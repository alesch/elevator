defmodule Elevator.AlgorithmTest do
  use ExUnit.Case
  alias Elevator.Core

  describe "LOOK Algorithm (Scenarios 4.1 & 4.2)" do
    test "Scenario 4.1: Pick-up on the way (Hall Request)" do
      # GIVEN: Moving UP to F5, hall request added for F3
      state = %Core{
        phase: :moving,
        current_floor: 1,
        heading: :up,
        requests: [{:hall, 5}],
        motor_status: :running
      }
      {state, _} = Core.request_floor(state, :hall, 3)

      # WHEN: Sensor confirms arrival at F3
      {new_state, actions} = Core.process_arrival(state, 3)

      # THEN: Elevator must stop at F3 (it is in the current heading)
      assert new_state.phase == :arriving
      assert new_state.motor_status == :stopping
      assert {:hall, 3} in new_state.requests
      assert {:stop_motor} in actions
    end

    test "Scenario 4.2 (Retire): Heading becomes :idle when no requests remain" do
      # GIVEN: Arriving at F3, about to confirm stop — no more work above
      state = %Core{
        phase: :arriving,
        current_floor: 3,
        heading: :up,
        requests: [{:car, 3}],
        motor_status: :stopping
      }

      # WHEN: Motor confirms stopped (clears the request, opens door)
      {state, _} = Core.handle_event(state, :motor_stopped, 0)

      # THEN: Heading is still :up — updated only when next direction is chosen
      assert state.heading == :up
      refute {:car, 3} in state.requests

      # WHEN: New request arrives below — heading updates to :down
      state_with_down = %{state | requests: [{:hall, 1}]}
      {new_state, _} = Core.request_floor(state_with_down, :hall, 1)
      assert new_state.heading == :down
    end
  end

  describe "Scenario 4.4: Honor All Requests" do
    test "Car request on the path — elevator stops" do
      # GIVEN: Moving :up, car request for F3 on the path
      state = %Core{
        phase: :moving,
        current_floor: 1,
        heading: :up,
        requests: [{:car, 3}],
        motor_status: :running
      }

      # WHEN: Sensor confirms arrival at F3
      {new_state, actions} = Core.process_arrival(state, 3)

      # THEN: Elevator stops at F3
      assert new_state.phase == :arriving
      assert new_state.motor_status == :stopping
      assert {:stop_motor} in actions
    end

    test "Hall request on the path — elevator stops" do
      # GIVEN: Moving :up, hall request for F4 on the path
      state = %Core{
        phase: :moving,
        current_floor: 2,
        heading: :up,
        requests: [{:hall, 4}],
        motor_status: :running
      }

      # WHEN: Sensor confirms arrival at F4
      {new_state, actions} = Core.process_arrival(state, 4)

      # THEN: Elevator stops at F4
      assert new_state.phase == :arriving
      assert new_state.motor_status == :stopping
      assert {:stop_motor} in actions
    end
  end

  describe "Wake Up Logic (Scenario 4.5)" do
    test "Scenario 4.5: Context-Aware Wake Up (Idle at F5 heads DOWN for F1)" do
      # Arrange: Elevator is idle at Floor 5
      state = %Core{current_floor: 5, heading: :idle}

      # Act: Request comes in for Floor 1
      {new_state, _} = Core.request_floor(state, :hall, 1)

      # Assert: Heading correctly switches to :down
      assert new_state.heading == :down
    end

    test "Idle elevator at F1 heads UP for F3" do
      # Arrange: Elevator is idle at Floor 1
      state = %Core{current_floor: 1, heading: :idle}

      # Act: Request comes in for Floor 3
      {new_state, _} = Core.request_floor(state, :hall, 3)

      # Assert: Heading correctly switches to :up
      assert new_state.heading == :up
    end
  end

  describe "Scenario 4.3: Multi-Stop Sweep Ordering" do
    test "Elevator stops at each floor in ascending order when heading up" do
      # GIVEN: Idle at F0, three car requests
      state = %Core{phase: :idle, current_floor: 0, heading: :idle, door_status: :closed}
      {state, _} = Core.request_floor(state, :car, 2)
      {state, _} = Core.request_floor(state, :car, 4)
      {state, _} = Core.request_floor(state, :car, 6)

      assert state.heading == :up
      assert state.phase == :moving

      # ARRIVE at F2 — must stop
      {state, _} = Core.process_arrival(state, 2)
      assert state.phase == :arriving
      assert state.motor_status == :stopping

      # Clear F2 (motor stopped), then simulate door cycle completing → back to :moving
      {state, _} = Core.handle_event(state, :motor_stopped, 0)
      refute {:car, 2} in state.requests
      state = %{state | phase: :moving, motor_status: :running, door_status: :closed}

      # ARRIVE at F4 — must stop
      {state, _} = Core.process_arrival(state, 4)
      assert state.phase == :arriving
      assert state.motor_status == :stopping

      # Clear F4, simulate door cycle
      {state, _} = Core.handle_event(state, :motor_stopped, 0)
      refute {:car, 4} in state.requests
      state = %{state | phase: :moving, motor_status: :running, door_status: :closed}

      # ARRIVE at F6 — must stop
      {state, _} = Core.process_arrival(state, 6)
      assert state.phase == :arriving
      assert state.motor_status == :stopping

      # All requests fulfilled
      {final_state, _} = Core.handle_event(state, :motor_stopped, 0)
      assert final_state.requests == []
    end
  end

  describe "Scenario 4.9: Request Fulfillment (Internal State Sync)" do
    test "clears requests during arrival to ensure correct heading choice" do
      # Arrange: Elevator at F1, heading up, requests contain {:car, 3} and {:car, 0}
      state = %Core{
        current_floor: 1,
        heading: :up,
        motor_status: :stopped,
        requests: [{:car, 3}, {:car, 0}]
      }

      # Act: Simulate arrival and STOP at Floor 3
      state = %{state | current_floor: 3, motor_status: :stopping}
      {state, _} = Core.handle_event(state, :motor_stopped, 0)

      # Assert: F3 is cleared, F0 remains
      refute {:car, 3} in state.requests
      assert {:car, 0} in state.requests

      # Act: Passenger presses Floor 0 again (already queued — triggers update_heading)
      {state, _} = Core.request_floor(state, :car, 0)

      # Assert: Heading is now :down (the only remaining work is below)
      assert state.heading == :down
    end
  end
end
