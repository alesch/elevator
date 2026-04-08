defmodule Elevator.EdgeCasesTest do
  use ExUnit.Case
  alias Elevator.Core

  describe "[S-MOVE-SAME-FLOOR]: Same-Floor Interaction" do
    # REVISE: Align with [S-MOVE-SAME-FLOOR] behavioral scenario (Request on the current floor).
    test "Idle at F3 receives Car request for F3 -> Opens door immediately" do
      # GIVEN: Idle at F3, doors closed, motor stopped
      state = Core.idle_at(3)

      # WHEN: Passenger inside presses Floor 3
      {new_state, actions} = Core.request_floor(state, :car, 3)

      # THEN: No braking cycle needed; door opens immediately; request fulfilled; phase :arriving
      assert Core.phase(new_state) == :arriving
      assert Core.motor_status(new_state) == :stopped
      assert Core.door_status(new_state) == :opening
      refute {:car, 3} in Core.requests(new_state)
      assert {:open_door} in actions
    end

    test "Idle at F3 receives Hall request for F3 -> Opens door immediately" do
      # GIVEN: Idle at F3, doors closed, motor stopped
      state = Core.idle_at(3)

      # WHEN: Hall call for F3
      {new_state, actions} = Core.request_floor(state, :hall, 3)

      # THEN: Same as car — no braking cycle, door opens, request fulfilled, phase :arriving
      assert Core.phase(new_state) == :arriving
      assert Core.motor_status(new_state) == :stopped
      assert Core.door_status(new_state) == :opening
      refute {:hall, 3} in Core.requests(new_state)
      assert {:open_door} in actions
    end
  end

  test "Extreme Reversal: At F5, request for F1 -> Heading becomes :down" do
    # GIVEN: Idle at F5, doors closed
    state = Core.idle_at(5)

    {new_state, _} = Core.request_floor(state, :hall, 1)

    assert Core.heading(new_state) == :down
  end
end
