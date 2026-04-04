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

  # Scenario 8.2
  test "Scenario 8.2: :moving → :arriving when target floor reached" do
    state = %Core{phase: :moving, heading: :up, requests: [{:car, 3}], current_floor: 2}

    {new_state, actions} = Core.process_arrival(state, 3)

    assert new_state.phase == :arriving
    assert new_state.motor_status == :stopping
    assert {:stop_motor} in actions
  end
end
