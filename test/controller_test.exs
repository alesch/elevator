defmodule Elevator.ControllerTest do
  @moduledoc """
  Functional Tests for the Elevator Controller Architecture.
  """
  use ExUnit.Case, async: false
  alias Elevator.{Controller, Vault, Core}
  alias Elevator.Hardware.Sensor

  setup do
    # Start dependencies with name: nil to allow parallel isolation
    vault = start_supervised!({Vault, [name: nil]})
    sensor = start_supervised!({Sensor, [vault: vault, name: nil]})

    # Subscribe to status for real-time monitoring
    Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:status")

    # Pre-seed the Vault & Sensor to F0 so we start in :normal status for standard tests
    Vault.put_floor(vault, 0)

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
      # Normalized: Reaches :idle immediately due to setup pre-seeding vault to F0
      assert Core.phase(state) == :idle
    end

    test "[S-SYS-PUBSUB]: Observable State Change — any state change is broadcast over PubSub", %{
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

      # Wait for initial broadcast from handle_continue
      assert_receive {:elevator_state, state}
      assert Core.phase(state) == :idle

      # WHEN: A state-changing event occurs (floor request)
      Controller.request_floor(pid, :car, 3)

      # THEN: New state is broadcast on "elevator:status"
      assert_receive {:elevator_state, state}
      assert Core.phase(state) == :moving
      assert Core.heading(state) == :up
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
      
      assert Core.heading(state) == :up
      assert {:car, 4} in Core.requests(state)

      # Verify physical commands
      assert_receive {:"$gen_cast", {:move, :up}}
    end

    test "[S-MOVE-BASE]: Return to Base (Inactivity Timeout)", %{
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

      # 2. Verify Logic (Action)
      send(pid, :return_to_base)

      # Pulse 1: Transition to :arriving (Request for F0) and door opening
      assert_receive {:elevator_state, state}
      assert Core.phase(state) == :arriving
      assert Core.door_status(state) == :opening
      assert_receive {:"$gen_cast", :open}
    end

    test "[S-MOVE-BRAKING]/[S-MOVE-OPENING]: Arrival sequence triggers immediate intent signals",
         %{
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

      # 1. Start moving to F3
      Controller.request_floor(pid, :car, 3)
      assert_receive {:"$gen_cast", {:move, :up}}

      # 2. Simulate arrival pulse at F3
      send(pid, {:floor_arrival, 3})

      # ASSERT 1: Physical stop command sent
      assert_receive {:"$gen_cast", :stop_now}
      # ASSERT 2: Immediate :arriving intent
      assert_receive {:elevator_state, state}
      assert Core.phase(state) == :arriving
      assert Core.motor_status(state) == :stopping
      assert Core.current_floor(state) == 3

      # 3. Confirm motor is stopped
      send(pid, :motor_stopped)

      # ASSERT 3: Physical open command sent
      assert_receive {:"$gen_cast", :open}
      # ASSERT 4: Immediate :opening intent
      assert_receive {:elevator_state, state}
      assert Core.phase(state) == :arriving
      assert Core.motor_status(state) == :stopped
      assert Core.door_status(state) == :opening
    end

    test "[S-SAFE-GOLDEN]: Hardware Safety Interlock (The Golden Rule)", %{
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

      # 1. Start moving (to F3)
      Controller.request_floor(pid, :car, 3)
      assert_receive {:"$gen_cast", {:move, :up}}

      # 2. While moving, force doors open (e.g. key override)
      # Logic: Motor MUST stop. Pulse Architecture ensures this via enforce_the_golden_rule
      send(pid, :door_opened)
      assert_receive {:"$gen_cast", :stop_now}
      assert_receive {:elevator_state, state}
      assert Core.motor_status(state) == :stopped
    end

    test "[S-SAFE-OBSTRUCT]: Door obstruction during closing triggers reversal", %{
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

      # Wait for initial broadcast
      assert_receive {:elevator_state, state}
      assert Core.phase(state) == :idle
      assert Core.current_floor(state) == 0

      # 1. Start with doors OPEN
      send(pid, :return_to_base)
      assert_receive {:"$gen_cast", :open}
      send(pid, :door_opened)
      
      assert_receive {:elevator_state, state}
      assert Core.phase(state) == :docked
      assert Core.door_status(state) == :open

      # 2. Trigger a close (by requesting another floor)
      Controller.request_floor(pid, :car, 3)
      
      # Pulse: Heading shifts up
      assert_receive {:elevator_state, state}
      assert Core.heading(state) == :up
      
      # Step 2: Simulate timeout fires → begins closing
      send(pid, {:timeout, :door_timeout})
      assert_receive {:"$gen_cast", :close}
      assert_receive {:elevator_state, state}
      assert Core.door_status(state) == :closing

      # 3. Simulate obstruction
      send(pid, :door_obstructed)

      # ASSERT: Hardware receives OPEN command (Reversal)
      assert_receive {:"$gen_cast", :open}

      # ASSERT: Phase reverts to :arriving (The Broker) and door opens
      assert_receive {:elevator_state, state}
      assert Core.phase(state) == :arriving
      assert Core.door_status(state) == :opening
    end
  end
end
