defmodule Elevator.Sweep do
  @moduledoc """
  Pure functional calculator for the **LOOK algorithm** (elevator sweep).

  The LOOK algorithm is an optimized version of the SCAN (elevator) algorithm:
  - It maintains a `heading` (:up or :down) as long as there are requests "ahead".
  - It reverses direction ONLY when it "looks" ahead and finds no further requests in that direction.
  - Car requests are prioritized on the way, while Hall requests may be deferred to the return journey.
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

  @doc "Returns the ordered queue of requests based on current heading and position."
  @spec ordered_queue(t(), floor()) :: [request()]
  def ordered_queue(%Sweep{heading: :idle, requests: reqs}, _current_floor), do: reqs

  def ordered_queue(%Sweep{heading: heading, requests: requests}, current_floor) do
    # The LOOK Algorithm "Story":
    # 1. We split the universe into what's "Ahead" and what's "Behind" us.
    {ahead, behind} = split_by_proximity(requests, current_floor, heading)

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
    |> ordered_queue(current_floor)
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
  def update_heading(%Sweep{requests: []} = sweep, _current_floor) do
    %{sweep | heading: :idle}
  end

  def update_heading(sweep, current_floor) do
    cond do
      any_requests_above?(sweep, current_floor) -> %{sweep | heading: :up}
      any_requests_below?(sweep, current_floor) -> %{sweep | heading: :down}
      true -> %{sweep | heading: :idle}
    end
  end

  #
  #  --- Private functions ---
  #

  # --- LOOK Algorithm Implementation ---
  #
  # 1. Look-Ahead Logic:
  #    The elevator "looks ahead" along its current heading. If it sees a
  #    request, it keeps going. However, to be efficient, it only stops
  #    for Hall requests if they are at the "peak" (the furthest point)
  #    of the current sweep. Car requests are ALWAYS stops.
  #
  # 2. Directional Asymmetry (Project Specific):
  #    As per our business rules [R-MOVE-LOOK], hall requests are deferred
  #    on UP journeys (unless they are the peak), but are picked up
  #    normally on DOWN journeys.
  #
  # 3. The Return Journey:
  #    Anything "behind" us or "deferred" gets moved to the end of the
  #    queue and is sorted in the reverse direction, forming the next sweep.

  defp split_by_proximity(requests, current_floor, :up) do
    Enum.split_with(requests, fn {_, f} -> f >= current_floor end)
  end

  defp split_by_proximity(requests, current_floor, :down) do
    Enum.split_with(requests, fn {_, f} -> f <= current_floor end)
  end

  defp apply_look_priorities(ahead, :up) do
    # On UP journeys: Defer hall requests that aren't the peak.
    peak_floor = ahead |> Enum.map(fn {_, f} -> f end) |> Enum.max(fn -> nil end)

    Enum.split_with(ahead, fn
      {:car, _} -> true
      {:hall, f} -> f == peak_floor
    end)
  end

  defp apply_look_priorities(ahead, :down) do
    # On DOWN journeys: Pick up everything on the way (Asymmetric rule).
    {ahead, []}
  end

  defp assemble_journey(immediate, return_journey, heading) do
    sort_by_heading(immediate, heading) ++ sort_reverse_heading(return_journey, heading)
  end

  defp sort_by_heading(requests, :up), do: Enum.sort_by(requests, fn {_, f} -> f end, :asc)
  defp sort_by_heading(requests, :down), do: Enum.sort_by(requests, fn {_, f} -> f end, :desc)

  defp sort_reverse_heading(requests, :up), do: Enum.sort_by(requests, fn {_, f} -> f end, :desc)
  defp sort_reverse_heading(requests, :down), do: Enum.sort_by(requests, fn {_, f} -> f end, :asc)

  defp any_requests_above?(sweep, floor) do
    Enum.any?(sweep.requests, fn {_, f} -> f > floor end)
  end

  defp any_requests_below?(sweep, floor) do
    Enum.any?(sweep.requests, fn {_, f} -> f < floor end)
  end

  defp element_to_floor(nil), do: nil
  defp element_to_floor({_, f}), do: f
end
