defmodule Elevator.PhaseTransitionsTest do
  use ExUnit.Case
  alias Elevator.Core

  # [S-PHASE-IDLE-MOVE]
  test "[S-PHASE-IDLE-MOVE]: :idle → :moving on request for a different floor" do
    state = Core.idle_at(0)

    {new_state, actions} = Core.request_floor(state, :car, 3)

    assert Core.phase(new_state) == :moving
    # Reality: Motor status remains :stopped until :motor_running confirmation
    assert Core.motor_status(new_state) == :stopped 
    assert Core.heading(new_state) == :up
    assert {:move, :up} in actions
  end

  # [S-PHASE-MOVE-ARRIVE]
  test "[S-PHASE-MOVE-ARRIVE]: :moving → :arriving when target floor reached" do
    state = Core.moving_to(2, 3)

    {new_state, actions} = Core.process_arrival(state, 3)

    assert Core.phase(new_state) == :arriving
    # Reality: Motor status remains :running until :motor_stopped confirmation
    assert Core.motor_status(new_state) == :running
    assert {:stop_motor} in actions
  end

  # [S-PHASE-ARRIVE-DOCK]
  test "[S-PHASE-ARRIVE-DOCK]: :arriving → :docked when doors confirm open" do
    # Reach :arriving state naturally
    state = 
      Core.moving_to(0, 3)
      |> Core.handle_event(:arrival, 3)
      |> elem(0)
      |> Core.handle_event(:motor_stopped)
      |> elem(0)
      |> Core.handle_event(:door_opening)
      |> elem(0)

    assert Core.motor_status(state) == :stopped
    assert Core.door_status(state) == :opening

    {new_state, actions} = Core.handle_event(state, :door_opened, 100)

    assert Core.phase(new_state) == :docked
    assert Core.door_status(new_state) == :open
    assert {:set_timer, :door_timeout, 5000} in actions
  end

  # [S-SAFE-TIMEOUT]
  test "[S-SAFE-TIMEOUT]: :docked → :leaving when door timeout fires" do
    state = Core.docked_at(3)
    # The factory calls request_floor which opens doors, but we need to confirm they are open to reach :docked
    {state, _} = Core.handle_event(state, :door_opened, 0)

    {new_state, actions} = Core.handle_event(state, :door_timeout, 5000)

    assert Core.phase(new_state) == :leaving
    # Reality: Door remains :open until :door_closing confirmation
    assert Core.door_status(new_state) == :open
    assert {:close_door} in actions
  end

  # [S-PHASE-LEAVE-MOVE]
  test "[S-PHASE-LEAVE-MOVE]: :leaving → :moving when door closes and requests remain" do
    # Start at 3, docking. Request 5.
    state = 
      Core.idle_at(3)
      |> Core.request_floor(:car, 5)
      |> elem(0)
      |> Core.request_floor(:car, 3) # arrive at 3
      |> elem(0)
      |> Core.handle_event(:motor_stopped, nil)
      |> elem(0)
      |> Core.handle_event(:door_opened, 0)
      |> elem(0)
      |> Core.handle_event(:door_timeout, 5000)
      |> elem(0)
      |> Core.handle_event(:door_closing)
      |> elem(0)

    assert Core.phase(state) == :leaving
    assert Core.door_status(state) == :closing

    {new_state, actions} = Core.handle_event(state, :door_closed, nil)

    assert Core.phase(new_state) == :moving
    # Reality: Door remains :closed, Motor remains :stopped until :motor_running confirmation
    assert Core.motor_status(new_state) == :stopped
    assert {:move, :up} in actions
  end

  # [S-PHASE-LEAVE-IDLE]
  test "[S-PHASE-LEAVE-IDLE]: :leaving → :idle when door closes and no requests remain" do
    state = 
      Core.idle_at(3)
      |> Core.request_floor(:car, 3)
      |> elem(0)
      |> Core.handle_event(:motor_stopped, nil)
      |> elem(0)
      |> Core.handle_event(:door_opened, 0)
      |> elem(0)
      |> Core.handle_event(:door_timeout, 5000)
      |> elem(0)
      |> Core.handle_event(:door_closing)
      |> elem(0)

    assert Core.phase(state) == :leaving
    assert Core.door_status(state) == :closing

    {new_state, _actions} = Core.handle_event(state, :door_closed, nil)

    assert Core.phase(new_state) == :idle
    assert Core.motor_status(new_state) == :stopped
  end

  test "[S-PHASE-LEAVE-DOCK]: :leaving → :arriving on obstruction during close" do
    state = 
      Core.idle_at(3)
      |> Core.request_floor(:car, 3)
      |> elem(0)
      |> Core.handle_event(:motor_stopped, nil)
      |> elem(0)
      |> Core.handle_event(:door_opened, 0)
      |> elem(0)
      |> Core.handle_event(:door_timeout, 5000)
      |> elem(0)
      |> Core.handle_event(:door_closing)
      |> elem(0)

    {new_state, actions} = Core.handle_event(state, :door_obstructed, nil)

    assert Core.phase(new_state) == :arriving
    # Reality: Door has been obstructed physically
    assert Core.door_status(new_state) == :obstructed
    assert {:open_door} in actions
  end
end
