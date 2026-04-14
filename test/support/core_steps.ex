defmodule Elevator.Gherkin.CoreSteps do
  @moduledoc """
  Shared step definitions for Elevator Core testing.
  Uses public API accessors solely.
  """
  use Cabbage.Feature

  alias Elevator.Core
  alias Elevator.Gherkin.Arguments, as: Args
  import ExUnit.Assertions

  # --- Given: Factory Initializers ---

  defgiven ~r/^the core is in phase idle at floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    {:ok, %{context | state: Core.idle_at(floor), actions: []}}
  end

  defgiven ~r/^the core is in phase docked at floor (?<floor>.+)$/,
           %{floor: floor_str},
           context do
    floor = Args.parse_floor(floor_str)
    {:ok, %{context | state: Core.docked_at(floor), actions: []}}
  end

  defgiven ~r/^the core is moving from floor (?<from>.+) to floor (?<to>.+)$/,
           %{from: f_str, to: t_str},
           context do
    from = Args.parse_floor(f_str)
    to = Args.parse_floor(t_str)
    {:ok, %{context | state: Core.moving_to(from, to), actions: []}}
  end

  defgiven ~r/^the elevator is booting$/, _vars, context do
    {:ok, %{context | state: Core.booting(), actions: []}}
  end

  defgiven ~r/^the elevator is rehoming$/, _vars, context do
    {:ok, %{context | state: Core.rehoming(), actions: []}}
  end

  # --- Given: State Modifiers (Pre-conditions) ---

  defgiven ~r/^the current position is (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    state = put_in(context.state.hardware.current_floor, floor)
    {:ok, %{context | state: state}}
  end

  defgiven ~r/^the last saved elevator position is (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    # We store the vault (saved position) in the context to use in startup-check
    {:ok, Map.put(context, :vault_floor, floor)}
  end

  defgiven ~r/^a car request for floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    {state, actions} = Core.request_floor(context.state, :car, floor)
    {:ok, %{context | state: state, actions: actions}}
  end

  # --- When: Events ---

  defwhen ~r/^the signal startup-check is received$/, _vars, context do
    vault = Map.get(context, :vault_floor, :unknown)
    sensor = Core.current_floor(context.state)

    {state, actions} =
      Core.handle_event(context.state, :startup_check, %{vault: vault, sensor: sensor})

    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^a car request for floor (?<floor>.+) is received$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    {state, actions} = Core.request_floor(context.state, :car, floor)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^a hall request for floor (?<floor>.+) is received$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    {state, actions} = Core.request_floor(context.state, :hall, floor)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the inactivity timeout expires$/, _vars, context do
    {state, actions} = Core.handle_event(context.state, :inactivity_timeout)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the arrival at floor (?<floor>.+) is received$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    {state, actions} = Core.process_arrival(context.state, floor)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the motor is stopped$/, _vars, context do
    {state, actions} = Core.handle_event(context.state, :motor_stopped)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the door is open$/, _vars, context do
    {state, actions} = Core.handle_event(context.state, :door_opened, 0)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the door timeout is received$/, _vars, context do
    {state, actions} = Core.handle_event(context.state, :door_timeout)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the button (?<button>.+) is pressed$/, %{button: btn_str}, context do
    button = Args.parse_button(btn_str)
    {state, actions} = Core.handle_button_press(context.state, button, 0)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the door is closed$/, _vars, context do
    {state, actions} = Core.handle_event(context.state, :door_closed)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the door is obstructed$/, _vars, context do
    {state, actions} = Core.handle_event(context.state, :door_obstructed, 0)
    {:ok, %{context | state: state, actions: actions}}
  end

  # --- Then: Assertions ---

  defthen ~r/^the phase is (?<phase>.+)$/, %{phase: phase_str}, context do
    expected = Args.parse_phase(phase_str)
    assert Core.phase(context.state) == expected
    {:ok, context}
  end

  # Special case for core.feature: "the motor phase is arriving"
  defthen ~r/^the motor phase is (?<phase>.+)$/, %{phase: phase_str}, context do
    expected = Args.parse_phase(phase_str)
    assert Core.phase(context.state) == expected
    {:ok, context}
  end

  defthen ~r/^the motor is (?<status>.+)$/, %{status: status_str}, context do
    status = Args.parse_motor_status(status_str)
    actions = context.actions

    case status do
      :running ->
        assert Core.motor_status(context.state) == :running or
                 Enum.any?(actions, fn a -> match?({:move, _}, a) end)

      :crawling ->
        assert Core.motor_status(context.state) == :crawling or
                 Enum.any?(actions, fn a -> match?({:crawl, _}, a) end)

      :stopping ->
        assert Core.motor_status(context.state) == :stopping or
                 {:stop_motor} in actions

      :stopped ->
        # If we just told it to stop, it's effectively "stopping" or "stopped"
        # but the state machine might still say :stopped if already there.
        assert Core.motor_status(context.state) == :stopped or
                 {:stop_motor} in actions
    end

    {:ok, context}
  end

  # Special case: "the motor stopped" (Then)
  defthen ~r/^the motor stopped$/, _vars, context do
    assert Core.motor_status(context.state) == :stopped or {:stop_motor} in context.actions
    {:ok, context}
  end

  defthen ~r/^the door is (?<status>.+)$/, %{status: status_str}, context do
    status = Args.parse_door_status(status_str)
    actions = context.actions

    case status do
      :open ->
        assert Core.door_status(context.state) == :open

      :closed ->
        assert Core.door_status(context.state) == :closed or
                 {:close_door} in actions

      :opening ->
        assert Core.door_status(context.state) == :opening or
                 {:open_door} in actions

      :closing ->
        assert Core.door_status(context.state) == :closing or
                 {:close_door} in actions
    end

    {:ok, context}
  end

  # Special case: "door is opening" (Then)
  defthen ~r/^door is opening$/, _vars, context do
    assert Core.door_status(context.state) == :opening or {:open_door} in context.actions
    {:ok, context}
  end

  defthen ~r/^the heading is (?<heading>.+)$/, %{heading: heading_str}, context do
    expected = Args.parse_heading(heading_str)
    assert Core.heading(context.state) == expected
    {:ok, context}
  end

  defthen ~r/^the queue is (?<val>.+)$/, %{val: val_str}, context do
    expected = Args.parse_list(val_str, &Args.parse_floor/1)
    actual = Core.queue(context.state)
    assert actual == expected, "Expected queue #{inspect(expected)}, got #{inspect(actual)}"
    {:ok, context}
  end

  defthen ~r/^the elevator is at floor (?<floor>.+)$/, %{floor: floor_str}, context do
    expected = Args.parse_floor(floor_str)
    assert Core.current_floor(context.state) == expected
    {:ok, context}
  end

  defthen ~r/^the door timeout timer is set$/, _vars, context do
    assert Enum.any?(context.actions, fn a -> match?({:set_timer, :door_timeout, _}, a) end)
    {:ok, context}
  end
end
