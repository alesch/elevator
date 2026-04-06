defmodule Elevator.EdgeCasesTest do
  use ExUnit.Case
  alias Elevator.Core

  describe "[S-MOVE-SAME-FLOOR]: Same-Floor Interaction" do
    # REVISE: Align with [S-MOVE-SAME-FLOOR] behavioral scenario (Request on the current floor).
    test "Idle at F3 receives Car request for F3 -> Opens door immediately" do
      # GIVEN: Idle at F3, doors closed, motor stopped
      state = %Core{
        phase: :idle,
        current_floor: 3,
        heading: :idle,
        motor_status: :stopped,
        door_status: :closed
      }

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
      state = %Core{
        phase: :idle,
        current_floor: 3,
        heading: :idle,
        motor_status: :stopped,
        door_status: :closed
      }

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

  test "Extreme Reversal: At F5, request for F1 -> Heading becomes :down" do
    # GIVEN: Idle at F5, doors closed
    state = %Core{phase: :idle, current_floor: 5, heading: :idle, door_status: :closed}

    {new_state, _} = Core.request_floor(state, :hall, 1)

    assert new_state.heading == :down
  end
end
