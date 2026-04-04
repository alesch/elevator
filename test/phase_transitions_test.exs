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

  # Scenario 8.3
  test "Scenario 8.3: :arriving → :docked when doors confirm open" do
    state = %Core{phase: :arriving, motor_status: :stopped, door_status: :opening}

    {new_state, actions} = Core.handle_event(state, :door_opened, 100)

    assert new_state.phase == :docked
    assert new_state.door_status == :open
    assert {:set_timer, :door_timeout, 5000} in actions
  end

  # Scenario 8.4
  test "Scenario 8.4: :docked → :leaving when door timeout fires" do
    state = %Core{phase: :docked, door_status: :open, door_sensor: :clear}

    {new_state, actions} = Core.handle_event(state, :door_timeout, 5000)

    assert new_state.phase == :leaving
    assert new_state.door_status == :closing
    assert {:close_door} in actions
  end

  # Scenario 8.5
  test "Scenario 8.5: :leaving → :moving when door closes and requests remain" do
    state = %Core{
      phase: :leaving,
      door_status: :closing,
      heading: :up,
      requests: [{:car, 5}],
      current_floor: 3
    }

    {new_state, actions} = Core.handle_event(state, :door_closed, nil)

    assert new_state.phase == :moving
    assert new_state.motor_status == :running
    assert {:move_motor, :up, :normal} in actions
  end

  # Scenario 8.6
  test "Scenario 8.6: :leaving → :idle when door closes and no requests remain" do
    state = %Core{
      phase: :leaving,
      door_status: :closing,
      heading: :idle,
      requests: [],
      motor_status: :stopped
    }

    {new_state, _actions} = Core.handle_event(state, :door_closed, nil)

    assert new_state.phase == :idle
    assert new_state.motor_status == :stopped
  end
end
