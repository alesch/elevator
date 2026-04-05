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

  describe "[S-MOVE-WAKEUP]: Context-Aware Wake Up (Request from IDLE)" do
    test "Sub-case A: Request above — heading becomes :up and phase becomes :moving" do
      # GIVEN: Idle at F1, doors closed
      state = %Core{current_floor: 1, heading: :idle, phase: :idle, door_status: :closed}

      # WHEN: Request for F4
      {new_state, actions} = Core.request_floor(state, :car, 4)

      assert new_state.heading == :up
      assert new_state.phase == :moving
      assert new_state.requests == [{:car, 4}]
      assert {:move, :up} in actions
    end

    test "Sub-case B: Request below — heading becomes :down and phase becomes :moving" do
      # GIVEN: Idle at F5, doors closed
      state = %Core{current_floor: 5, heading: :idle, phase: :idle, door_status: :closed}

      # WHEN: Request for F1
      {new_state, actions} = Core.request_floor(state, :car, 1)

      assert new_state.heading == :down
      assert new_state.phase == :moving
      assert new_state.requests == [{:car, 1}]
      assert {:move, :down} in actions
    end
  end

  test "[S-MOVE-BRAKING]: Arrival at target floor triggers braking" do
    # GIVEN: Moving up, request for F3
    state = %Core{
      phase: :moving,
      current_floor: 2,
      heading: :up,
      requests: [{:car, 3}],
      motor_status: :running
    }

    # WHEN: Sensor confirms arrival at F3
    {new_state, actions} = Core.process_arrival(state, 3)

    # THEN: Motor begins braking; phase transitions to :arriving
    assert new_state.phase == :arriving
    assert new_state.motor_status == :stopping
    assert new_state.current_floor == 3
    assert {:stop_motor} in actions
    # Request stays in queue until motor actually stops
    assert {:car, 3} in new_state.requests
  end

  test "[S-MOVE-OPENING]: Braking complete — motor stops and doors begin opening" do
    # GIVEN: Arriving at F3 (braking in progress)
    state = %Core{
      phase: :arriving,
      current_floor: 3,
      motor_status: :stopping,
      requests: [{:car, 3}],
      door_status: :closed
    }

    # WHEN: Motor confirms stopped
    {new_state, actions} = Core.handle_event(state, :motor_stopped, 0)

    # THEN: Motor stopped, doors begin opening, request fulfilled
    assert new_state.phase == :arriving
    assert new_state.motor_status == :stopped
    assert new_state.door_status == :opening
    assert {:open_door} in actions
    assert new_state.requests == []
  end

  test "[S-MOVE-DOCKED]: Door open confirmation — phase becomes :docked, timer set" do
    # GIVEN: Arriving at floor, doors opening
    state = %Core{phase: :arriving, door_status: :opening, motor_status: :stopped}

    # WHEN: Doors confirm open at T=100
    {new_state, actions} = Core.handle_event(state, :door_opened, 100)

    # THEN: Docked, timer armed for auto-close
    assert new_state.phase == :docked
    assert new_state.door_status == :open
    assert new_state.last_activity_at == 100
    assert {:set_timer, :door_timeout, 5000} in actions
  end

  test "[S-MOVE-CLOSING]: Door closing is a two-step sequence — intent then confirmation" do
    # GIVEN: Docked, doors open, sensor clear — timeout fires
    state = %Core{phase: :docked, door_status: :open, door_sensor: :clear}

    # STEP 1 — WHEN: Timeout fires
    {closing_state, actions} = Core.handle_event(state, :door_timeout, 5000)

    # THEN: Intent set to :closing, close command dispatched
    assert closing_state.door_status == :closing
    assert closing_state.phase == :leaving
    assert {:close_door} in actions

    # STEP 2 — WHEN: Hardware confirms door is physically closed
    {closed_state, _actions} = Core.handle_event(closing_state, :door_closed, 6000)

    # THEN: Confirmed :closed
    assert closed_state.door_status == :closed
  end

  test "[S-MANUAL-RESET-TIMER]: Reset Auto-Close Timer" do
    # GIVEN: Docked — doors open, last activity at T=100
    state = %Core{phase: :docked, door_status: :open, last_activity_at: 100}

    # WHEN: Passenger presses door open button at T=150
    {new_state, actions} = Core.handle_button_press(state, :door_open, 150)

    # THEN: Activity timestamp updated, auto-close timer restarted
    assert new_state.last_activity_at == 150
    assert {:set_timer, :door_timeout, 5000} in actions
  end

  test "[S-MANUAL-OPEN-WIN]: Door Open button reverses a closing door" do
    # GIVEN: Leaving — door in the process of closing
    state = %Core{phase: :leaving, door_status: :closing}

    # WHEN: Passenger presses door open button
    {new_state, actions} = Core.handle_button_press(state, :door_open, 0)

    # THEN: Closing discarded, door reverses to opening
    assert new_state.door_status == :opening
    assert {:open_door} in actions
  end

  describe "Door Safety Sensors" do
    test "[S-SAFE-OBSTRUCT]: door_obstructed while leaving — door reverses, sensor blocked, phase reverts to :docked" do
      # GIVEN: Leaving — door in the process of closing
      state = %Core{phase: :leaving, door_status: :closing, door_sensor: :clear}

      # WHEN: Obstruction detected
      {new_state, actions} = Core.handle_event(state, :door_obstructed, 0)

      # THEN: Door reverses, sensor flagged, phase reverts to :docked
      assert new_state.door_status == :opening
      assert new_state.door_sensor == :blocked
      assert new_state.phase == :docked
      assert {:open_door} in actions
    end

    test "[S-SAFE-CLEARED]: door_cleared marks sensor as clear" do
      # GIVEN: Sensor is blocked
      state = %Core{door_sensor: :blocked}

      # WHEN: Obstruction clears
      {new_state, _actions} = Core.handle_event(state, :door_cleared, 0)

      # THEN: Sensor is clear
      assert new_state.door_sensor == :clear
    end
  end

  describe "Manual Door Overrides" do
    test "[S-MANUAL-OPEN-IDLE]: Manual door open from closed+idle" do
      # GIVEN: Idle at a floor, doors closed
      state = %Core{phase: :idle, door_status: :closed, heading: :idle, motor_status: :stopped}

      # WHEN: Passenger presses door open button
      {new_state, actions} = Core.handle_button_press(state, :door_open, 0)

      # THEN: Door begins opening
      assert new_state.door_status == :opening
      assert {:open_door} in actions
    end
  end

  describe "Autonomous Core: Intent & Safety Interlocks" do
    @tag :capture_log
    test "[S-SAFE-GOLDEN]: Motor MUST be stopped if doors are NOT closed" do
      # Case: Deliberately invalid state — golden rule must correct it
      state = %Core{heading: :up, door_status: :opening, motor_status: :running}

      # Act: Applying constraints (this is now internal to handle_event)
      {new_state, actions} = Core.handle_event(state, :door_opened, 100)

      # Assert: Motor MUST be stopped because doors were NOT closed.
      assert new_state.motor_status == :stopped
      # Since it's only T=100 and it just opened, it stays open for 5s.
      assert new_state.door_status == :open
      assert {:set_timer, :door_timeout, 5000} in actions
    end

    test "[S-SAFE-SERVICE-DELAY]: Service delay — door stays open 5s before movement begins" do
      # GIVEN: Docked at F1, doors open, request for F5 arrives
      state = %Core{
        phase: :docked,
        current_floor: 1,
        door_status: :open,
        heading: :idle,
        last_activity_at: 100
      }

      # WHEN: Request for F5 is added
      {new_state, _actions} = Core.request_floor(state, :car, 5)

      # THEN: Heading is :up, but door stays open — 5s timer governs the close
      assert new_state.heading == :up
      assert new_state.door_status == :open

      # WHEN: Door timeout fires (the controller sends this after 5s)
      {final_state, actions} = Core.handle_event(new_state, :door_timeout, 5101)

      # THEN: Door begins closing, phase transitions to :leaving
      assert final_state.door_status == :closing
      assert final_state.phase == :leaving
      assert {:close_door} in actions
    end

    test "[S-MOVE-OPENING]: Arrival at floor triggers :opening when stopped" do
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

    test "[S-SAFE-TIMEOUT] Sub-case B: Door does NOT close on timeout when sensor is blocked" do
      # GIVEN: Docked, door open, but sensor is blocked
      state = %Core{
        phase: :docked,
        current_floor: 1,
        door_status: :open,
        heading: :up,
        door_sensor: :blocked,
        last_activity_at: 0
      }

      # WHEN: 5s timeout fires
      {new_state, actions} = Core.handle_event(state, :door_timeout, 5000)

      # THEN: Door must NOT close — obstruction overrides timeout
      refute new_state.door_status == :closing
      refute {:close_door} in actions
    end

    test "[S-SAFE-TIMEOUT] Sub-case A: Door closes on timeout even when heading is :idle" do
      # GIVEN: Docked at F0, door open, no pending requests, sensor clear
      state = %Core{
        phase: :docked,
        current_floor: 0,
        door_status: :open,
        heading: :idle,
        door_sensor: :clear,
        last_activity_at: 0
      }

      # WHEN: 5s timeout fires
      {new_state, actions} = Core.handle_event(state, :door_timeout, 5000)

      # THEN: Door closes regardless of idle heading; phase transitions to :leaving
      assert new_state.door_status == :closing
      assert new_state.phase == :leaving
      assert {:close_door} in actions
    end

    test "[S-MANUAL-CLOSE]: Manual Close Button Override" do
      # GIVEN: Docked, doors open, heading :up (pending work)
      state = %Core{
        phase: :docked,
        current_floor: 1,
        door_status: :open,
        heading: :up,
        last_activity_at: 100
      }

      # WHEN: Passenger presses close button
      {new_state, actions} = Core.handle_button_press(state, :door_close, 150)

      # THEN: Doors start closing immediately, timer cancelled
      assert new_state.door_status == :closing
      assert {:close_door} in actions
      assert {:cancel_timer, :door_timeout} in actions
    end

    test "[S-REHOME-STATUS]: Rehoming uses :crawling status" do
      # GIVEN: Idle
      state = %Core{phase: :idle, current_floor: 1}

      # WHEN: Rehoming starts
      {new_state, actions} = Core.handle_event(state, :rehoming_started, 0)

      # THEN: Phase is :rehoming, motor is :crawling down
      assert new_state.phase == :rehoming
      assert new_state.motor_status == :crawling
      assert new_state.heading == :down
      assert {:crawl, :down} in actions
    end
  end
end
