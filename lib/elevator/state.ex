defmodule Elevator.State do
  @moduledoc """
  The internal state of the elevator box.
  """
  alias __MODULE__, as: State
  require Logger

  defstruct current_floor: 1,
            heading: :idle,
            door_status: :closed,
            requests: [],
            last_activity_at: 0,
            status: :normal,
            door_sensor: :clear,
            motor_status: :stopped,
            weight: 0,
            weight_limit: 1000

  @type t :: %__MODULE__{
          current_floor: integer(),
          heading: :up | :down | :idle,
          door_status: :open | :closed | :opening | :closing,
          requests: list({atom(), integer()}),
          last_activity_at: integer(),
          status: :normal | :overload | :emergency,
          door_sensor: :clear | :blocked,
          motor_status: :running | :stopping | :stopped,
          weight: integer(),
          weight_limit: integer()
        }

  @doc "Creates a standard passenger elevator state."
  @spec new_passenger() :: t()
  def new_passenger, do: %State{weight_limit: 1000}

  @doc "Creates a heavy-duty freight elevator state."
  @spec new_freight() :: t()
  def new_freight, do: %State{weight_limit: 5000}

  @doc """
  Adds a floor request to the state with a specific source (:hall or :car).
  """
  @spec request_floor(t(), atom(), integer()) :: t()
  def request_floor(%State{} = state, source, floor) when is_integer(floor) do
    state
    |> add_request(source, floor)
    |> update_heading()
  end

  @doc """
  Processes the current floor arrival.
  Initiates the braking sequence only if we should stop at this floor.
  """
  @spec process_current_floor(t()) :: t()
  def process_current_floor(%State{} = state) do
    if should_stop_at?(state, state.current_floor) do
      %{state | motor_status: :stopping}
    else
      state
    end
  end

  defp should_stop_at?(state, floor) do
    # 1. Always stop for Car requests (internal)
    # 2. Stop for Hall requests (external) only if we have capacity
    Enum.any?(state.requests, fn
      {:car, ^floor} -> true
      {:hall, ^floor} -> remaining_capacity(state) > 100
      _ -> false
    end)
  end

  @doc """
  Central event handler for physical component confirmations.
  """
  @spec handle_event(t(), atom(), integer() | nil) :: t()
  def handle_event(%State{motor_status: :stopping} = state, :motor_stopped, _now) do
    state
    |> fulfill_current_floor_requests()
    |> confirm_stopped_at_floor()
  end

  def handle_event(%State{door_status: :opening} = state, :door_open_done, now) do
    %{state | door_status: :open, last_activity_at: now}
  end

  def handle_event(state, event, _now) do
    Logger.warning("Unexpected event #{inspect(event)} in state: #{inspect(state)}")
    state
  end

  @doc """
  Handles physical button presses (e.g., from the box panel).
  """
  @spec handle_button_press(t(), atom(), integer()) :: t()
  def handle_button_press(%State{door_status: :closing} = state, :door_open, _now) do
    %{state | door_status: :opening}
  end

  def handle_button_press(%State{door_status: :open} = state, :door_open, now) do
    %{state | last_activity_at: now}
  end

  # Default: No change for unknown buttons or states
  def handle_button_press(state, button, _now) do
    Logger.warning("Unexpected button press #{inspect(button)} in state: #{inspect(state)}")
    state
  end

  @doc """
  Updates the current weight in the box.
  If weight exceeds weight_limit, sets status to :overload.
  """
  @spec update_weight(t(), integer()) :: t()
  def update_weight(%State{} = state, new_weight) do
    state
    |> set_weight(new_weight)
    |> update_overload_status()
  end

  defp add_request(state, source, floor) do
    if {source, floor} in state.requests do
      state
    else
      %{state | requests: state.requests ++ [{source, floor}]}
    end
  end

  defp fulfill_current_floor_requests(state) do
    state
    |> Map.update!(:requests, fn reqs ->
      Enum.reject(reqs, fn {_, f} -> f == state.current_floor end)
    end)
  end

  defp confirm_stopped_at_floor(state) do
    %{state | motor_status: :stopped, door_status: :opening}
  end

  defp set_weight(state, weight), do: %{state | weight: weight}

  defp update_overload_status(state) do
    new_status = if state.weight > state.weight_limit, do: :overload, else: :normal
    %{state | status: new_status}
  end

  defp remaining_capacity(state), do: state.weight_limit - state.weight

  defp update_heading(state) do
    cond do
      # 1. Keep Heading: If there are requests ahead of us in the current direction
      has_requests_ahead?(state) ->
        state

      # 2. Reverse: If no requests ahead, but requests exist in opposite direction
      has_requests_behind?(state) ->
        %{state | heading: reverse_heading(state.heading)}

      # 3. Retire: No requests anywhere
      true ->
        %{state | heading: :idle}
    end
  end

  defp has_requests_ahead?(%{heading: :up} = state),
    do: Enum.any?(state.requests, fn {_, f} -> f > state.current_floor end)

  defp has_requests_ahead?(%{heading: :down} = state),
    do: Enum.any?(state.requests, fn {_, f} -> f < state.current_floor end)

  defp has_requests_ahead?(_), do: false

  defp has_requests_behind?(%{heading: :up} = state),
    do: Enum.any?(state.requests, fn {_, f} -> f < state.current_floor end)

  defp has_requests_behind?(%{heading: :down} = state),
    do: Enum.any?(state.requests, fn {_, f} -> f > state.current_floor end)

  defp has_requests_behind?(%{heading: :idle} = state),
    do: Enum.any?(state.requests, fn {_, _} -> true end)

  defp reverse_heading(:up), do: :down
  defp reverse_heading(:down), do: :up
  # Or logic to pick best start
  defp reverse_heading(:idle), do: :up
end
