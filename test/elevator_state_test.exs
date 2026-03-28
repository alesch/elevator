defmodule Elevator.StateTest do
  use ExUnit.Case
  alias Elevator.State

  test "initial state has floor 1 and is idle" do
    state = %State{}
    assert state.current_floor == 1
    assert state.direction == :idle
  end

  test "we can create a state with a specific floor" do
    state = %State{current_floor: 3}
    assert state.current_floor == 3
  end
end
