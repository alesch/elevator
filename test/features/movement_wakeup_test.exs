defmodule Elevator.MovementWakeupTest do
  use Cabbage.Feature,
    file: "movement_wakeup.feature",
    scenarios: ["Wake up from idle state", "Arrival at target floor"]

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
  defgiven ~r/^the elevator is idle at floor (?<current>.+)$/, %{current: current}, context do
    floor = Args.parse_floor(current)

    # We initialize the state to match the "idle" requirement.
    # In a real system, it would have reached :idle via the booting/recovery sequence.
    new_internal_state = %{
      context.state
      | phase: :idle,
        current_floor: floor,
        door_status: :closed,
        motor_status: :stopped,
        sweep: %Elevator.Sweep{heading: :idle}
    }

    {:ok, %{context | state: new_internal_state}}
  end

  # When a request for floor <target> is received
  defwhen ~r/^a request for floor (?<target>.+) is received$/, %{target: target}, context do
    floor = Args.parse_floor(target)

    # Trigger the core logic
    {new_internal_state, actions} = Core.request_floor(context.state, :car, floor)

    {:ok, %{context | state: new_internal_state, actions: actions}}
  end

  # Then the elevator should start moving <heading>
  defthen ~r/^the elevator should start moving (?<heading>.+)$/,
          %{heading: heading_str},
          context do
    expected_heading = Args.parse_heading(heading_str)

    # Assertions on state
    assert Core.phase(context.state) == :moving
    assert Core.heading(context.state) == expected_heading

    # Assertions on derived actions
    assert {:move, expected_heading} in context.actions

    {:ok, context}
  end

  # Then the elevator should begin opening the doors
  defthen ~r/^the elevator should begin opening the doors$/, _vars, context do
    assert Core.door_status(context.state) == :opening
    assert {:open_door} in context.actions

    {:ok, context}
  end

  # And the request should be fulfilled without any motor movement
  defthen ~r/^the request should be fulfilled without any motor movement$/, _vars, context do
    # Fulfillment: No requests for current floor
    current_floor = Core.current_floor(context.state)
    assert Enum.all?(Core.requests(context.state), fn {_, f} -> f != current_floor end)

    # Motor check: Should remain stopped
    assert Core.motor_status(context.state) == :stopped
    refute Enum.any?(context.actions, fn a -> match?({:move, _}, a) end)

    {:ok, context}
  end

  # And floor <target> should be in the pending requests
  defthen ~r/^floor (?<target>.+) should be in the pending requests$/,
          %{target: target},
          context do
    floor = Args.parse_floor(target)

    assert {:car, floor} in Core.requests(context.state)

    {:ok, context}
  end

  # @S-MOVE-BRAKING
  # Given the elevator is moving up towards floor 3
  defgiven ~r/^the elevator is moving up towards floor (?<target>.+)$/,
           %{target: target},
           context do
    floor = Args.parse_floor(target)
    # Positioning the elevator just before the target floor
    new_internal_state = %{
      context.state
      | phase: :moving,
        current_floor: floor - 1,
        sweep: %Elevator.Sweep{heading: :up},
        motor_status: :running
    }

    {:ok, %{context | state: new_internal_state}}
  end

  # And a request for floor 3 is active
  defgiven ~r/^a request for floor (?<target>.+) is active$/, %{target: target}, context do
    floor = Args.parse_floor(target)

    new_internal_state = %{
      context.state
      | sweep: %Elevator.Sweep{context.state.sweep | requests: [{:car, floor}]}
    }

    {:ok, %{context | state: new_internal_state}}
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
  defthen ~r/^the elevator should begin to stop$/, _vars, context do
    assert Core.phase(context.state) == :arriving
    assert Core.motor_status(context.state) == :stopping
    {:ok, context}
  end

  # And a stop command should be sent to the motor
  defthen ~r/^a stop command should be sent to the motor$/, _vars, context do
    assert {:stop_motor} in context.actions
    {:ok, context}
  end

  # And the request for floor 3 should still be pending
  defthen ~r/^the request for floor (?<target>.+) should still be pending$/,
          %{target: target},
          context do
    floor = Args.parse_floor(target)
    assert {:car, floor} in Core.requests(context.state)
    {:ok, context}
  end
end
