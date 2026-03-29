defmodule Elevator.StateTest do
  use ExUnit.Case
  alias Elevator.State

  test "initial state has floor 1 and is idle" do
    state = %State{}
    assert state.current_floor == 1
    assert state.heading == :idle
  end

  test "we can create a state with a specific floor" do
    state = %State{current_floor: 3}
    assert state.current_floor == 3
  end

  test "requesting a floor above the current floor sets heading and adds request" do
    state = %State{current_floor: 1, heading: :idle}

    new_state = State.request_floor(state, :car, 4)

    assert new_state.current_floor == 1
    assert new_state.heading == :up
    assert new_state.requests == [{:car, 4}]
  end

  test "Scenario 1.2: Arrival at floor triggers braking (stopping)" do
    # Arrange
    state = %State{current_floor: 3, heading: :up, requests: [{:car, 3}], motor_status: :running}

    # Act
    new_state = State.process_current_floor(state)

    # Assert
    assert new_state.motor_status == :stopping
    # Request should NOT be removed yet (until confirmed stopped)
    assert {:car, 3} in new_state.requests
  end

  test "Scenario 1.3: Completing braking and opening doors" do
    # Arrange
    state = %State{current_floor: 3, motor_status: :stopping, requests: [{:car, 3}]}

    # Act: Complete braking at T=0
    new_state = State.handle_event(state, :motor_stopped, 0)

    # Assert
    assert new_state.motor_status == :stopped
    assert new_state.door_status == :opening
    # Now it is safe to clear the request
    assert new_state.requests == []
  end

  test "Scenario 1.4: Door transition to open" do
    # Arrange
    state = %State{door_status: :opening}

    # Act: Doors open at T=100
    new_state = State.handle_event(state, :door_open_done, 100)

    # Assert
    assert new_state.door_status == :open
    assert new_state.last_activity_at == 100
  end

  test "Scenario 3.2: Reset Auto-Close Timer" do
    # Arrange: Doors are open, last activity was at T=100
    state = %State{door_status: :open, last_activity_at: 100}

    # Act: Press "Open" button at T=150
    new_state = State.handle_button_press(state, :door_open, 150)

    # Assert
    assert new_state.last_activity_at == 150
  end

  test "Scenario 2.2: Weight sensor triggers overload if weight > limit" do
    state = %State{door_status: :open, weight: 0, weight_limit: 1000}

    # Act
    new_state = State.update_weight(state, 1200)

    # Assert
    assert new_state.status == :overload
    assert new_state.weight == 1200
  end

  test "Scenario 2.3: Return to normal from overload when weight decreases" do
    state = %State{status: :overload, weight: 1200, weight_limit: 1000}

    # Act
    new_state = State.update_weight(state, 800)

    # Assert
    assert new_state.status == :normal
    assert new_state.weight == 800
  end

  test "Scenario 3.1: Door Open button reverses a closing door" do
    state = %State{door_status: :closing}

    # Act
    new_state = State.handle_button_press(state, :door_open, 0)

    # Assert
    assert new_state.door_status == :opening
  end
end
