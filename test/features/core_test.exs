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

  defgiven ~r/^the core is "(?<phase>.+)" and doors are "(?<door>.+)"$/,
           %{phase: phase_str, door: _door_str},
           context do
    phase = Arguments.parse_phase(phase_str)

    state =
      case phase do
        :idle ->
          Core.idle_at(0)
          # We could expand this for other starting states if needed
      end

    {:ok, %{context | state: state}}
  end

  defgiven ~r/^the core is in "phase: (?<phase>.+)"$/, %{phase: phase_str}, context do
    phase = Arguments.parse_phase(phase_str)

    state =
      case phase do
        :moving ->
          Core.moving_to(0, 3)

        :arriving ->
          # Reach :arriving and settle motor
          {s, _} = Core.moving_to(0, 3) |> Core.process_arrival(3)
          {s, _} = Core.handle_event(s, :motor_stopped, nil)
          # And start door opening
          {s, _} = Core.handle_event(s, :door_opened, 0)
          # Wait, Arriving -> Docked happens ON door_opened.
          # If we are ALREADY in arriving and motor stopped, door is opening.
          # Let's just use a dedicated factory if we had one, or build it carefully.
          s = Core.moving_to(0, 3) |> elem(0)
          {s, _} = Core.handle_event(s, :arrival, 3) # -> arriving phase, stop_motor action
          {s, _} = Core.handle_event(s, :motor_stopped) # -> opening door action
          # Physical door status is still :closed, logic is :arriving.
          # The scenario says And "door_status" is ":opening".
          # So we MUST ingest opening.
          Core.handle_event(s, :door_opening) |> elem(0)

        :docked ->
          Core.docked_at(3)

        :leaving ->
          # Reach :leaving via timeout and start close
          s = Core.docked_at(3)
          {s, _} = Core.handle_event(s, :door_timeout, 5000)
          # Now logic is :leaving, action is :close_door. Reality is still :open.
          # Scenario says And "door_status" is ":closing".
          Core.handle_event(s, :door_closing) |> elem(0)
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

  defwhen ~r/^the core arrives at floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Arguments.parse_floor(floor_str)
    {state, actions} = Core.process_arrival(context.state, floor)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the "(?<event>.+)" message is received$/, %{event: event_str}, context do
    event = Arguments.parse_event(event_str)
    {state, actions} = Core.handle_event(context.state, event, 0)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^the "(?<event>.+)" event is received$/, %{event: event_str}, context do
    event = Arguments.parse_event(event_str)
    {state, actions} = Core.handle_event(context.state, event, 5000)
    {:ok, %{context | state: state, actions: actions}}
  end

  defwhen ~r/^a "(?<event>.+)" message is received$/, %{event: event_str}, context do
    event = Arguments.parse_event(event_str)
    {state, actions} = Core.handle_event(context.state, event, nil)
    {:ok, %{context | state: state, actions: actions}}
  end

  # --- Then Steps ---

  defthen ~r/^(the )?"?(?<subject>phase|motor_status|door_status)"? (?<verb>should become|should stay|is) "(?<value>.+)"$/,
          %{subject: subject, verb: verb, value: val_str},
          context do
    case subject do
      "phase" ->
        expected = Arguments.parse_phase(val_str)
        assert Core.phase(context.state) == expected

      "motor_status" ->
        expected = Arguments.parse_motor_status(val_str)

        if verb == "should become" do
          case expected do
            :running ->
              assert Enum.any?(context.actions, fn
                       {:move, _} -> true
                       {:crawl, _} -> true
                       _ -> false
                     end)

            :stopping ->
              assert {:stop_motor} in context.actions

            _ ->
              assert Core.motor_status(context.state) == expected
          end
        else
          assert Core.motor_status(context.state) == expected
        end

      "door_status" ->
        expected = Arguments.parse_door_status(val_str)

        if verb == "should become" do
          case expected do
            :opening -> assert {:open_door} in context.actions
            :closing -> assert {:close_door} in context.actions
            _ -> assert Core.door_status(context.state) == expected
          end
        else
          assert Core.door_status(context.state) == expected
        end
    end

    {:ok, context}
  end

  defthen ~r/^the door timeout timer should be set$/, _vars, context do
    assert {:set_timer, :door_timeout, 5000} in context.actions
    {:ok, context}
  end
end
