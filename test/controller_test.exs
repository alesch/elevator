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
      # Normalized: Reaches :idle immediately due to setup pre-seeding vault to F0
      assert state.phase == :idle
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

      # Mandatory boot handshake
      send(pid, {:recovery_complete, 0})
      assert_receive {:elevator_state, %{phase: :idle}}

      # WHEN: A state-changing event occurs (floor request)
      Controller.request_floor(pid, :car, 3)

      # THEN: New state is broadcast on "elevator:status"
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
      send(pid, {:recovery_complete, 0})

      # Cast is "fire and forget"
      Controller.request_floor(pid, :car, 4)
      state = Controller.get_state(pid)
      assert state.heading == :up
      assert {:car, 4} in state.requests

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
      send(pid, {:recovery_complete, 0})

      # 2. Verify Logic (Action)
      send(pid, :return_to_base)

      # Pulse 1: Transition to :arriving (Request for F0)
      assert_receive {:elevator_state, %{phase: :arriving}}
      # Pulse 2: At-floor stop confirms door opening cycle begins
      assert_receive {:"$gen_cast", :open}
      assert_receive {:elevator_state, %{door_status: :opening}}
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
      send(pid, {:recovery_complete, 0})

      # 1. Start moving to F3
      Controller.request_floor(pid, :car, 3)
      assert_receive {:"$gen_cast", {:move, :up}}

      # 2. Simulate arrival pulse at F3
      send(pid, {:floor_arrival, 3})

      # ASSERT 1: Physical stop command sent
      assert_receive {:"$gen_cast", :stop_now}
      # ASSERT 2: Immediate :arriving intent
      assert_receive {:elevator_state, %{motor_status: :stopping, current_floor: 3}}

      # 3. Confirm motor is stopped
      send(pid, :motor_stopped)

      # ASSERT 3: Physical open command sent
      assert_receive {:"$gen_cast", :open}
      # ASSERT 4: Immediate :opening intent
      assert_receive {:elevator_state, %{motor_status: :stopped, door_status: :opening}}
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
      send(pid, {:recovery_complete, 0})

      # 1. Start moving (to F3)
      Controller.request_floor(pid, :car, 3)
      assert_receive {:"$gen_cast", {:move, :up}}

      # 2. While moving, force doors open (e.g. key override)
      # Logic: Motor MUST stop. Pulse Architecture ensures this via enforce_the_golden_rule
      send(pid, :door_opened)
      assert_receive {:"$gen_cast", :stop_now}
      assert_receive {:elevator_state, %{motor_status: :stopped}}
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

      # 0. Hardware Recovery (Mandatory to exit :booting)
      send(pid, {:recovery_complete, 0})
      assert_receive {:elevator_state, %{phase: :idle, current_floor: 0}}

      # 1. Start with doors OPEN
      send(pid, :motor_stopped)
      # Wait for the cast :open (initial arrival)
      assert_receive {:"$gen_cast", :open}
      send(pid, :door_opened)
      assert_receive {:elevator_state, %{phase: :docked, door_status: :open}}

      # 2. Trigger a close (by requesting another floor)
      Controller.request_floor(pid, :car, 3)
      
      # Pulse 1: Heading shifts up
      assert_receive {:elevator_state, %{heading: :up}}
      
      # Step 2: Simulate timeout fires → begins closing
      send(pid, {:timeout, :door_timeout})
      assert_receive {:"$gen_cast", :close}
      assert_receive {:elevator_state, %{door_status: :closing}}

      # 3. Simulate obstruction
      send(pid, :door_obstructed)

      # ASSERT: Hardware receives OPEN command (Reversal)
      assert_receive {:"$gen_cast", :open}

      # ASSERT: Phase reverts to :arriving (The Broker)
      assert_receive {:elevator_state, %{phase: :arriving, door_status: :obstructed}}
    end
  end
end
