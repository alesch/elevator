defmodule Elevator.SweepTest do
  use Cabbage.Feature, file: "sweep.feature"

  alias Elevator.Sweep
  import ExUnit.Assertions

  setup do
    {:ok, %{sweep: %Sweep{}, current_floor: 0}}
  end

  # Given a sweep with heading up and the elevator at floor 3
  defgiven ~r/^a sweep with heading (?<heading>up|down|idle)(?: and the elevator at floor (?<floor>\d+))?$/, 
           %{heading: heading_str, floor: floor_str}, state do
    heading = String.to_existing_atom(heading_str)
    floor = if floor_str, do: String.to_integer(floor_str), else: 0
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
    floors = floors_str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&String.to_integer/1)
    new_sweep = Enum.reduce(floors, state.sweep, fn f, acc -> Sweep.add_request(acc, :car, f) end)
    {:ok, %{state | sweep: new_sweep}}
  end

  # Then the ordered queue should be: 2, 4, 5
  defthen ~r/^the ordered queue should be: (?<floors>.+)$/, %{floors: floors_str}, state do
    expected_floors = floors_str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&String.to_integer/1)
    
    # Extract only floors from the requests, using current_floor
    actual_floors = Sweep.ordered_queue(state.sweep, state.current_floor) |> Enum.map(fn {_, f} -> f end) |> Enum.uniq()
    
    assert actual_floors == expected_floors
    {:ok, state}
  end

  # Given a car/hall request for floor X
  defgiven ~r/^a (?<source>car|hall) request for floor (?<floor>\d+)$/, %{source: source_str, floor: floor_str}, state do
    source = String.to_existing_atom(source_str)
    floor = String.to_integer(floor_str)
    new_sweep = Sweep.add_request(state.sweep, source, floor)
    {:ok, %{state | sweep: new_sweep}}
  end

  # When the elevator reaches floor X
  # When the elevator is at floor X
  defwhen ~r/^the elevator (?:is at|reaches) floor (?<floor>\d+)$/, %{floor: floor_str}, state do
    floor = String.to_integer(floor_str)
    {:ok, Map.put(state, :current_floor, floor)}
  end



  # Given a sweep with car and hall requests for floor 3
  defgiven ~r/^a sweep with car and hall requests for floor (?<floor>\d+)$/, %{floor: floor_str}, state do
    floor = String.to_integer(floor_str)
    new_sweep = state.sweep 
                |> Sweep.add_request(:car, floor)
                |> Sweep.add_request(:hall, floor)
    {:ok, %{state | sweep: new_sweep}}
  end

  # When floor 3 is serviced
  defwhen ~r/^floor (?<floor>\d+) is serviced$/, %{floor: floor_str}, state do
    floor = String.to_integer(floor_str)
    new_sweep = Sweep.floor_serviced(state.sweep, floor)
    {:ok, %{state | sweep: new_sweep}}
  end

  # Then there should be no requests for floor 3
  defthen ~r/^there should be no requests for floor (?<floor>\d+)$/, %{floor: floor_str}, state do
    floor = String.to_integer(floor_str)
    refute Enum.any?(state.sweep.requests, fn {_, f} -> f == floor end)
    {:ok, state}
  end

  # Then the next stop should be floor X
  defthen ~r/^the next stop should be floor (?<floor>\d+)$/, %{floor: floor_str}, state do
    floor = String.to_integer(floor_str)
    assert Sweep.next_stop(state.sweep, state.current_floor) == floor
    {:ok, state}
  end
end
