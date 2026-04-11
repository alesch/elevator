defmodule Elevator.AlgorithmTest do
  use ExUnit.Case
  alias Elevator.Core

  describe "LOOK Algorithm ([S-MOVE-SWEEP-CAR] & [S-MOVE-SWEEP-HALL])" do
    # REVISE: Align with [S-MOVE-SWEEP-CAR] (immediate stop) and [S-MOVE-SWEEP-HALL] (deferred sweep).
  end

  describe "[S-REQ-HONOR-ALL]: Honor All Requests" do
    test "Car request on the path — elevator stops" do
      # GIVEN: Moving :up, car request for F3 on the path
      state = Core.idle_at(1) |> Core.request_floor(:car, 3) |> elem(0)
      # Ingest reality: motor is now running
      {state, _} = Core.handle_event(state, :motor_running)

      # WHEN: Sensor confirms arrival at F3
      {new_state, actions} = Core.process_arrival(state, 3)

      # THEN: Elevator stops at F3
      assert Core.phase(new_state) == :arriving
      # Reality: still running until stop confirmed
      assert Core.motor_status(new_state) == :running 
      assert {:stop_motor} in actions
    end

    test "Hall request on the path — elevator stops" do
      # GIVEN: Moving :up, hall request for F4 on the path
      state = Core.idle_at(2) |> Core.request_floor(:hall, 4) |> elem(0)
      {state, _} = Core.handle_event(state, :motor_running)

      # WHEN: Sensor confirms arrival at F4
      {new_state, actions} = Core.process_arrival(state, 4)

      # THEN: Elevator stops at F4
      assert Core.phase(new_state) == :arriving
      assert Core.motor_status(new_state) == :running
      assert {:stop_motor} in actions
    end
  end

  describe "Wake Up Logic ([S-MOVE-WAKEUP])" do
    test "[S-MOVE-WAKEUP]: Context-Aware Wake Up (Idle at F5 heads DOWN for F1)" do
      # Arrange: Elevator is idle at Floor 5
      state = Core.idle_at(5)

      # Act: Request comes in for Floor 1
      {new_state, _} = Core.request_floor(state, :hall, 1)

      # Assert: Heading correctly switches to :down
      assert Core.heading(new_state) == :down
    end

    test "Idle elevator at F1 heads UP for F3" do
      # Arrange: Elevator is idle at Floor 1
      state = Core.idle_at(1)

      # Act: Request comes in for Floor 3
      {new_state, _} = Core.request_floor(state, :hall, 3)

      # Assert: Heading correctly switches to :up
      assert Core.heading(new_state) == :up
    end
  end

  describe "Multi-Stop Sweep Ordering ([S-MOVE-MULTI-CAR] & [S-MOVE-MULTI-HALL])" do
    # REVISE: Align with [S-MOVE-MULTI-CAR] (ascending: 2, 4, 5) and [S-MOVE-MULTI-HALL] (descending: 5, 4, 2).
    test "Elevator stops at each floor in ascending order when heading up" do
      # GIVEN: Idle at F0, three car requests
      state = Core.idle_at(0)
      {state, _} = Core.request_floor(state, :car, 2)
      {state, _} = Core.request_floor(state, :car, 4)
      {state, _} = Core.request_floor(state, :car, 6)

      # Ingest reality: motor started
      {state, _} = Core.handle_event(state, :motor_running)

      # Pulse settlement: the first request_floor starts the move
      assert Core.heading(state) == :up
      assert Core.phase(state) == :moving
      assert Core.motor_status(state) == :running

      # ARRIVE at F2 — must stop
      {state, actions} = Core.process_arrival(state, 2)
      assert Core.phase(state) == :arriving
      assert {:stop_motor} in actions

      # Settle to :docked to clear request
      {state, _} = Core.handle_event(state, :motor_stopped, 0)
      {state, _} = Core.handle_event(state, :door_opened, 0)
      refute {:car, 2} in Core.requests(state)
      assert Core.phase(state) == :docked

      # Depart from F2
      {state, _} = Core.handle_event(state, :door_timeout, 5000)
      {state, _} = Core.handle_event(state, :door_closed)
      assert Core.phase(state) == :moving
      {state, _} = Core.handle_event(state, :motor_running)
      assert Core.motor_status(state) == :running

      # ARRIVE at F4 — must stop
      {state, actions} = Core.process_arrival(state, 4)
      assert Core.phase(state) == :arriving
      assert {:stop_motor} in actions

      # Settle to :docked to clear request
      {state, _} = Core.handle_event(state, :motor_stopped, 0)
      {state, _} = Core.handle_event(state, :door_opened, 0)
      refute {:car, 4} in Core.requests(state)

      # Depart from F4
      {state, _} = Core.handle_event(state, :door_timeout, 5000)
      {state, _} = Core.handle_event(state, :door_closed)
      assert Core.phase(state) == :moving
      {state, _} = Core.handle_event(state, :motor_running)
      assert Core.motor_status(state) == :running

      # ARRIVE at F6 — must stop
      {state, actions} = Core.process_arrival(state, 6)
      assert Core.phase(state) == :arriving
      assert {:stop_motor} in actions

      # All requests fulfilled after docking
      {state, _} = Core.handle_event(state, :motor_stopped, 0)
      {final_state, _} = Core.handle_event(state, :door_opened, 0)
      assert Core.requests(final_state) == []
    end
  end

  describe "[S-REQ-SYNC]: Request Fulfillment (Internal State Sync)" do
    test "clears requests during arrival to ensure correct heading choice" do
      # GIVEN: Arriving at F3 (from a move up), two requests in queue
      state = Core.moving_to(0, 3) 
      # Now it's moving. Arrive it.
      {state, _} = Core.process_arrival(state, 3)
      # Now it's arriving at 3. Add a request for 0.
      {state, _} = Core.request_floor(state, :car, 0)

      # WHEN: Move to :docked (fulfills F3 request)
      {state, _} = Core.handle_event(state, :motor_stopped, 0)
      {state, _} = Core.handle_event(state, :door_opened, 0)

      # THEN: F3 cleared, F0 remains
      refute {:car, 3} in Core.requests(state)
      assert {:car, 0} in Core.requests(state)

      # WHEN: Request for F0 triggers heading update
      {state, _} = Core.request_floor(state, :car, 0)

      # THEN: Heading is :down (only remaining work is below)
      assert Core.heading(state) == :down
    end
  end
end
