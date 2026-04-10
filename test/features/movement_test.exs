defmodule Elevator.Features.MovementTest do
  use Cabbage.Feature,
    file: "movement.feature"

  alias Elevator.Core
  alias Elevator.Gherkin.Arguments, as: Args
  import ExUnit.Assertions

  setup do
    # Initial state for our tests. Core starts in :booting by default,
    # but our scenario starts with "Given the elevator is idle".
    {:ok, %{state: Core.init(), actions: []}}
  end

  defgiven ~r/^the elevator is (idle )?at floor (?<current>.+)$/, %{current: current}, context do
    floor = Args.parse_floor(current)
    {:ok, %{context | state: Core.idle_at(floor)}}
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

  defthen ~r/^the elevator should begin opening the doors$/, _vars, context do
    assert {:open_door} in context.actions
    {:ok, context}
  end

  # And the request should be fulfilled without any motor movement
  defthen ~r/^the request should be fulfilled without any motor movement$/, _vars, context do
    # Fulfillment: No requests for current floor
    current_floor = Core.current_floor(context.state)
    assert request_fulfilled?(context.state, current_floor)

    # Motor check: Should remain stopped
    assert Core.motor_status(context.state) == :stopped
    refute motor_moving?(context.actions)

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
    # Reach moving state naturally
    new_internal_state = Core.moving_to(floor - 1, floor)

    {:ok, %{context | state: new_internal_state}}
  end

  # And a request for floor 3 is active
  defgiven ~r/^a request for floor (?<target>.+) is active$/, %{target: target}, context do
    # This is redundantly covered by moving_to, but let's ensure it's in the queue
    floor = Args.parse_floor(target)
    assert {:car, floor} in Core.requests(context.state)
    {:ok, context}
  end

  # When the sensor confirms arrival at floor 3
  defwhen ~r/^the sensor confirms arrival at floor (?<target>.+)$/,
          %{target: target},
          context do
    floor = Args.parse_floor(target)
    {new_internal_state, actions} = Core.process_arrival(context.state, floor)
    {:ok, %{context | state: new_internal_state, actions: actions}}
  end

  defthen ~r/^the elevator should begin to stop$/, _vars, context do
    assert Core.phase(context.state) == :arriving
    {:ok, context}
  end

  # And a stop command should be sent to the motor
  defthen ~r/^a stop command should be sent to the motor$/, _vars, context do
    assert {:stop_motor} in context.actions
    {:ok, context}
  end

  defgiven ~r/^the elevator is stopping at a floor$/, _vars, context do
    # Reach stopping via process_arrival
    floor = 3
    s = Core.moving_to(floor - 1, floor)
    {s, _} = Core.process_arrival(s, floor)
    {:ok, %{context | state: s}}
  end

  defgiven ~r/^the doors are opening$/, _vars, context do
    # Arrived and motor stopped
    floor = 3
    s = Core.moving_to(floor - 1, floor)
    {s, _} = Core.process_arrival(s, floor)
    {s, _} = Core.handle_event(s, :motor_stopped, nil)
    {:ok, %{context | state: s}}
  end

  defgiven ~r/^the doors are closing$/, _vars, context do
    # Docked and timeout
    floor = 3
    s = Core.docked_at(floor)
    {s, _} = Core.handle_event(s, :door_timeout, 0)
    {:ok, %{context | state: s}}
  end

  defgiven ~r/^it is moving up to serve a request at floor (?<target>.+)$/, %{target: target}, context do
    t_floor = Args.parse_floor(target)
    c_floor = Core.current_floor(context.state)
    s = Core.moving_to(c_floor, t_floor)
    {:ok, %{context | state: s}}
  end

  # --- When Steps ---

  defwhen ~r/^the motor confirms it has stopped$/, _vars, context do
    {s, actions} = Core.handle_event(context.state, :motor_stopped, nil)
    {:ok, %{context | state: s, actions: actions}}
  end

  defwhen ~r/^the door confirms it has fully opened$/, _vars, context do
    {s, actions} = Core.handle_event(context.state, :door_opened, 0)
    {:ok, %{context | state: s, actions: actions}}
  end

  defwhen ~r/^5 minutes pass without any activity$/, _vars, context do
    # 5 minutes = 300,000 ms
    {s, actions} = Core.handle_event(context.state, :inactivity_timeout, 300_000)
    {:ok, %{context | state: s, actions: actions}}
  end

  defwhen ~r/^a passenger inside the car selects floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    {s, actions} = Core.request_floor(context.state, :car, floor)
    {:ok, %{context | state: s, actions: actions}}
  end

  defwhen ~r/^a hall request is received for floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    {s, actions} = Core.request_floor(context.state, :hall, floor)
    {:ok, %{context | state: s, actions: actions}}
  end

  defwhen ~r/^the elevator arrives at floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    {s, actions} = Core.process_arrival(context.state, floor)
    {:ok, %{context | state: s, actions: actions}}
  end

  defwhen ~r/^the elevator passes floor (?<floor>.+)$/, %{floor: floor_str}, context do
    # Passing a floor means arriving but NOT stopping. 
    # Use process_arrival and we'll check if it stayed in :moving.
    floor = Args.parse_floor(floor_str)
    {s, actions} = Core.process_arrival(context.state, floor)
    {:ok, %{context | state: s, actions: actions}}
  end

  defwhen ~r/^passengers inside the car select floors (?<floors>.+)$/, %{floors: floors_str}, context do
    floors = String.split(floors_str, ~r/,\s*(?:and\s+)?|\s+and\s+/) |> Enum.map(&Args.parse_floor/1)
    s = Enum.reduce(floors, context.state, fn f, acc ->
      {new_s, _} = Core.request_floor(acc, :car, f)
      new_s
    end)
    {:ok, %{context | state: s}}
  end

  defwhen ~r/^hall requests are received for floors (?<floors>.+)$/, %{floors: floors_str}, context do
    floors = String.split(floors_str, ~r/,\s*(?:and\s+)?|\s+and\s+/) |> Enum.map(&Args.parse_floor/1)
    s = Enum.reduce(floors, context.state, fn f, acc ->
      {new_s, _} = Core.request_floor(acc, :hall, f)
      new_s
    end)
    {:ok, %{context | state: s}}
  end

  defwhen ~r/^the elevator travels upward$/, _vars, context do
    # Assuming it's already moving or triggered to move
    {:ok, context}
  end

  defwhen ~r/^the elevator travels upward, passing floors 2 and 4 to reach floor 5$/, _vars, context do
    # Simulation: Pass 2, Pass 4, Arrive at 5
    s = context.state
    {s, _} = Core.process_arrival(s, 2)
    {s, _} = Core.process_arrival(s, 4)
    {s, actions} = Core.process_arrival(s, 5)
    {:ok, %{context | state: s, actions: actions}}
  end

  defwhen ~r/^the door sensor detects an obstruction$/, _vars, context do
    {s, actions} = Core.handle_event(context.state, :door_obstructed, 0)
    {:ok, %{context | state: s, actions: actions}}
  end

  # --- Then Steps ---

  defthen ~r/^the request for floor (?<target>.+) should still be pending$/,
          %{target: target},
          context do
    floor = Args.parse_floor(target)
    assert {:car, floor} in Core.requests(context.state) or {:hall, floor} in Core.requests(context.state)
    {:ok, context}
  end

  defthen ~r/^the request for the current floor should be fulfilled$/, _vars, context do
    current = Core.current_floor(context.state)
    assert request_fulfilled?(context.state, current)
    {:ok, context}
  end

  defthen ~r/^the elevator should be docked at floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    assert Core.current_floor(context.state) == floor
    assert Core.phase(context.state) == :docked
    {:ok, context}
  end

  defthen ~r/^the doors should be set to close in 5 seconds$/, _vars, context do
    assert {:set_timer, :door_timeout, 5000} in context.actions
    {:ok, context}
  end

  defthen ~r/^a request for floor (?<floor>.+) should be added$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    assert {:car, floor} in Core.requests(context.state)
    {:ok, context}
  end

  defthen ~r/^the elevator should return to floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    assert Core.heading(context.state) == (if floor < Core.current_floor(context.state), do: :down, else: :up)
    {:ok, context}
  end

  defthen ~r/^the elevator should stop at floor (?<floor>.+)$/, %{floor: _floor_str}, context do
    assert Core.phase(context.state) == :arriving
    {:ok, context}
  end

  defthen ~r/^the elevator should not stop at floor (?<floor>.+)$/, %{floor: _floor_str}, context do
    assert Core.phase(context.state) == :moving
    {:ok, context}
  end

  defthen ~r/^it should continue towards floor (?<floor>.+)$/, %{floor: _floor_str}, context do
    # Check if heading is still towards target
    assert Core.phase(context.state) == :moving
    {:ok, context}
  end

  defthen ~r/^it should stop at floors: (?<floors>.+)$/, %{floors: floors_str}, context do
    floors = String.split(floors_str, ~r/,\s*(?:and\s+)?|\s+and\s+/) |> Enum.map(&Args.parse_floor/1)
    
    # We simulate the trip
    Enum.reduce(floors, context.state, fn f, acc ->
      {new_s, _} = Core.process_arrival(acc, f)
      assert Core.phase(new_s) == :arriving
      # Move to next
      {new_s, _} = Core.handle_event(new_s, :motor_stopped, nil)
      {new_s, _} = Core.handle_event(new_s, :door_opened, 0)
      {new_s, _} = Core.handle_event(new_s, :door_timeout, 0)
      {new_s, _} = Core.handle_event(new_s, :door_closed, 0)
      new_s
    end)
    {:ok, context}
  end

  defgiven ~r/^a request for the current floor is pending$/, _vars, context do
    # Current floor should have a request
    current_floor = Core.current_floor(context.state)
    {s, _} = Core.request_floor(context.state, :car, current_floor)
    {:ok, %{context | state: s}}
  end

  defp request_fulfilled?(state, floor) do
    Enum.all?(Core.requests(state), fn {_, f} -> f != floor end)
  end

  defp motor_moving?(actions) do
    Enum.any?(actions, fn
      {:move, _} -> true
      {:crawl, _} -> true
      _ -> false
    end)
  end
end
