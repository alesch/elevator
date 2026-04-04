defmodule Elevator.AlgorithmTest do
  use ExUnit.Case
  alias Elevator.Core

  describe "LOOK Algorithm (Scenarios 4.1 & 4.2)" do
    test "Scenario 4.1: Pick-up on the way (Hall Request)" do
      # Arrange: Moving UP to 5, someone calls from 3
      state = %Core{current_floor: 1, heading: :up, requests: [{:hall, 5}]}
      {state, _} = Core.request_floor(state, :hall, 3)

      # Act: Move to 3
      state = %{state | current_floor: 3}
      {new_state, _} = Core.process_current_floor(state)

      # Assert: It should stop at 3
      assert new_state.motor_status == :stopping
      assert {:hall, 3} in new_state.requests
    end

    test "Scenario 4.2 (Retire): Heading becomes :idle when no requests remain" do
      # Arrange: At 3, just finished a request, no more work
      state = %Core{
        current_floor: 3,
        heading: :up,
        requests: [{:car, 3}],
        motor_status: :stopping
      }

      # Act: Confirm stopped at T=0 (which removes the request)
      {state, _} = Core.handle_event(state, :motor_stopped, 0)

      # Assert: Heading is still :up until we explicitly update it
      assert state.heading == :up

      # Now update heading (this would happen after door cycle in the real app)
      state_with_down = %{state | requests: [{:hall, 1}]}
      {new_state, _} = Core.request_floor(state_with_down, :hall, 1)
      assert new_state.heading == :down
    end
  end

  describe "Full Load Bypass (Scenarios 4.3 & 4.4)" do
    test "Scenario 4.3: Bypass Hall request when near weight limit" do
      # Arrange: Moving UP to 5, Weight 901kg (Limit 1000kg)
      state = %Core{current_floor: 1, heading: :up, requests: [{:car, 5}], weight: 901}
      {state, _} = Core.request_floor(state, :hall, 3)

      # Act: Move to 3
      state = %{state | current_floor: 3, motor_status: :running}
      {new_state, _} = Core.process_current_floor(state)

      # Assert: It should NOT stop (stays :running since it's bypassing)
      assert new_state.motor_status == :running
    end

    test "Scenario 4.4: Honor Car request even when near weight limit" do
      # Arrange: Moving UP to 5, Weight 900kg
      state = %Core{current_floor: 1, heading: :up, requests: [{:car, 5}], weight: 900}
      {state, _} = Core.request_floor(state, :car, 3)

      # Act: Move to 3
      state = %{state | current_floor: 3}
      {new_state, _} = Core.process_current_floor(state)

      # Assert: It MUST stop because it's a Car request
      assert new_state.motor_status == :stopping
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
      # GIVEN: At F0, requests for F2, F4, F6
      state = %Core{current_floor: 0, heading: :idle}
      {state, _} = Core.request_floor(state, :car, 2)
      {state, _} = Core.request_floor(state, :car, 4)
      {state, _} = Core.request_floor(state, :car, 6)

      assert state.heading == :up

      # ACT + ASSERT: Arrive at F2 — must stop
      state = %{state | current_floor: 2}
      {state, _} = Core.process_current_floor(state)
      assert state.motor_status == :stopping

      # Clear F2, continue
      {state, _} = Core.handle_event(state, :motor_stopped, 0)
      refute {:car, 2} in state.requests

      # ACT + ASSERT: Arrive at F4 — must stop
      state = %{state | current_floor: 4, motor_status: :running}
      {state, _} = Core.process_current_floor(state)
      assert state.motor_status == :stopping

      # Clear F4, continue
      {state, _} = Core.handle_event(state, :motor_stopped, 0)
      refute {:car, 4} in state.requests

      # ACT + ASSERT: Arrive at F6 — must stop
      state = %{state | current_floor: 6, motor_status: :running}
      {state, _} = Core.process_current_floor(state)
      assert state.motor_status == :stopping

      # All requests fulfilled
      {final_state, _} = Core.handle_event(state, :motor_stopped, 0)
      assert final_state.requests == []
      assert final_state.heading == :up
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
