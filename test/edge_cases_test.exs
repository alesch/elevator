defmodule Elevator.EdgeCasesTest do
  use ExUnit.Case
  alias Elevator.Core

  describe "Scenario 4.6: Same-Floor Interaction" do
    test "Idle at F3 receives Car request for F3 -> Opens door immediately" do
      # GIVEN: Idle at F3, doors closed, motor stopped
      state = %Core{phase: :idle, current_floor: 3, heading: :idle, motor_status: :stopped, door_status: :closed}

      # WHEN: Passenger inside presses Floor 3
      {new_state, actions} = Core.request_floor(state, :car, 3)

      # THEN: No braking cycle needed; door opens immediately; request fulfilled; phase :arriving
      assert new_state.phase == :arriving
      assert new_state.motor_status == :stopped
      assert new_state.door_status == :opening
      refute {:car, 3} in new_state.requests
      assert {:open_door} in actions
    end

    test "Idle at F3 receives Hall request for F3 -> Opens door immediately" do
      # GIVEN: Idle at F3, doors closed, motor stopped
      state = %Core{phase: :idle, current_floor: 3, heading: :idle, motor_status: :stopped, door_status: :closed}

      # WHEN: Hall call for F3
      {new_state, actions} = Core.request_floor(state, :hall, 3)

      # THEN: Same as car — no braking cycle, door opens, request fulfilled, phase :arriving
      assert new_state.phase == :arriving
      assert new_state.motor_status == :stopped
      assert new_state.door_status == :opening
      refute {:hall, 3} in new_state.requests
      assert {:open_door} in actions
    end
  end

  describe "Scenario 4.8: Boundary Reversals" do
    test "At F5 heading UP with no requests above -> Retire to :idle" do
      # GIVEN: Idle at F5 (top), doors closed
      state = %Core{phase: :idle, current_floor: 5, heading: :up, requests: [], door_status: :closed}

      # WHEN: Same-floor request forces heading update
      {new_state, _} = Core.request_floor(state, :car, 5)

      # THEN: Heading becomes :idle — nowhere higher to go
      assert new_state.heading == :idle
    end

    test "At F1 heading DOWN with no requests below -> Retire to :idle" do
      # GIVEN: Idle at F1 (bottom), doors closed
      state = %Core{phase: :idle, current_floor: 1, heading: :down, requests: [], door_status: :closed}

      {new_state, _} = Core.request_floor(state, :car, 1)

      assert new_state.heading == :idle
    end

    test "Extreme Reversal: At F5, request for F1 -> Heading becomes :down" do
      # GIVEN: Idle at F5, doors closed
      state = %Core{phase: :idle, current_floor: 5, heading: :idle, door_status: :closed}

      {new_state, _} = Core.request_floor(state, :hall, 1)

      assert new_state.heading == :down
    end
  end
end
