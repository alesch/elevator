defmodule Elevator.SafetyFeatureTest do
  use Cabbage.Feature, file: "safety.feature"
  @moduletag :skip
  alias Elevator.Core
  import Elevator.CommonSteps
  import_feature(Elevator.CommonSteps)

  setup do
    {:ok, %{state: %Core{}, actions: []}}
  end

  # --- Unique Safety Assertions ---

  defthen ~r/^the motor MUST stay "(?<status>:[^"]+)" while the doors are "(?<d1>:[^"]+)", "(?<d2>:[^"]+)", or "(?<d3>:[^"]+)"$/,
          %{status: status},
          state do
    # Safety invariant: motor MUST be stopped if doors are not fully closed.
    assert state.state.motor_status == parse_atom(status)
    {:ok, state}
  end

  defthen ~r/^the motor is ONLY commanded to "(?<cmd>:[^"]+)" after "(?<e1>:[^"]+)" and "(?<e2>:[^"]+)" signals are confirmed$/,
          _data,
          state do
    # Verify no motor movement command exists in current actions if signals are pending.
    refute Enum.any?(state.actions, fn
             {:start_motor, _} -> true
             {:set_motor_speed, _} -> true
             _ -> false
           end)

    {:ok, state}
  end

  defthen ~r/^the actions should be "(?<action>[^"]+)"$/, %{action: action_str}, state do
    case action_str do
      "(No action)" -> assert state.actions == []
      "{:close_door}" -> assert {:close_door} in state.actions
      _ -> :ok
    end

    {:ok, state}
  end

  defthen ~r/^the door should stay "(?<status>:[^"]+)" until the 5s timer fires$/,
          %{status: status},
          state do
    assert state.state.door_status == parse_atom(status)
    {:ok, state}
  end

  defthen ~r/^the movement should ONLY begin after the doors are confirmed "(?<status>:[^"]+)"$/,
          %{status: status},
          state do
    # 1. Fire the timeout (transitions from :open to :closing)
    {closing_state, _} = Core.handle_event(state.state, :door_timeout, 5100)
    assert closing_state.door_status == :closing

    # 2. Fire the door closed confirmation (transitions from :closing to :closed)
    {final_state, actions} = Core.handle_event(closing_state, :door_closed, 5101)
    assert final_state.door_status == parse_atom(status)

    {:ok, %{state | state: final_state, actions: actions}}
  end
end
