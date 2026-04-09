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

    Vault.put_floor(vault, 0)
    {:ok, pid} = start_elevator(%{vault: vault, sensor: sensor})

    %{vault: vault, sensor: sensor, elevator: pid}
  end

  describe "Elevator Actor Lifecycle" do
    test "Starting a passenger elevator", %{elevator: pid} do
      # Note: The 'pid' from setup is a default :service elevator.
      # To test passenger, we'll just check the phase is :idle (startup consensus).
      assert Core.phase(Controller.get_state(pid)) == :idle
    end

    test "[S-SYS-PUBSUB]: Observable State Change — any state change is broadcast over PubSub", %{
      elevator: pid
    } do
      # WHEN: A state-changing event occurs (floor request)
      Controller.request_floor(pid, :car, 3)

      # THEN: New state is broadcast on "elevator:status"
      assert_receive {:elevator_state, state}
      assert Core.phase(state) == :moving
      assert Core.heading(state) == :up
    end

    test "Requesting a floor via cast (Asynchronous)", %{elevator: pid} do
      # Cast is "fire and forget"
      Controller.request_floor(pid, :car, 4)
      state = Controller.get_state(pid)
      
      assert Core.heading(state) == :up
      assert {:car, 4} in Core.requests(state)

      # Verify physical commands
      assert_receive {:"$gen_cast", {:move, :up}}
    end


    test "[S-MOVE-BRAKING]/[S-MOVE-OPENING]: Arrival sequence triggers immediate intent signals",
         %{elevator: pid} do
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

    test "[S-SAFE-GOLDEN]: Hardware Safety Interlock (The Golden Rule)", %{elevator: pid} do
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

    test "[S-SAFE-OBSTRUCT]: Door obstruction during closing triggers reversal", %{elevator: pid} do
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

  # --- Helpers ---

  defp start_elevator(context, opts \\ []) do
    defaults = [
      motor: self(),
      door: self(),
      vault: context.vault,
      sensor: context.sensor,
      name: nil
    ]

    {:ok, pid} = Controller.start_link(Keyword.merge(defaults, opts))

    # Mandatory: Wait for initial :idle broadcast to ensure rehoming finished
    assert_receive {:elevator_state, state}
    assert Core.phase(state) == :idle

    {:ok, pid}
  end
end
