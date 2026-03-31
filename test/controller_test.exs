defmodule Elevator.ControllerTest do
  @moduledoc """
  Functional Tests for the Elevator Controller Architecture.
  """
  use ExUnit.Case, async: false
  alias Elevator.{Controller, Vault}
  alias Elevator.Hardware.Sensor

  setup do
    # Start dependencies with name: nil to allow parallel isolation
    vault = start_supervised!({Vault, [name: nil]})
    sensor = start_supervised!({Sensor, [vault: vault, name: nil]})

    # Pre-seed the Vault & Sensor to F1 so we start in :normal status for standard tests
    Vault.put_floor(vault, 1)

    %{vault: vault, sensor: sensor}
  end

  describe "Elevator Actor Lifecycle" do
    test "Starting a passenger elevator", %{vault: vault, sensor: sensor} do
      # Note: motor and door are self() for command capture
      {:ok, pid} =
        Controller.start_link(
          type: :passenger,
          motor: self(),
          door: self(),
          vault: vault,
          sensor: sensor,
          name: nil
        )

      # Barrier to ensure handle_continue finishes
      _ = Controller.get_state(pid)

      state = Controller.get_state(pid)
      assert state.status == :normal
      assert state.current_floor == 1
    end

    test "Requesting a floor via cast (Asynchronous)", %{vault: vault, sensor: sensor} do
      {:ok, pid} =
        Controller.start_link(
          motor: self(),
          door: self(),
          vault: vault,
          sensor: sensor,
          name: nil
        )

      # Barrier to ensure handle_continue finishes
      _ = Controller.get_state(pid)

      # Cast is "fire and forget"
      Controller.request_floor(pid, :car, 4)
      state = Controller.get_state(pid)
      assert state.heading == :up
      assert {:car, 4} in state.requests

      # Verify physical commands (With the new 3-element tuple for Motor)
      assert_receive {:"$gen_cast", {:move, :up, []}}
      assert_receive {:"$gen_cast", :close}
    end

    test "Handling concurrent requests (Race Condition Proof)", %{vault: vault, sensor: sensor} do
      {:ok, pid} =
        Controller.start_link(
          motor: self(),
          door: self(),
          vault: vault,
          sensor: sensor,
          name: nil
        )

      # Barrier to ensure handle_continue finishes
      _ = Controller.get_state(pid)

      # Simulate parallel button presses
      tasks =
        for i <- 1..5 do
          Task.async(fn -> Controller.request_floor(pid, :hall, i) end)
        end

      # Wait for all "fingers" to finish
      Enum.each(tasks, &Task.await/1)

      state = Controller.get_state(pid)

      unique_targets = Enum.map(state.requests, fn {_, f} -> f end) |> Enum.sort()
      assert unique_targets == [1, 2, 3, 4, 5]
    end

    test "Rule 1.4: Inactivity Window (Deterministic Verification)", %{
      vault: vault,
      sensor: sensor
    } do
      {:ok, pid} =
        Controller.start_link(
          motor: self(),
          door: self(),
          vault: vault,
          sensor: sensor,
          name: nil
        )

      # Barrier to ensure handle_continue finishes
      _ = Controller.get_state(pid)

      # 1. Verify Scheduling (Intent)
      timer_ref = Controller.get_timer_ref(pid)
      assert is_reference(timer_ref)

      # 2. Verify Logic (Action)
      send(pid, :return_to_base)

      # barrier
      state = Controller.get_state(pid)
      assert {:hall, 1} in state.requests
    end

    test "Arrival at target floor stops the motor", %{vault: vault, sensor: sensor} do
      {:ok, pid} =
        Controller.start_link(
          motor: self(),
          door: self(),
          vault: vault,
          sensor: sensor,
          name: nil
        )

      _ = Controller.get_state(pid)

      # 1. Request Floor 3
      Controller.request_floor(pid, :car, 3)
      assert_receive {:"$gen_cast", {:move, :up, []}}

      # 2. Simulate arrival at Floor 3
      send(pid, {:floor_arrival, 3})

      # 3. Assert motor received stop message
      assert_receive {:"$gen_cast", :stop_now}
      assert_receive {:"$gen_cast", :open} # Door should open
    end

    test "Overshoot safety: passing the target floor stops the motor", %{
      vault: vault,
      sensor: sensor
    } do
      {:ok, pid} =
        Controller.start_link(
          motor: self(),
          door: self(),
          vault: vault,
          sensor: sensor,
          name: nil
        )

      _ = Controller.get_state(pid)

      # 1. Request Floor 3
      Controller.request_floor(pid, :car, 3)
      assert_receive {:"$gen_cast", {:move, :up, []}}

      # 2. Simulate overshooting to Floor 4
      send(pid, {:floor_arrival, 4})

      # 3. Assert safety stop
      assert_receive {:"$gen_cast", :stop_now}
    end
  end
end
