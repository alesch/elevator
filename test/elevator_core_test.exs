defmodule Elevator.CoreTest do
  use ExUnit.Case
  alias Elevator.Core

  test "initial state has floor 1 and is idle" do
    state = %Core{}
    assert state.current_floor == 1
    assert state.heading == :idle
  end

  test "we can create a state with a specific floor" do
    state = %Core{current_floor: 3}
    assert state.current_floor == 3
  end

  test "requesting a floor above the current floor sets heading and adds request" do
    state = %Core{current_floor: 1, heading: :idle}

    new_state = Core.request_floor(state, :car, 4)

    assert new_state.current_floor == 1
    assert new_state.heading == :up
    assert new_state.requests == [{:car, 4}]
  end

  test "Scenario 1.2: Arrival at floor triggers braking (stopping)" do
    # Arrange
    state = %Core{current_floor: 3, heading: :up, requests: [{:car, 3}], motor_status: :running}

    # Act
    new_state = Core.process_current_floor(state)

    # Assert
    assert new_state.motor_status == :stopping
    # Request should NOT be removed yet (until confirmed stopped)
    assert {:car, 3} in new_state.requests
  end

  test "Scenario 1.3: Completing braking and opening doors" do
    # Arrange
    state = %Core{current_floor: 3, motor_status: :stopping, requests: [{:car, 3}]}

    # Act: Complete braking at T=0
    new_state = Core.handle_event(state, :motor_stopped, 0)

    # Assert
    assert new_state.motor_status == :stopped
    assert new_state.door_status == :opening
    # Now it is safe to clear the request
    assert new_state.requests == []
  end

  test "Scenario 1.4: Door transition to open" do
    # Arrange
    state = %Core{door_status: :opening}

    # Act: Doors open at T=100
    new_state = Core.handle_event(state, :door_opened, 100)

    # Assert
    assert new_state.door_status == :open
    assert new_state.last_activity_at == 100
  end

  test "Scenario 3.2: Reset Auto-Close Timer" do
    # Arrange: Doors are open, last activity was at T=100
    state = %Core{door_status: :open, last_activity_at: 100}

    # Act: Press "Open" button at T=150
    new_state = Core.handle_button_press(state, :door_open, 150)

    # Assert
    assert new_state.last_activity_at == 150
  end

  test "Scenario 2.2: Weight sensor triggers overload if weight > limit" do
    state = %Core{door_status: :open, weight: 0, weight_limit: 1000}

    # Act
    new_state = Core.update_weight(state, 1200)

    # Assert
    assert new_state.status == :overload
    assert new_state.weight == 1200
  end

  test "Scenario 2.3: Return to normal from overload when weight decreases" do
    state = %Core{status: :overload, weight: 1200, weight_limit: 1000}

    # Act
    new_state = Core.update_weight(state, 800)

    # Assert
    assert new_state.status == :normal
    assert new_state.weight == 800
  end

  test "Scenario 3.1: Door Open button reverses a closing door" do
    state = %Core{door_status: :closing}

    # Act
    new_state = Core.handle_button_press(state, :door_open, 0)

    # Assert
    assert new_state.door_status == :opening
  end

  describe "Scenario 2.1 & 2.5: Door Safety Sensors" do
    test "Scenario 2.1: door_obstructed reverses a closing door and marks sensor blocked" do
      state = %Core{door_status: :closing, door_sensor: :clear}

      # Act
      new_state = Core.handle_event(state, :door_obstructed, 0)

      # Assert
      assert new_state.door_status == :opening
      assert new_state.door_sensor == :blocked
    end

    test "Scenario 2.5: door_cleared marks sensor as clear" do
      state = %Core{door_sensor: :blocked}

      # Act
      new_state = Core.handle_event(state, :door_cleared, 0)

      # Assert
      assert new_state.door_sensor == :clear
    end
  end

  describe "Autonomous Core: Intent & Safety Interlocks" do
    test "The Golden Rule: Motor MUST be stopped if doors are NOT closed" do
      # Case: Heading is :up (intent to move), but doors are :opening
      state = %Core{heading: :up, door_status: :opening, motor_status: :running}

      # Act: Applying constraints (this is now internal to handle_event)
      new_state = Core.handle_event(state, :door_opened, 100)

      # Assert: Motor MUST be stopped because doors were NOT closed.
      # And since heading is :up, the core immediately Decides to start closing (Start of Service).
      assert new_state.motor_status == :stopped
      assert new_state.door_status == :closing
    end

    test "Start of Service: Heading :up and doors :open triggers :closing" do
      # GIVEN: At F1, doors open, but we just got a request for F5
      state = %Core{current_floor: 1, door_status: :open, heading: :idle}

      # ACT: Request floor 5
      new_state = Core.request_floor(state, :car, 5)

      # ASSERT: Core immediately decides we need to CLOSE doors to start service
      assert new_state.heading == :up
      assert new_state.door_status == :closing
      assert new_state.motor_status == :stopped
    end

    test "End of Service: Arrival at floor triggers :opening when stopped" do
      # GIVEN: Arrived at F3, motor stopped, doors were closed
      state = %Core{
        current_floor: 3,
        motor_status: :stopping,
        door_status: :closed,
        requests: [{:car, 3}]
      }

      # ACT: Motor confirms stop
      new_state = Core.handle_event(state, :motor_stopped, 100)

      # ASSERT: Core immediately decides to OPEN doors
      assert new_state.motor_status == :stopped
      assert new_state.door_status == :opening
    end

    test "Safety Overload: Prevents door from closing" do
      # GIVEN: Overloaded at F1, doors open, heading :up
      state = %Core{current_floor: 1, door_status: :open, heading: :up, status: :overload}

      # ACT: Any update that would normally trigger closure
      # Still overloaded
      new_state = Core.update_weight(state, 1200)

      # ASSERT: Door MUST stay open (or transition to :opening if it was :closing)
      assert new_state.door_status == :open
    end
  end
end
