defmodule Elevator.Features.SweepTest do
  use Cabbage.Feature,
    file: "sweep.feature",
    # async: true is actually slower for this feature
    async: false

  alias Elevator.Sweep
  alias Elevator.Gherkin.Arguments
  import ExUnit.Assertions

  defmacro trace(context) do
    quote do
      # Capture the line in the test file where trace(context) was called.
      location = "#{Path.basename(__ENV__.file)}:#{__ENV__.line}"

      # Accumulate into a list called :step_history
      Map.update(unquote(context), :step_history, [location], fn history ->
        [location | history]
      end)
    end
  end

  setup context do
    {:ok, %{sweep: %Sweep{}, current_floor: 0, scenario: context.test}}
  end

  #
  # --- Given ---
  #

  # Given a new sweep
  defgiven ~r/^a new sweep$/, _vars, context do
    context = trace(context)
    {:ok, %{context | sweep: %Sweep{}, current_floor: 0}}
  end

  # Given the elevator is at floor X
  defgiven ~r/^the elevator is at floor (?<floor>.+)$/, %{floor: floor_str}, context do
    context = trace(context)
    floor = Arguments.parse_floor(floor_str)
    {:ok, %{context | current_floor: floor}}
  end

  #
  # --- When ---
  #

  # When car requests for floors 2, 5
  defwhen ~r/^car requests are added for floors (?<floors>.+)$/, %{floors: floors_str}, context do
    context = trace(context)
    do_add_car_requests(context, floors_str)
  end

  # When a car/hall request for floor X is added
  defwhen ~r/^a (?<source>.+) request for floor (?<floor>.+) is added$/,
          %{source: source_str, floor: floor_str},
          context do
    context = trace(context)
    source = Arguments.parse_source(source_str)
    floor = Arguments.parse_floor(floor_str)
    do_add_request(context, floor, source)
  end

  # When floor 3 is serviced
  defwhen ~r/^floor (?<floor>.+) is serviced$/, %{floor: floor_str}, context do
    context = trace(context)
    floor = Arguments.parse_floor(floor_str)
    new_sweep = Sweep.floor_serviced(context.sweep, floor)
    {:ok, %{context | sweep: new_sweep}}
  end

  #
  # --- Then ---
  #

  # Then the queue should be 2, 4, 5
  defthen ~r/^the queue should be (?<floors>.+)$/, %{floors: floors_str}, context do
    context = trace(context)
    expected_floors = Arguments.parse_list(floors_str, &Arguments.parse_floor/1)

    actual_floors =
      context.sweep
      |> Sweep.queue(context.current_floor)
      |> extract_floors()

    assert actual_floors == expected_floors
    {:ok, context}
  end

  # Then there should be no requests for floor 3
  defthen ~r/^there should be no requests for floor (?<floor>.+)$/,
          %{floor: floor_str},
          context do
    context = trace(context)
    floor = Arguments.parse_floor(floor_str)

    floors =
      context.sweep
      |> Sweep.requests()
      |> extract_floors()

    refute floor in floors
    {:ok, context}
  end

  # Then the next stop should be X
  defthen ~r/^the next stop should be (?<floor>.+)$/, %{floor: floor_str}, context do
    context = trace(context)
    floor = Arguments.parse_floor(floor_str)
    assert_next_stop(context, floor)
  end

  # Then the next stop should be none
  defthen ~r/^the next stop should be none$/, _vars, context do
    context = trace(context)
    assert_next_stop(context, nil)
  end

  # Then the heading should be up
  defthen ~r/^the heading should be (?<heading>.+)$/, %{heading: heading_str}, context do
    context = trace(context)
    expected_heading = Arguments.parse_heading(heading_str)

    # We check what the heading BECOMES when updated from the current position
    new_sweep = Sweep.update_heading(context.sweep, context.current_floor)

    assert Sweep.heading(new_sweep) == expected_heading
    {:ok, context}
  end

  #
  # --- Helpers ---
  #

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

  defp extract_floors(requests), do: Enum.map(requests, fn {_, f} -> f end)

  defp assert_next_stop(context, expected) do
    next = Sweep.next_stop(context.sweep, context.current_floor)
    assert next == expected
    {:ok, context}
  end
end
