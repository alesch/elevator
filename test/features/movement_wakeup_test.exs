defmodule Elevator.MovementWakeupTest do
  use Cabbage.Feature, file: "movement_wakeup.feature", scenarios: ["Wake up from idle state", "Arrival at target floor"]
  alias Elevator.Core
  alias Elevator.Gherkin.Arguments, as: Args
  import ExUnit.Assertions

  setup do
    # Initial state for our tests. Core starts in :booting by default,
    # but our scenario starts with "Given the elevator is idle".
    {:ok, %{state: %Core{}, actions: []}}
  end


  # @S-MOVE-WAKEUP
  # Given the elevator is idle at floor <current>
  defgiven ~r/^the elevator is idle at floor (?<current>.+)$/, %{current: current}, state do
    floor = Args.parse_floor(current)

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
    floor = Args.parse_floor(target)

    # Trigger the core logic
    {new_internal_state, actions} = Core.request_floor(context.state, :car, floor)

    {:ok, %{context | state: new_internal_state, actions: actions}}
  end

  # Then the elevator should start moving <heading>
  defthen ~r/^the elevator should start moving (?<heading>up|down)$/,
          %{heading: heading_str},
          state do
    expected_heading = Args.parse_heading(heading_str)

    # Assertions on state
    assert state.state.phase == :moving
    assert state.state.heading == expected_heading

    # Assertions on derived actions
    assert {:move, expected_heading} in state.actions

    {:ok, state}
  end

  # And floor <target> should be in the pending requests
  defthen ~r/^floor (?<target>.+) should be in the pending requests$/, %{target: target}, state do
    floor = Args.parse_floor(target)

    assert {:car, floor} in state.state.requests

    {:ok, state}
  end

  # @S-MOVE-BRAKING
  # Given the elevator is moving up towards floor 3
  defgiven ~r/^the elevator is moving up towards floor (?<target>.+)$/, %{target: target}, state do
    floor = Args.parse_floor(target)
    # Positioning the elevator just before the target floor
    new_internal_state = %{
      state.state
      | phase: :moving,
        current_floor: floor - 1,
        heading: :up,
        motor_status: :running
    }

    {:ok, %{state | state: new_internal_state}}
  end

  # And a request for floor 3 is active
  defgiven ~r/^a request for floor (?<target>.+) is active$/, %{target: target}, state do
    floor = Args.parse_floor(target)
    new_internal_state = %{state.state | requests: [{:car, floor}]}
    {:ok, %{state | state: new_internal_state}}
  end

  # When the sensor confirms arrival at floor 3
  defwhen ~r/^the sensor confirms arrival at floor (?<target>.+)$/,
          %{target: target},
          context do
    floor = Args.parse_floor(target)
    {new_internal_state, actions} = Core.process_arrival(context.state, floor)
    {:ok, %{context | state: new_internal_state, actions: actions}}
  end

  # Then the elevator should begin to stop
  defthen ~r/^the elevator should begin to stop$/, _vars, state do
    assert state.state.phase == :arriving
    assert state.state.motor_status == :stopping
    {:ok, state}
  end

  # And a stop command should be sent to the motor
  defthen ~r/^a stop command should be sent to the motor$/, _vars, state do
    assert {:stop_motor} in state.actions
    {:ok, state}
  end

  # And the request for floor 3 should still be pending
  defthen ~r/^the request for floor (?<target>.+) should still be pending$/,
          %{target: target},
          state do
    floor = Args.parse_floor(target)
    assert {:car, floor} in state.state.requests
    {:ok, state}
  end
end
