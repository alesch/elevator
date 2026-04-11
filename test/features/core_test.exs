defmodule Elevator.Features.CoreTest do
  use Cabbage.Feature,
    file: "core.feature",
    async: false

  alias Elevator.Core
  alias Elevator.Gherkin.Arguments
  import ExUnit.Assertions

  setup do
    # Default to idle at ground floor
    {:ok, %{state: Core.idle_at(0), actions: []}}
  end

  # --- Given Steps ---

  defgiven ~r/^the core is in phase (?<phase>.+)$/, %{phase: phase_str}, context do
    phase = Arguments.parse_phase(phase_str)

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

  defgiven ~r/^heading is (?<direction>.+)$/, %{direction: direction_str}, context do
    direction = Arguments.parse_direction(direction_str)
  end

  # --- When Steps ---

  defwhen ~r/^a request for a different floor is received$/, _vars, context do
    {state, actions} = Core.request_floor(context.state, :car, 3)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the core arrives at floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Arguments.parse_floor(floor_str)
    {state, actions} = Core.process_arrival(context.state, floor)
    {:ok, %{context | state: state, actions: actions}}
  end

  # --- Then Steps ---

  defthen ~r/^the phase is (?<value>.+)$/, %{value: val_str}, context do
    expected = Arguments.parse_phase(val_str)
    assert Core.phase(context.state) == expected
    {:ok, context}
  end

  defthen ~r/^the motor is (?<value>.+)$/, %{value: val_str}, context do
    expected = Arguments.parse_motor_status(val_str)

    case {expected, context.actions} do
      {:running, actions} when actions != [] ->
        assert Enum.any?(actions, fn
                 {:move, _} -> true
                 {:crawl, _} -> true
                 _ -> false
               end)

      {:stopping, actions} when actions != [] ->
        assert {:stop_motor} in actions

      _ ->
        assert Core.motor_status(context.state) == expected
    end

    {:ok, context}
  end

  defthen ~r/^the door is "(?<value>.+)"$/, %{value: val_str}, context do
    expected = Arguments.parse_door_status(val_str)

    case {expected, context.actions} do
      {:opening, actions} when actions != [] -> assert {:open_door} in actions
      {:closing, actions} when actions != [] -> assert {:close_door} in actions
      _ -> assert Core.door_status(context.state) == expected
    end

    {:ok, context}
  end

  defthen ~r/^the door timeout timer is set$/, _vars, context do
    assert {:set_timer, :door_timeout, 5000} in context.actions
    {:ok, context}
  end
end
