defmodule Elevator.Features.StateMachineTest do
  use Cabbage.Feature,
    file: "state_machine.feature",
    async: false

  alias Elevator.Core
  alias Elevator.Gherkin.Arguments
  import ExUnit.Assertions

  setup do
    # Default to idle at ground floor
    {:ok, %{state: Core.idle_at(0), actions: []}}
  end

  # --- Given Steps ---

  defgiven ~r/^the elevator is "(?<phase>.+)" and doors are "(?<door>.+)"$/,
           %{phase: phase_str, door: _door_str},
           context do
    phase = Arguments.parse_phase(phase_str)
    state = case phase do
      :idle -> Core.idle_at(0)
      # We could expand this for other starting states if needed
    end
    {:ok, %{context | state: state}}
  end

  defgiven ~r/^the elevator is in "phase: (?<phase>.+)"$/, %{phase: phase_str}, context do
    phase = Arguments.parse_phase(phase_str)
    state = case phase do
      :moving -> 
        Core.moving_to(0, 3)
      :arriving ->
        # Naturally reach :arriving
        Core.moving_to(0, 3)
        |> Core.process_arrival(3)
        |> elem(0)
      :docked ->
        # Naturally reach :docked
        s = Core.moving_to(0, 0)
        # Note: moving_to(0,0) immediately triggers :arriving/:opening
        {s, _} = Core.handle_event(s, :motor_stopped, nil)
        {s, _} = Core.handle_event(s, :door_opened, 0)
        s
      :leaving ->
        # Reach :leaving via timeout
        s = Core.moving_to(0, 0)
        {s, _} = Core.handle_event(s, :motor_stopped, nil)
        {s, _} = Core.handle_event(s, :door_opened, 0)
        {s, _} = Core.handle_event(s, :door_timeout, 5000)
        s
    end
    {:ok, %{context | state: state}}
  end

  defgiven ~r/^"(?<field>.+)" is "(?<value>.+)"$/, %{field: _field, value: _val_str}, context do
    # Generic field adjustment helper if needed, but we try to avoid direct mutation.
    # For now, we trust the factory state is correct for the phase.
    {:ok, context}
  end

  defgiven ~r/^a request exists for Floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Arguments.parse_floor(floor_str)
    {state, _} = Core.request_floor(context.state, :car, floor)
    {:ok, %{context | state: state}}
  end

  defgiven ~r/^pending work exists in the queue$/, _vars, context do
    # Ensure there is a request ahead
    {state, _} = Core.request_floor(context.state, :car, 5)
    {:ok, %{context | state: state}}
  end

  defgiven ~r/^no pending requests remain$/, _vars, context do
    # This is usually the default after servicing, but we can clear if needed.
    {:ok, context}
  end

  # --- When Steps ---

  defwhen ~r/^a request for a different floor is received$/, _vars, context do
    {state, actions} = Core.request_floor(context.state, :car, 3)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the elevator arrives at floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Arguments.parse_floor(floor_str)
    {state, actions} = Core.process_arrival(context.state, floor)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the "(?<event>.+)" message is received$/, %{event: event_str}, context do
    event = Arguments.parse_phase(event_str) # parse_phase handles leading colons correctly
    {state, actions} = Core.handle_event(context.state, event, 0)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the "(?<event>.+)" event is received$/, %{event: event_str}, context do
    event = Arguments.parse_phase(event_str)
    {state, actions} = Core.handle_event(context.state, event, 5000)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^a "(?<event>.+)" message is received$/, %{event: event_str}, context do
    event = Arguments.parse_phase(event_str)
    {state, actions} = Core.handle_event(context.state, event, nil)
    {:ok, %{context | state: state, actions: actions}}
  end

  # --- Then Steps ---

  defthen ~r/^(the )?"(?<field>.+)" should become "(?<value>.+)"$/, %{field: field, value: val_str}, context do
    expected = Arguments.parse_phase(val_str)
    actual = case field do
      "phase" -> Core.phase(context.state)
      "motor_status" -> Core.motor_status(context.state)
      "door_status" -> Core.door_status(context.state)
    end
    assert actual == expected
    {:ok, context}
  end

  defthen ~r/^"(?<field>.+)" should stay "(?<value>.+)"$/, %{field: field, value: val_str}, context do
    expected = Arguments.parse_phase(val_str)
    actual = case field do
      "motor_status" -> Core.motor_status(context.state)
    end
    assert actual == expected
    {:ok, context}
  end

  defthen ~r/^the door timeout timer should be set$/, _vars, context do
    assert {:set_timer, :door_timeout, 5000} in context.actions
    {:ok, context}
  end
end
