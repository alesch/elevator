defmodule Elevator.PhaseTransitionsTest do
  use ExUnit.Case
  alias Elevator.Core

  # Scenario 8.1
  test "Scenario 8.1: :idle → :moving on request for a different floor" do
    state = %Core{phase: :idle, door_status: :closed, current_floor: 0}

    {new_state, actions} = Core.request_floor(state, :car, 3)

    assert new_state.phase == :moving
    assert new_state.motor_status == :running
    assert new_state.heading == :up
    assert {:move_motor, :up, :normal} in actions
  end
end
