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

  @type source :: :car | :hall
  @type floor :: integer()
  @type request :: {source(), floor()}
  @type t :: %Sweep{
          heading: :up | :down | :idle,
          requests: [request()]
        }

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
  def ordered_queue(%Sweep{heading: :up, requests: reqs}, current_floor) do
    # Divide into ahead and behind
    {ahead, behind} = Enum.split_with(reqs, fn {_, f} -> f >= current_floor end)
    
    # In ahead: hall requests are only picked up if they are the "peak"
    # (nothing strictly above them)
    max_floor = Enum.max_by(ahead, fn {_, f} -> f end, fn -> nil end) |> element_to_floor()
    
    {stops, deferred} = Enum.split_with(ahead, fn
      {:car, _} -> true
      {:hall, f} -> f == max_floor
    end)

    Enum.sort_by(stops, fn {_, f} -> f end, :asc) ++ 
    Enum.sort_by(behind ++ deferred, fn {_, f} -> f end, :desc)
  end

  def ordered_queue(%Sweep{heading: :down, requests: reqs}, current_floor) do
    {ahead, behind} = Enum.split_with(reqs, fn {_, f} -> f <= current_floor end)
    
    # In LOOK, we pick up all hall requests on the way DOWN
    # but only car requests or the peak hall request on the way UP.
    # Actually, let's keep the asymmetry if that's the goal.
    # For now, following the specific rule: hall requests on :down always stop.
    Enum.sort_by(ahead, fn {_, f} -> f end, :desc) ++ 
    Enum.sort_by(behind, fn {_, f} -> f end, :asc)
  end

  def ordered_queue(%Sweep{requests: reqs}, _current_floor), do: reqs

  @doc "Determines if the elevator should stop at the given floor."
  @spec should_stop?(t(), floor(), floor()) :: boolean()
  def should_stop?(sweep, floor, _current_floor) do
    has_car_request? = Enum.any?(sweep.requests, &(&1 == {:car, floor}))
    has_hall_request? = Enum.any?(sweep.requests, &(&1 == {:hall, floor}))

    cond do
      has_car_request? -> true
      sweep.heading == :down and has_hall_request? -> true
      # Pick up a hall request going UP ONLY if there is nothing strictly above us to sweep
      sweep.heading == :up and has_hall_request? and not any_requests_above?(sweep, floor) -> true
      sweep.heading == :idle and has_hall_request? -> true
      true -> false
    end
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

  # Helper to check for requests above a floor
  defp any_requests_above?(sweep, floor) do
    Enum.any?(sweep.requests, fn {_, f} -> f > floor end)
  end

  # Helper to check for requests below a floor
  defp any_requests_below?(sweep, floor) do
    Enum.any?(sweep.requests, fn {_, f} -> f < floor end)
  end

  defp element_to_floor(nil), do: nil
  defp element_to_floor({_, f}), do: f
end
