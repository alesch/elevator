defmodule Elevator.CoreTest do
  use ExUnit.Case
  alias Elevator.Core

  test "initial state has floor 0 and is idle" do
    state = %Core{}
    assert state.current_floor == 0
    assert state.heading == :idle
  end

  test "we can create a state with a specific floor" do
    state = %Core{current_floor: 3}
    assert state.current_floor == 3
  end

  describe "Scenario 1.1: Context-Aware Wake Up (Request from IDLE)" do
    test "Scenario 1.1a: Request above — heading becomes :up and phase becomes :moving" do
      # GIVEN: Idle at F1, doors closed
      state = %Core{current_floor: 1, heading: :idle, phase: :idle, door_status: :closed}

      # WHEN: Request for F4
      {new_state, actions} = Core.request_floor(state, :car, 4)

      assert new_state.heading == :up
      assert new_state.phase == :moving
      assert new_state.requests == [{:car, 4}]
      assert {:move_motor, :up, :normal} in actions
    end

    test "Scenario 1.1b: Request below — heading becomes :down and phase becomes :moving" do
      # GIVEN: Idle at F5, doors closed
      state = %Core{current_floor: 5, heading: :idle, phase: :idle, door_status: :closed}

      # WHEN: Request for F1
      {new_state, actions} = Core.request_floor(state, :car, 1)

      assert new_state.heading == :down
      assert new_state.phase == :moving
      assert new_state.requests == [{:car, 1}]
      assert {:move_motor, :down, :normal} in actions
    end
  end

  test "Scenario 1.2: Arrival at floor triggers braking (stopping)" do
    # Arrange
    state = %Core{current_floor: 3, heading: :up, requests: [{:car, 3}], motor_status: :running}

    # Act
    {new_state, actions} = Core.process_current_floor(state)

    # Assert
    assert new_state.motor_status == :stopping
    assert {:stop_motor} in actions
    # Request should NOT be removed yet (until confirmed stopped)
    assert {:car, 3} in new_state.requests
  end

  test "Scenario 1.3: Completing braking and opening doors" do
    # Arrange
    state = %Core{
      current_floor: 3,
      motor_status: :stopping,
      requests: [{:car, 3}],
      door_status: :closed
    }

    # Act: Complete braking at T=0
    {new_state, actions} = Core.handle_event(state, :motor_stopped, 0)

    # Assert
    assert new_state.motor_status == :stopped
    assert new_state.door_status == :opening
    assert {:open_door} in actions
    # Now it is safe to clear the request
    assert new_state.requests == []
  end

  test "Scenario 1.4: Door transition to open" do
    # Arrange
    state = %Core{door_status: :opening}

    # Act: Doors open at T=100
    {new_state, actions} = Core.handle_event(state, :door_opened, 100)

    # Assert
    assert new_state.door_status == :open
    assert new_state.last_activity_at == 100
    assert {:set_timer, :door_timeout, 5000} in actions
  end

  test "Scenario 3.2: Reset Auto-Close Timer" do
    # Arrange: Doors are open, last activity was at T=100
    state = %Core{door_status: :open, last_activity_at: 100}

    # Act: Press "Open" button at T=150
    {new_state, actions} = Core.handle_button_press(state, :door_open, 150)

    # Assert
    assert new_state.last_activity_at == 150
    # Timer should be reset (cancelled and set again)
    assert {:set_timer, :door_timeout, 5000} in actions
  end

  test "Scenario 3.1: Door Open button reverses a closing door" do
    state = %Core{door_status: :closing}

    # Act
    {new_state, actions} = Core.handle_button_press(state, :door_open, 0)

    # Assert
    assert new_state.door_status == :opening
    assert {:open_door} in actions
  end

  describe "Scenario 2.1 & 2.5: Door Safety Sensors" do
    test "Scenario 2.1: door_obstructed reverses a closing door and marks sensor blocked" do
      state = %Core{door_status: :closing, door_sensor: :clear}

      # Act
      {new_state, actions} = Core.handle_event(state, :door_obstructed, 0)

      # Assert
      assert new_state.door_status == :opening
      assert new_state.door_sensor == :blocked
      assert {:open_door} in actions
    end

    test "Scenario 2.5: door_cleared marks sensor as clear" do
      state = %Core{door_sensor: :blocked}

      # Act
      {new_state, _actions} = Core.handle_event(state, :door_cleared, 0)

      # Assert
      assert new_state.door_sensor == :clear
    end
  end

  describe "Manual Door Overrides" do
    test "Scenario 3.0: Manual door open from closed+idle" do
      # GIVEN: Idle elevator stopped at a floor, doors closed
      state = %Core{door_status: :closed, heading: :idle, motor_status: :stopped}

      # ACT: Passenger presses door open button
      {new_state, actions} = Core.handle_button_press(state, :door_open, 0)

      # ASSERT: Door begins opening
      assert new_state.door_status == :opening
      assert {:open_door} in actions
    end
  end

  describe "Autonomous Core: Intent & Safety Interlocks" do
    test "The Golden Rule: Motor MUST be stopped if doors are NOT closed" do
      # Case: Heading is :up (intent to move), but doors are :opening
      state = %Core{heading: :up, door_status: :opening, motor_status: :running}

      # Act: Applying constraints (this is now internal to handle_event)
      {new_state, actions} = Core.handle_event(state, :door_opened, 100)

      # Assert: Motor MUST be stopped because doors were NOT closed.
      assert new_state.motor_status == :stopped
      # Since it's only T=100 and it just opened, it stays open for 5s.
      assert new_state.door_status == :open
      assert {:set_timer, :door_timeout, 5000} in actions
    end

    test "Start of Service: Heading :up and doors :open triggers wait, then closing" do
      # GIVEN: At F1, doors open, but we just got a request for F5 at T=100
      state = %Core{current_floor: 1, door_status: :open, heading: :idle, last_activity_at: 100}

      # ACT: Request floor 5 at T=101
      {new_state, _actions} = Core.request_floor(state, :car, 5)

      # ASSERT: Heading is UP, but door stays open until timeout
      assert new_state.heading == :up
      assert new_state.door_status == :open

      # ACT: Tick at F=5101 (timeout)
      {final_state, actions} = Core.handle_event(new_state, :tick, 5101)

      # ASSERT: Now it's closing
      assert final_state.door_status == :closing
      assert {:close_door} in actions
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
      {new_state, actions} = Core.handle_event(state, :motor_stopped, 100)

      # ASSERT: Core immediately decides to OPEN doors
      assert new_state.motor_status == :stopped
      assert new_state.door_status == :opening
      assert {:open_door} in actions
    end

    test "Scenario 7.1b: Door does NOT close on timeout when sensor is blocked" do
      # GIVEN: Door open, but sensor is blocked
      state = %Core{
        current_floor: 1,
        door_status: :open,
        heading: :up,
        door_sensor: :blocked,
        last_activity_at: 0
      }

      # ACT: 5s timeout fires
      {new_state, actions} = Core.handle_event(state, :door_timeout, 5000)

      # ASSERT: Door must NOT close — obstruction overrides timeout
      refute new_state.door_status == :closing
      refute {:close_door} in actions
    end

    test "Scenario 7.1a: Door closes on timeout even when heading is :idle" do
      # GIVEN: Idle elevator at F0, door open (e.g., post-rehoming), no pending requests
      state = %Core{
        current_floor: 0,
        door_status: :open,
        heading: :idle,
        last_activity_at: 0
      }

      # ACT: 5s timeout fires
      {new_state, actions} = Core.handle_event(state, :door_timeout, 5000)

      # ASSERT: Door closes regardless of idle heading
      assert new_state.door_status == :closing
      assert {:close_door} in actions
    end

    test "Scenario 7.2: Manual Close Button Override" do
      # GIVEN: Doors open at F1, heading :up
      state = %Core{current_floor: 1, door_status: :open, heading: :up, last_activity_at: 100}

      # ACT: Press "Close" button
      {new_state, actions} = Core.handle_button_press(state, :door_close, 150)

      # ASSERT: Doors start closing immediately
      assert new_state.door_status == :closing
      assert {:close_door} in actions
      # Note: timer cancellation is tested in the action set
      assert {:cancel_timer, :door_timeout} in actions
    end
  end
end
