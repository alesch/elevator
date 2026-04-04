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

  describe "Scenario 4.7: Weight Thresholds & Bypass" do
    test "Exactly 900kg -> Should BYPASS Hall Request" do
      # Rule 1.5: If weight > 900kg, bypass. (We'll check if we want 'greater than' or 'greater than or equal')
      # Our Rule 1.5 says '> 900kg'. So 900kg should actually STOP.
      state = %Core{current_floor: 1, heading: :up, requests: [{:car, 5}], weight: 900}

      # Hall call at F3
      {new_state, _} = Core.request_floor(state, :hall, 3)

      # Move to F3
      arrived_state = %{new_state | current_floor: 3}
      {processed_state, _} = Core.process_current_floor(arrived_state)

      # Assert: It should STOP at 900kg because rule is '> 900'
      assert processed_state.motor_status == :stopping
    end

    test "Over Weight Limit (1001kg) -> Should be :overload" do
      state = Core.new_passenger()
      {new_state, _} = Core.update_weight(state, 1001)

      assert new_state.status == :overload
    end

    test "Exactly at Weight Limit (1000kg) -> Should be :normal" do
      state = Core.new_passenger()
      {new_state, _} = Core.update_weight(state, 1000)

      assert new_state.status == :normal
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
