defmodule Elevator.Gherkin.CoreSteps do
  @moduledoc """
  Shared step definitions for Elevator Core testing.
  Uses public API accessors solely.
  """
  use Cabbage.Feature

  alias __MODULE__, as: CoreSteps
  alias Elevator.Core
  alias Elevator.Gherkin.Arguments, as: Args

  # --- Given: Factory Initializers ---

  defgiven ~r/^the core is in phase idle at floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    {:ok, Map.merge(context, %{state: Core.idle_at(floor), actions: []})}
  end

  defgiven ~r/^the core is in phase docked at floor (?<floor>.+)$/,
           %{floor: floor_str},
           context do
    floor = Args.parse_floor(floor_str)
    {:ok, Map.merge(context, %{state: Core.docked_at(floor), actions: []})}
  end

  defgiven ~r/^the core is moving from floor (?<from>.+) to floor (?<to>.+)$/,
           %{from: f_str, to: t_str},
           context do
    from = Args.parse_floor(f_str)
    to = Args.parse_floor(t_str)
    {:ok, Map.merge(context, %{state: Core.moving_to(from, to), actions: []})}
  end

  defgiven ~r/^the elevator is booting$/, _vars, context do
    {:ok, Map.merge(context, %{state: Core.booting(), actions: []})}
  end

  defgiven ~r/^the elevator is rehoming$/, _vars, context do
    {:ok, Map.merge(context, %{state: Core.rehoming(), actions: []})}
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

  defgiven ~r/^the last activity was (?<val>.+) minutes ago$/, _vars, context do
    # Pure state doesn't track relative time internally, we just simulate the timeout signal
    {:ok, context}
  end

  defgiven ~r/^a car request for floor (?<floor>.+)$/, %{floor: floor_str}, context do
    CoreSteps.receive_request(context, :car, floor_str)
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
    CoreSteps.receive_request(context, :car, floor_str)
  end

  defwhen ~r/^a hall request for floor (?<floor>.+) is received$/, %{floor: floor_str}, context do
    CoreSteps.receive_request(context, :hall, floor_str)
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
        assert Enum.any?(actions, fn a -> match?({:move, _}, a) or match?({:crawl, _}, a) end),
               "Expected motor to start running, but no :move/:crawl action in #{inspect(actions)}"

      :crawling ->
        assert Enum.any?(actions, fn a -> match?({:crawl, _}, a) end),
               "Expected motor to crawl, but no :crawl action in #{inspect(actions)}"

      :stopping ->
        assert {:stop_motor} in actions,
               "Expected motor to stop, but :stop_motor not in #{inspect(actions)}"

      :stopped ->
        assert {:stop_motor} in actions or Core.motor_status(context.state) == :stopped
    end

    {:ok, context}
  end

  defthen ~r/^the motor stopped$/, _vars, context do
    assert {:stop_motor} in context.actions or Core.motor_status(context.state) == :stopped
    {:ok, context}
  end

  defthen ~r/^the door is (?<status>.+)$/, %{status: status_str}, context do
    status = Args.parse_door_status(status_str)
    actions = context.actions

    case status do
      :open ->
        assert Core.door_status(context.state) == :open

      :closed ->
        assert Core.door_status(context.state) == :closed or {:close_door} in actions

      :opening ->
        assert {:open_door} in actions

      :closing ->
        assert {:close_door} in actions
    end

    {:ok, context}
  end

  defthen ~r/^door is opening$/, _vars, context do
    assert {:open_door} in context.actions or Core.door_status(context.state) == :opening
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

  # --- Helpers ---

  def receive_request(context, source, floor_str) do
    floor = Args.parse_floor(floor_str)
    {state, actions} = Core.request_floor(context.state, {source, floor})
    {:ok, %{context | state: state, actions: actions}}
  end
end
