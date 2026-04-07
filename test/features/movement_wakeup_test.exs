defmodule Elevator.MovementWakeupTest do
  use Cabbage.Feature, file: "movement_wakeup.feature", scenarios: ["Wake up from idle state"]
  alias Elevator.Core
  import ExUnit.Assertions

  setup do
    # Initial state for our tests. Core starts in :booting by default,
    # but our scenario starts with "Given the elevator is idle".
    {:ok, %{state: %Core{}, actions: []}}
  end

  defp parse_floor("ground"), do: 0

  defp parse_floor(n) when is_binary(n) do
    case Integer.parse(n) do
      {num, _} -> num
      :error -> n
    end
  end

  defp parse_floor(num) when is_integer(num), do: num

  # @S-MOVE-WAKEUP
  # Given the elevator is idle at floor <current>
  defgiven ~r/^the elevator is idle at floor (?<current>.+)$/, %{current: current}, state do
    floor = parse_floor(current)

    # We initialize the state to match the "idle" requirement.
    # In a real system, it would have reached :idle via the booting/recovery sequence.
    new_internal_state = %{
      state.state
      | phase: :idle,
        current_floor: floor,
        door_status: :closed,
        motor_status: :stopped,
        heading: :idle
    }

    {:ok, %{state | state: new_internal_state}}
  end

  # When a request for floor <target> is received
  defwhen ~r/^a request for floor (?<target>.+) is received$/, %{target: target}, context do
    floor = parse_floor(target)

    # Trigger the core logic
    {new_internal_state, actions} = Core.request_floor(context.state, :car, floor)

    {:ok, %{context | state: new_internal_state, actions: actions}}
  end

  # Then the elevator should start moving <heading>
  defthen ~r/^the elevator should start moving (?<heading>up|down)$/,
          %{heading: heading_str},
          state do
    expected_heading = String.to_atom(heading_str)

    # Assertions on state
    assert state.state.phase == :moving
    assert state.state.heading == expected_heading

    # Assertions on derived actions
    assert {:move, expected_heading} in state.actions

    {:ok, state}
  end

  # And floor <target> should be in the pending requests
  defthen ~r/^floor (?<target>.+) should be in the pending requests$/, %{target: target}, state do
    floor = parse_floor(target)

    assert {:car, floor} in state.state.requests

    {:ok, state}
  end
end
