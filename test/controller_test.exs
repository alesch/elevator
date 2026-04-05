defmodule Elevator.ControllerTest do
  @moduledoc """
  Functional Tests for the Elevator Controller Architecture.
  """
  use ExUnit.Case, async: false
  alias Elevator.{Controller, Vault}
  alias Elevator.Hardware.{Door, Sensor}

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
      assert state.phase == :idle
      assert state.current_floor == 0
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

      # WHEN: A state-changing event occurs (floor request)
      Controller.request_floor(pid, :car, 3)

      # THEN: New state is broadcast on "elevator:status" — match specifically on :moving phase
      assert_receive {:elevator_state, %{phase: :moving, heading: :up}}
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

      # Verify physical commands
      assert_receive {:"$gen_cast", {:move, :up}}

      # NOTE: Door is already closed at Floor 1 startup, so no redundant command is sent.
      refute_receive {:"$gen_cast", :close}
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

      # Simulate parallel button presses (avoid floor 0 — elevator starts there,
      # so that request is fulfilled immediately and won't appear in the queue)
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

      # 1. Verify Scheduling (Intent)
      timer_ref = Controller.get_timer_ref(pid)
      assert is_reference(timer_ref)

      # 2. Verify Logic (Action)
      # Elevator starts at F1 (motor already stopped). return_to_base sends :hall 1.
      # Since we're already at F1 with motor stopped, the request is fulfilled immediately
      # and the door opens — no :stopping cycle needed.
      send(pid, :return_to_base)

      # barrier
      state = Controller.get_state(pid)
      assert state.door_status == :opening
      assert state.requests == []
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

      # 1.1 First, it broadcasts we are moving
      assert_receive {:elevator_state, %{motor_status: :running}}
      # 1.2 Then, it dispatches hardware
      assert_receive {:"$gen_cast", {:move, :up}}

      # 2. Simulate arrival pulse at F3
      send(pid, {:floor_arrival, 3})

      # ASSERT 1: Physical stop command sent
      assert_receive {:"$gen_cast", :stop_now}

      # ASSERT 2: Immediate :stopping intent
      assert_receive {:elevator_state, %{motor_status: :stopping, current_floor: 3}}

      # 3. Confirm motor is stopped
      send(pid, :motor_stopped)

      # ASSERT 3: Physical open command sent
      assert_receive {:"$gen_cast", :open}

      # ASSERT 4: Immediate :opening intent
      assert_receive {:elevator_state, %{motor_status: :stopped, door_status: :opening}}

      # 4. Confirm door is opened
      send(pid, :door_opened)

      # ASSERT 5: Final confirmed state
      assert_receive {:elevator_state, %{door_status: :open}}
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
      assert_receive {:"$gen_cast", {:move, :up}}

      # 2. Simulate overshooting to Floor 4
      send(pid, {:floor_arrival, 4})

      # 3. Assert safety stop
      assert_receive {:"$gen_cast", :stop_now}
    end

    test "[S-REQ-SPAM]: Button Spamming is ignored SILENTLY", %{vault: vault, sensor: sensor} do
      {:ok, pid} =
        Controller.start_link(
          motor: self(),
          door: self(),
          vault: vault,
          sensor: sensor,
          name: nil
        )

      _ = Controller.get_state(pid)

      # 1. First request for F3
      # We use capture_log to ensure NO warnings are emitted
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          Controller.request_floor(pid, :car, 3)
          # Barrier for message processing
          _ = Controller.get_state(pid)
        end)

      # Verify request was added
      state = Controller.get_state(pid)
      assert length(state.requests) == 1
      assert log == ""

      # 2. Mashing the same button
      log2 =
        capture_log(fn ->
          Controller.request_floor(pid, :car, 3)
          _ = Controller.get_state(pid)
        end)

      # Verify queue didn't grow and NO Log was emitted
      state2 = Controller.get_state(pid)
      assert length(state2.requests) == 1
      assert log2 == ""
    end

    test "[S-SYS-REDUNDANT]: Actor Redundancy triggers LOUD warnings (Hardware Layer)", %{
      vault: vault
    } do
      import ExUnit.CaptureLog

      # Prove hardware actors we control have warnings
      {:ok, door} = Door.start_link(vault: vault, name: nil)

      # Wait for init
      _ = Door.get_state(door)

      # Dispatch two identical opens
      log =
        capture_log(fn ->
          GenServer.cast(door, :open)
          GenServer.cast(door, :open)
          # Give it a moment to process mailbox and log
          Process.sleep(50)
        end)

      # Verify warning is captured for the redundant command
      assert log =~ "Hardware: Redundant Door Open"
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

      # 1. Get to :docked phase — request same floor (F0) to open door without motor cycle
      Controller.request_floor(pid, :car, 0)
      assert_receive {:"$gen_cast", :open}
      send(pid, :door_opened)
      assert_receive {:elevator_state, %{phase: :docked, door_status: :open}}

      # 2. While docked, add a request for F3
      Controller.request_floor(pid, :car, 3)
      assert_receive {:elevator_state, %{heading: :up, door_status: :open}}

      # ASSERT: Motor is NOT commanded to move — door is still open
      refute_receive {:"$gen_cast", {:move, :up}}, 100

      # 3. Timeout fires → door begins closing (phase: :leaving)
      send(pid, {:timeout, :door_timeout})
      assert_receive {:"$gen_cast", :close}

      assert_receive {:elevator_state,
                      %{phase: :leaving, door_status: :closing, motor_status: :stopped}}

      # ASSERT: Motor still NOT moving during closing
      refute_receive {:"$gen_cast", {:move, :up}}, 100

      # 4. Door confirms closed → phase: :moving, motor starts
      send(pid, :door_closed)
      assert_receive {:"$gen_cast", {:move, :up}}

      assert_receive {:elevator_state,
                      %{phase: :moving, motor_status: :running, door_status: :closed}}
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

      # 1. Start with doors OPEN
      send(pid, :motor_stopped)
      # Wait for the cast :open (initial arrival)
      assert_receive {:"$gen_cast", :open}
      send(pid, :door_opened)

      # 2. Trigger a close (by requesting another floor)
      Controller.request_floor(pid, :car, 3)

      # Drain startup
      assert_receive {:elevator_state, %{door_status: :opening}}
      assert_receive {:elevator_state, %{door_status: :open}}

      # Sim timeout
      send(pid, {:timeout, :door_timeout})

      assert_receive {:"$gen_cast", :close}
      assert_receive {:elevator_state, %{door_status: :closing}}

      # 3. Simulate obstruction
      send(pid, :door_obstructed)

      # ASSERT: Hardware receives OPEN command (Reversal)
      assert_receive {:"$gen_cast", :open}

      # ASSERT: State shows :opening
      assert_receive {:elevator_state, %{door_status: :opening, door_sensor: :blocked}}
    end
  end
end
