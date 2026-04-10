defmodule Elevator.CoreTest do
  use ExUnit.Case, async: true
  alias Elevator.Core

  test "initial state has floor :unknown and is booting" do
    state = Core.init()
    assert Core.current_floor(state) == :unknown
    assert Core.phase(state) == :booting
  end

  test "requesting floor during booting is ignored" do
    state = Core.init()
    {new_state, actions} = Core.request_floor(state, :car, 3)
    assert new_state == state
    assert actions == []
  end

  test "recovery_complete moves from booting to idle" do
    state = Core.init()
    {new_state, actions} = Core.handle_event(state, :recovery_complete, 0)
    assert Core.phase(new_state) == :idle
    assert Core.current_floor(new_state) == 0
    assert actions == []
  end

  describe "Door Safety and The Arriving Gateway" do
    test "obstruction while closing triggers reversal through :arriving broker" do
      # GIVEN: Elevator at F0, phase: :leaving, doors closing
      state =
        Core.init()
        |> put_in([Access.key(:logic), :phase], :leaving)
        |> put_in([Access.key(:hardware), :current_floor], 0)
        |> put_in([Access.key(:hardware), :door_status], :closing)

      # WHEN: Obstruction detected
      {state, actions} = Core.handle_event(state, :door_obstructed, 0)

      # THEN: Must pulse through :arriving (The Broker)
      # FIRST PULSE: handle_event sets hardware as :obstructed
      # transit(obstructed) -> sets phase: :arriving
      # SECOND PULSE: Because FICS separates logic from hardware, reality remains :obstructed until hardware responds.
      assert Core.phase(state) == :arriving
      assert Core.door_status(state) == :obstructed
      assert {:open_door} in actions
    end
  end
end
