defmodule Elevator.SweepTest do
  use Cabbage.Feature,
    file: "sweep.feature",
    # async: true is actually slower for this feature
    async: false

  alias Elevator.Sweep
  alias Elevator.Gherkin.Arguments
  import ExUnit.Assertions

  setup do
    {:ok, %{sweep: %Sweep{}, current_floor: 0}}
  end

  # Given a sweep with heading up and the elevator at floor 3
  defgiven ~r/^a sweep with heading (?<heading>.+) and the elevator at floor (?<floor>.+)$/,
           %{heading: heading_str, floor: floor_str},
           state do
    heading = Arguments.parse_heading(heading_str)
    floor = Arguments.parse_floor(floor_str)
    {:ok, %{state | sweep: %{state.sweep | heading: heading}, current_floor: floor}}
  end

  # When requests are added for floors: 5, 2, 4
  # Given requests for floors: 2, 5
  defgiven ~r/^requests for floors: (?<floors>.+)$/, %{floors: floors_str}, state do
    do_add_requests(state, floors_str)
  end

  defwhen ~r/^requests are added for floors: (?<floors>.+)$/, %{floors: floors_str}, state do
    do_add_requests(state, floors_str)
  end

  defp do_add_requests(state, floors_str) do
    floors = Arguments.parse_list(floors_str, &Arguments.parse_floor/1)
    new_sweep = Enum.reduce(floors, state.sweep, fn f, acc -> Sweep.add_request(acc, :car, f) end)
    {:ok, %{state | sweep: new_sweep}}
  end

  # Then the queue should be: 2, 4, 5
  defthen ~r/^the queue should be: (?<floors>.+)$/, %{floors: floors_str}, state do
    expected_floors = Arguments.parse_list(floors_str, &Arguments.parse_floor/1)

    # Extract only floors from the requests, using current_floor
    actual_floors =
      state.sweep
      |> Sweep.queue(state.current_floor)
      |> Enum.map(fn {_, f} -> f end)
      |> Enum.uniq()

    assert actual_floors == expected_floors
    {:ok, state}
  end

  # Given a car/hall request for floor X
  defgiven ~r/^a (?<source>.+) request for floor (?<floor>.+)$/,
           %{source: source_str, floor: floor_str},
           state do
    source = Arguments.parse_source(source_str)
    floor = Arguments.parse_floor(floor_str)
    new_sweep = Sweep.add_request(state.sweep, source, floor)
    {:ok, %{state | sweep: new_sweep}}
  end

  # When the elevator reaches floor X
  # When the elevator is at floor X
  defwhen ~r/^the elevator is at floor (?<floor>.+)$/, %{floor: floor_str}, state do
    floor = Arguments.parse_floor(floor_str)
    {:ok, Map.put(state, :current_floor, floor)}
  end

  # Given a sweep with car and hall requests for floor 3
  defgiven ~r/^a sweep with car and hall requests for floor (?<floor>.+)$/,
           %{floor: floor_str},
           state do
    floor = Arguments.parse_floor(floor_str)

    new_sweep =
      state.sweep
      |> Sweep.add_request(:car, floor)
      |> Sweep.add_request(:hall, floor)

    {:ok, %{state | sweep: new_sweep}}
  end

  # When floor 3 is serviced
  defwhen ~r/^floor (?<floor>.+) is serviced$/, %{floor: floor_str}, state do
    floor = Arguments.parse_floor(floor_str)
    new_sweep = Sweep.floor_serviced(state.sweep, floor)
    {:ok, %{state | sweep: new_sweep}}
  end

  # Then there should be no requests for floor 3
  defthen ~r/^there should be no requests for floor (?<floor>.+)$/, %{floor: floor_str}, state do
    floor = Arguments.parse_floor(floor_str)
    refute Enum.any?(state.sweep.requests, fn {_, f} -> f == floor end)
    {:ok, state}
  end

  # Then the next stop should be floor X
  defthen ~r/^the next stop should be floor (?<floor>.+)$/, %{floor: floor_str}, state do
    floor = Arguments.parse_floor(floor_str)
    assert Sweep.next_stop(state.sweep, state.current_floor) == floor
    {:ok, state}
  end

  # Then the heading should be up
  defthen ~r/^the heading should be (?<heading>.+)$/, %{heading: heading_str}, state do
    expected_heading = Arguments.parse_heading(heading_str)

    # We check what the heading BECOMES when updated from the current position
    actual_sweep = Sweep.update_heading(state.sweep, state.current_floor)

    assert actual_sweep.heading == expected_heading
    {:ok, state}
  end
end
