defmodule Elevator.EdgeCasesTest do
  use ExUnit.Case
  alias Elevator.Core

  describe "Scenario 4.6: Same-Floor Interaction" do
    test "Idle at F3 receives Car request for F3 -> Opens door immediately" do
      # Arrange: Idle at Floor 3, motor already stopped
      state = %Core{current_floor: 3, heading: :idle, motor_status: :stopped}

      # Act: Passenger inside presses Floor 3
      {new_state, actions} = Core.request_floor(state, :car, 3)

      # Assert: Motor stays :stopped (no braking cycle), door opens, request fulfilled
      assert new_state.motor_status == :stopped
      assert new_state.door_status == :opening
      refute {:car, 3} in new_state.requests
      assert {:open_door} in actions
    end

    test "Idle at F3 receives Hall request for F3 -> Opens door immediately" do
      state = %Core{current_floor: 3, heading: :idle, motor_status: :stopped}
      {new_state, actions} = Core.request_floor(state, :hall, 3)

      assert new_state.motor_status == :stopped
      assert new_state.door_status == :opening
      refute {:hall, 3} in new_state.requests
      assert {:open_door} in actions
    end
  end

  describe "Scenario 4.8: Boundary Floors (F1/F5)" do
    test "At F5 heading UP with no requests above -> Retire to :idle" do
      # Even if something set heading to :up (which shouldn't happen), update_heading must fix it
      state = %Core{current_floor: 5, heading: :up, requests: []}

      # Act: Force a heading update
      {new_state, _} = Core.request_floor(state, :car, 5)

      # Assert: Heading becomes :idle because there is nowhere higher to go
      assert new_state.heading == :idle
    end

    test "At F1 heading DOWN with no requests below -> Retire to :idle" do
      state = %Core{current_floor: 1, heading: :down, requests: []}
      {new_state, _} = Core.request_floor(state, :car, 1)

      assert new_state.heading == :idle
    end

    test "Extreme Reversal: At F5, request for F1 -> Heading becomes :down" do
      state = %Core{current_floor: 5, heading: :idle}
      {new_state, _} = Core.request_floor(state, :hall, 1)

      assert new_state.heading == :down
    end
  end
end
