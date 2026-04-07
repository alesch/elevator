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

  # --- Public API ---

  @doc "Initializes a new sweep state."
  @spec new(:up | :down | :idle, [request()]) :: t()
  def new(heading \\ :idle, requests \\ []) do
    %Sweep{heading: heading, requests: requests}
  end

  @doc "Adds a request to the sweep."
  @spec add_request(t(), source(), floor()) :: t()
  def add_request(%Sweep{requests: reqs} = sweep, source, floor) do
    if {source, floor} in reqs do
      sweep
    else
      %{sweep | requests: reqs ++ [{source, floor}]}
    end
  end

  @doc "Returns the queue of requests based on current heading and position."
  @spec queue(t(), floor()) :: [request()]
  def queue(%Sweep{heading: :idle, requests: []}, _current_floor), do: []

  def queue(%Sweep{heading: :idle, requests: _requests} = sweep, current_floor) do
    # If idle but has work, we calculate the heading for the journey
    heading = calculate_heading(sweep, current_floor)
    queue(%{sweep | heading: heading}, current_floor)
  end

  def queue(%Sweep{heading: heading, requests: requests}, current_floor) do
    # The LOOK Algorithm "Story":
    # 1. We split the universe into what's "Ahead" and what's "Behind" us.
    {ahead, behind} = split_by_heading(requests, current_floor, heading)

    # 2. In the current direction, we decide which requests are immediate stops
    #    and which should be deferred (Look-Ahead logic).
    {immediate_stops, deferred} = apply_look_priorities(ahead, heading)

    # 3. We assemble the journey: Immediate stops (Ahead) -> Deferred/Reverse (Behind).
    assemble_journey(immediate_stops, behind ++ deferred, heading)
  end

  @doc "Returns the next floor to stop at."
  @spec next_stop(t(), floor()) :: floor() | nil
  def next_stop(sweep, current_floor) do
    sweep
    |> queue(current_floor)
    |> List.first()
    |> element_to_floor()
  end

  @doc "Removes all requests for the given floor."
  @spec floor_serviced(t(), floor()) :: t()
  def floor_serviced(%Sweep{requests: reqs} = sweep, floor) do
    %{sweep | requests: Enum.reject(reqs, fn {_, f} -> f == floor end)}
  end

  @doc "Updates the heading based on current floor and requests."
  @spec update_heading(t(), floor()) :: t()
  def update_heading(sweep, current_floor) do
    %{sweep | heading: calculate_heading(sweep, current_floor)}
  end

  # --- Private Functions ---

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

  defp sort_ascending(requests), do: Enum.sort_by(requests, fn {_, f} -> f end, :asc)
  defp sort_descending(requests), do: Enum.sort_by(requests, fn {_, f} -> f end, :desc)

  defp any_requests_above?(sweep, floor) do
    Enum.any?(sweep.requests, fn {_, f} -> f > floor end)
  end

  defp any_requests_below?(sweep, floor) do
    Enum.any?(sweep.requests, fn {_, f} -> f < floor end)
  end

  defp element_to_floor(nil), do: nil
  defp element_to_floor({_, f}), do: f

  defp calculate_heading(%Sweep{requests: []}, _current_floor), do: :idle

  defp calculate_heading(sweep, current_floor) do
    cond do
      any_requests_above?(sweep, current_floor) -> :up
      any_requests_below?(sweep, current_floor) -> :down
      true -> :idle
    end
  end
end
