defmodule Elevator.CoreTest do
  use ExUnit.Case, async: true
  alias Elevator.Core

  test "initial state has floor :unknown and is booting" do
    state = %Core{}
    assert state.current_floor == :unknown
    assert state.phase == :booting
  end

  test "requesting floor during booting is ignored" do
    state = %Core{phase: :booting}
    {new_state, actions} = Core.request_floor(state, :car, 3)
    assert new_state == state
    assert actions == []
  end

  test "recovery_complete moves from booting to idle" do
    state = %Core{phase: :booting}
    {new_state, actions} = Core.handle_event(state, :recovery_complete, 0)
    assert new_state.phase == :idle
    assert new_state.current_floor == 0
    assert actions == []
  end

  describe "Door Safety and The Arriving Gateway" do
    test "obstruction while closing triggers reversal through :arriving broker" do
      # GIVEN: Elevator at F0, phase: :moving (implied by :closing doors)
      state = %Core{
        phase: :leaving,
        current_floor: 0,
        door_status: :closing,
        motor_status: :stopped
      }

      # WHEN: Obstruction detected
      {state, actions} = Core.handle_event(state, :door_obstructed, 0)

      # THEN: Must pulse through :arriving (The Broker)
      # FIRST PULSE: handle_event sets :obstructed
      # transit(obstructed) -> sets phase: :arriving
      # SECOND PULSE: transit(arriving + motor_stopped + obstructed) -> sets :opening
      assert state.phase == :arriving
      assert state.door_status == :opening
      assert {:open_door} in actions
    end
  end
end
