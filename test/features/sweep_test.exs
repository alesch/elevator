defmodule Elevator.Features.SweepTest do
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
           context do
    heading = Arguments.parse_heading(heading_str)
    floor = Arguments.parse_floor(floor_str)
    {:ok, %{context | sweep: %{context.sweep | heading: heading}, current_floor: floor}}
  end

  # Given requests for floors: 2, 5
  defgiven ~r/^car requests for floors: (?<floors>.+)$/, %{floors: floors_str}, context do
    do_add_car_requests(context, floors_str)
  end

  # When requests are added for floors: 5, 2, 4
  defwhen ~r/^car requests are added for floors: (?<floors>.+)$/,
          %{floors: floors_str},
          context do
    do_add_car_requests(context, floors_str)
  end

  # Then the queue should be: 2, 4, 5
  defthen ~r/^the queue should be: (?<floors>.+)$/, %{floors: floors_str}, context do
    expected_floors = Arguments.parse_list(floors_str, &Arguments.parse_floor/1)

    # Extract only floors from the requests, using current_floor
    actual_floors =
      context.sweep
      |> Sweep.queue(context.current_floor)
      |> Enum.map(fn {_, f} -> f end)
      |> Enum.uniq()

    assert actual_floors == expected_floors
    {:ok, context}
  end

  # Given a car/hall request for floor X
  defgiven ~r/^a (?<source>.+) request for floor (?<floor>.+)$/,
           %{source: source_str, floor: floor_str},
           context do
    source = Arguments.parse_source(source_str)
    floor = Arguments.parse_floor(floor_str)
    do_add_request(context, floor, source)
  end

  # --- Helpers ---

  defp do_add_request(context, floor, source) do
    new_sweep = Sweep.add_request(context.sweep, source, floor)
    {:ok, %{context | sweep: new_sweep}}
  end

  defp do_add_car_requests(context, floors_str) do
    floors = Arguments.parse_list(floors_str, &Arguments.parse_floor/1)

    Enum.reduce(floors, {:ok, context}, fn floor, {:ok, ctx} ->
      do_add_request(ctx, floor, :car)
    end)
  end

  # When the elevator reaches floor X
  # When the elevator is at floor X
  defwhen ~r/^the elevator is at floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Arguments.parse_floor(floor_str)
    {:ok, Map.put(context, :current_floor, floor)}
  end

  # Given a sweep with car and hall requests for floor 3
  defgiven ~r/^a sweep with car and hall requests for floor (?<floor>.+)$/,
           %{floor: floor_str},
           context do
    floor = Arguments.parse_floor(floor_str)

    new_sweep =
      context.sweep
      |> Sweep.add_request(:car, floor)
      |> Sweep.add_request(:hall, floor)

    {:ok, %{context | sweep: new_sweep}}
  end

  # When floor 3 is serviced
  defwhen ~r/^floor (?<floor>.+) is serviced$/, %{floor: floor_str}, context do
    floor = Arguments.parse_floor(floor_str)
    new_sweep = Sweep.floor_serviced(context.sweep, floor)
    {:ok, %{context | sweep: new_sweep}}
  end

  # Then there should be no requests for floor 3
  defthen ~r/^there should be no requests for floor (?<floor>.+)$/,
          %{floor: floor_str},
          context do
    floor = Arguments.parse_floor(floor_str)
    refute Enum.any?(Sweep.requests(context.sweep), fn {_, f} -> f == floor end)
    {:ok, context}
  end

  # Then the next stop should be floor X
  defthen ~r/^the next stop should be floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Arguments.parse_floor(floor_str)
    assert Sweep.next_stop(context.sweep, context.current_floor) == floor
    {:ok, context}
  end

  # Then the heading should be up
  defthen ~r/^the heading should be (?<heading>.+)$/, %{heading: heading_str}, context do
    expected_heading = Arguments.parse_heading(heading_str)

    # We check what the heading BECOMES when updated from the current position
    actual_sweep = Sweep.update_heading(context.sweep, context.current_floor)

    assert Sweep.heading(actual_sweep) == expected_heading
    {:ok, context}
  end
end
