defmodule Elevator.Features.SafetyTest do
  use Cabbage.Feature,
    file: "safety.feature"

  alias Elevator.Core
  alias Elevator.Gherkin.Arguments, as: Args
  import ExUnit.Assertions

  setup do
    {:ok, %{state: Core.init(), actions: []}}
  end

  # Given logic
  defgiven ~r/^the elevator is in phase "(?<phase>.+)"$/, %{phase: phase_str}, context do
    phase = Args.parse_phase(phase_str)

    # Use public API / factory methods to reach the desired state
    state = case phase do
      :booting ->
        Core.init()

      :rehoming ->
        {s, _actions} = Core.handle_event(Core.init(), :rehoming_started)
        s

      _ ->
        raise ArgumentError, "Phase #{inspect(phase)} setup not implemented in this test."
    end

    {:ok, %{context | state: state}}
  end

  # When logic
  defwhen ~r/^"(?<source>.+)" request for floor "(?<target>.+)" is received$/,
          %{source: source_str, target: target_str},
          context do
    source = Args.parse_source(source_str)
    target = Args.parse_floor(target_str)

    {new_state, actions} = Core.request_floor(context.state, source, target)
    {:ok, %{context | state: new_state, actions: actions}}
  end

  defwhen ~r/^the "(?<button>.+)" button is pressed$/, %{button: button_str}, context do
    button = Args.parse_button(button_str)
    now = 1000 # Mock time
    {new_state, actions} = Core.handle_button_press(context.state, button, now)
    {:ok, %{context | state: new_state, actions: actions}}
  end

  # Then logic
  defthen ~r/^the request should be ignored$/, _vars, context do
    # If ignored, the request queue remains empty and no actions are returned
    assert Core.requests(context.state) == []
    assert context.actions == []
    {:ok, context}
  end

  defthen ~r/^the button should be ignored$/, _vars, context do
    # If ignored, no actions (like :open_door or :close_door) are returned
    assert context.actions == []
    # And last_activity_at should still be 0 (initial state value)
    assert context.state.last_activity_at == 0
    {:ok, context}
  end
end
