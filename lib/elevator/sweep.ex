defmodule Elevator.Sweep do
  @moduledoc """
  Pure functional calculator for the **LOOK algorithm** (elevator sweep).

  The LOOK algorithm is an optimized version of the SCAN (elevator) algorithm:
  - It maintains a `heading` (:up or :down) as long as there are requests "ahead".
  - It reverses direction ONLY when it "looks" ahead and finds no further requests in that direction.
  - Car requests are prioritized on the way, while Hall requests may be deferred to the return journey.

  ## Algorithm Deep Dive

  1. **Look-Ahead Logic**:
     The elevator "looks ahead" along its current heading. If it sees a request, it keeps going. However, to be efficient, it only stops for Hall requests if they are at the "peak" (the furthest point) of the current sweep. Car requests are ALWAYS stops.

  2. **Directional Asymmetry**:
     As per our business rules [R-MOVE-LOOK], hall requests are deferred on UP journeys (unless they are the peak), but are picked up normally on DOWN journeys to maximize throughput.

  3. **The Return Journey**:
     Anything "behind" us or "deferred" gets moved to the end of the queue and is sorted in the reverse direction, forming the next sweep.
  """
  alias __MODULE__, as: Sweep

  defstruct heading: :idle, requests: []

  # --- Types ---

  @type source :: :car | :hall
  @type floor :: integer()
  @type request :: {source(), floor()}
  @type t :: %Sweep{
          heading: :up | :down | :idle,
          requests: [request()]
        }

  #
  # --- Public API ---
  #

  @doc "Initializes a new sweep state."
  @spec new([request()]) :: t()
  def new(requests \\ []) do
    %Sweep{requests: requests}
  end

  @doc "Returns the sweep heading."
  def heading(%Sweep{heading: h}), do: h

  @doc "Returns the requests list."
  def requests(%Sweep{requests: r}), do: r

  def queue(sweep) do
    sweep.requests |> Enum.map(&element_to_floor/1)
  end

  @doc "Adds a request to the sweep."
  @spec add_request(t(), source(), floor(), floor() | :unknown) :: t()
  def add_request(sweep, source, floor, current_floor) do
    sweep
    |> do_add_request(source, floor)
    |> update_heading(current_floor)
  end

  @doc "Returns the next floor to stop at."
  @spec next_stop(t()) :: floor() | nil
  def next_stop(sweep) do
    sweep
    |> requests()
    |> List.first()
    |> element_to_floor()
  end

  @doc "Removes all requests for the given floor and updates heading."
  @spec floor_serviced(t(), floor()) :: t()
  def floor_serviced(sweep, floor) do
    sweep
    |> do_remove_floor(floor)
    |> update_heading(floor)
  end

  #
  # --- Private Functions ---
  #

  @spec update_heading(t(), floor() | :unknown) :: t()
  defp update_heading(sweep, current_floor) do
    %{sweep | heading: do_update_heading(sweep, current_floor)}
  end

  defp calculate_look_queue(requests, current_floor, heading) do
    # The LOOK Algorithm "Story":
    # 1. We split the universe into what's "Ahead" and what's "Behind" us.
    {ahead, behind} = split_by_heading(requests, current_floor, heading)

    # 2. In the current direction, we decide which requests are immediate stops
    #    and which should be deferred (Look-Ahead logic).
    {immediate_stops, deferred} = apply_look_priorities(ahead, heading)

    # 3. We assemble the journey: Immediate stops (Ahead) -> Deferred/Reverse (Behind).
    assemble_journey(immediate_stops, behind ++ deferred, heading)
  end

  defp split_by_heading(requests, current_floor, :up) do
    Enum.split_with(requests, fn {_, f} -> f >= current_floor end)
  end

  defp split_by_heading(requests, current_floor, :down) do
    Enum.split_with(requests, fn {_, f} -> f <= current_floor end)
  end

  # Example:
  #   If `ahead` is `[{:hall, 3}, {:car, 5}, {:hall, 5}]` and heading is :up:
  #   1. `peak_floor` becomes 5.
  #   2. `split_with` groups `{:car, 5}` and `{:hall, 5}` as immediate stops.
  #   3. `{:hall, 3}` is deferred into the second list of the tuple.
  #   Result: `{[{:car, 5}, {:hall, 5}], [{:hall, 3}]}`
  defp apply_look_priorities(ahead, :up) do
    # On UP journeys: Defer hall requests that aren't the peak.
    peak_floor =
      ahead
      # transforms [{:car, 5}, {:hall, 3}] into [5, 3]
      |> Enum.map(fn {_, f} -> f end)
      # finds the highest floor number (5)
      |> Enum.max(fn -> nil end)

    Enum.split_with(ahead, fn
      {:car, _} -> true
      {:hall, f} -> f == peak_floor
    end)
  end

  defp apply_look_priorities(ahead, :down) do
    # On DOWN journeys: Pick up everything on the way (Asymmetric rule).
    {ahead, []}
  end

  defp assemble_journey(immediate, return_journey, :up) do
    sort_ascending(immediate) ++ sort_descending(return_journey)
  end

  defp assemble_journey(immediate, return_journey, :down) do
    sort_descending(immediate) ++ sort_ascending(return_journey)
  end

  defp do_add_request(sweep, source, floor) do
    %{sweep | requests: sweep.requests ++ [{source, floor}]}
  end

  defp do_remove_floor(sweep, floor) do
    %{sweep | requests: Enum.reject(sweep.requests, fn {_, f} -> f == floor end)}
  end

  defp sort_ascending(requests), do: Enum.sort_by(requests, fn {_, f} -> f end, :asc)
  defp sort_descending(requests), do: Enum.sort_by(requests, fn {_, f} -> f end, :desc)

  defp sort_by_heading(requests, :up), do: sort_ascending(requests)
  defp sort_by_heading(requests, :down), do: sort_descending(requests)
  defp sort_by_heading(requests, :idle), do: requests

  defp any_requests_above?(_sweep, :unknown), do: false

  defp any_requests_above?(sweep, floor) do
    Enum.any?(sweep.requests, fn {_, f} -> f > floor end)
  end

  defp any_requests_below?(sweep, :unknown), do: any_requests?(sweep)

  defp any_requests_below?(sweep, floor) do
    Enum.any?(sweep.requests, fn {_, f} -> f < floor end)
  end

  defp any_requests?(%Sweep{requests: reqs}), do: reqs != []

  defp element_to_floor(nil), do: nil
  defp element_to_floor({_, f}), do: f

  defp do_update_heading(%Sweep{requests: []}, _current_floor), do: :idle

  defp do_update_heading(sweep, current_floor) do
    cond do
      any_requests_above?(sweep, current_floor) -> :up
      any_requests_below?(sweep, current_floor) -> :down
      true -> :idle
    end
  end
end
