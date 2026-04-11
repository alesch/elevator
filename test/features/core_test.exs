defmodule Elevator.Features.CoreTest do
  use Cabbage.Feature,
    file: "core.feature",
    async: false

  alias Elevator.Core
  alias Elevator.Gherkin.Arguments, as: Args
  import_steps Elevator.Gherkin.Steps
  import ExUnit.Assertions

  setup do
    # Default to idle at ground floor
    {:ok, %{state: Core.idle_at(0), actions: []}}
  end

  # --- Given Steps ---

  defgiven ~r/^the core is in phase (?<phase>.+)$/, %{phase: phase_str}, context do
    phase = Args.parse_phase(phase_str)

    state =
      case phase do
        :idle ->
          Core.idle_at(0)

        :moving ->
          Core.moving_to(0, 3)

        :arriving ->
          # Reach :arriving and simulate motor stop + door starting to open
          s = Core.moving_to(0, 3)
          {s, _} = Core.handle_event(s, :arrival, 3)
          {s, _} = Core.handle_event(s, :motor_stopped)
          {s, _} = Core.handle_event(s, :door_opening)
          s

        :docked ->
          Core.docked_at(3)

        :leaving ->
          # Reach :leaving via timeout and start close
          s = Core.docked_at(3)
          {s, _} = Core.handle_event(s, :door_timeout, 5000)
          {s, _} = Core.handle_event(s, :door_closing)
          s
      end

    {:ok, %{context | state: state}}
  end

  defgiven ~r/^a request exists for Floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
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

  defgiven ~r/^heading is (?<heading>.+)$/, %{heading: heading_str}, context do
    heading = Args.parse_heading(heading_str)
    state = put_in(context.state.logic.sweep.heading, heading)
    {:ok, %{context | state: state}}
  end

  # --- When Steps ---

  defwhen ~r/^a request for a different floor is received$/, _vars, context do
    {state, actions} = Core.request_floor(context.state, :car, 3)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the core arrives at floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    {state, actions} = Core.process_arrival(context.state, floor)
    {:ok, %{context | state: state, actions: actions}}
  end

  # --- Then Steps ---


  defthen ~r/^the door timeout timer is set$/, _vars, context do
    assert {:set_timer, :door_timeout, 5000} in context.actions
    {:ok, context}
  end

  # --- Missing Steps ---

  defgiven ~r/^door is opening$/, _vars, context do
    {state, _} = Core.handle_event(context.state, :door_opening)
    {:ok, %{context | state: state}}
  end

  defgiven ~r/^door is open$/, _vars, context do
    {state, _} = Core.handle_event(context.state, :door_opened, 0)
    {:ok, %{context | state: state}}
  end

  defgiven ~r/^door is closing$/, _vars, context do
    {state, _} = Core.handle_event(context.state, :door_closing)
    {:ok, %{context | state: state}}
  end

  defgiven ~r/^door_sensor is clear$/, _vars, context do
    {state, _} = Core.handle_event(context.state, :door_cleared)
    {:ok, %{context | state: state}}
  end

  defgiven ~r/^the motor is stopped$/, _vars, context do
    {state, _} = Core.handle_event(context.state, :motor_stopped)
    {:ok, %{context | state: state}}
  end

  defwhen ~r/^the door is confirmed open$/, _vars, context do
    {state, actions} = Core.handle_event(context.state, :door_opened, 0)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the door is confirmed closed$/, _vars, context do
    {state, actions} = Core.handle_event(context.state, :door_closed)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the door timeout expires$/, _vars, context do
    {state, actions} = Core.handle_event(context.state, :door_timeout, 5000)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the door is obstructed$/, _vars, context do
    {state, actions} = Core.handle_event(context.state, :door_obstructed, 0)
    {:ok, %{context | state: state, actions: actions}}
  end

  defthen ~r/^door is closing$/, _vars, context do
    assert Core.door_status(context.state) == :closing
    {:ok, context}
  end

  defthen ~r/^door is opening$/, _vars, context do
    assert Core.door_status(context.state) == :opening
    {:ok, context}
  end

  defthen ~r/^door is open$/, _vars, context do
    assert Core.door_status(context.state) == :open
    {:ok, context}
  end

  defthen ~r/^the motor is running$/, _vars, context do
    assert Core.motor_status(context.state) == :running or {:move, :up} in context.actions or {:move, :down} in context.actions or {:crawl, :down} in context.actions
    {:ok, context}
  end

  defthen ~r/^the motor is stopping$/, _vars, context do
    assert Core.motor_status(context.state) == :stopping or {:stop_motor} in context.actions
    {:ok, context}
  end
end
