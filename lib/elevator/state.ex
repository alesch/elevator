defmodule Elevator.State do
  @moduledoc """
  The internal state of the elevator box.
  """
  defstruct [
    current_floor: 1,
    heading: :idle,
    door_status: :closed,
    requests: [],
    last_activity_at: 0,
    status: :normal,
    door_sensor: :clear,
    motor_status: :stopped,
    weight: 0,
    weight_limit: 1000
  ]

  @doc """
  Adds a floor request to the state with a specific source (:hall or :car).
  """
  def request_floor(%__MODULE__{} = state, source, floor) when is_integer(floor) do
    state = add_request(state, source, floor)
    update_heading(state)
  end

  @doc """
  Processes the current floor arrival.
  Initiates the braking sequence only if we should stop at this floor.
  """
  def process_current_floor(%__MODULE__{} = state) do
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
  def handle_event(%__MODULE__{motor_status: :stopping} = state, :motor_stopped) do
    # Remove BOTH car and hall requests for this floor upon arrival
    new_requests = Enum.reject(state.requests, fn {_, f} -> f == state.current_floor end)
    
    %{state | 
      motor_status: :stopped, 
      door_status: :opening,
      requests: new_requests
    }
  end

  def handle_event(%__MODULE__{door_status: :opening} = state, :door_open_done) do
    %{state | door_status: :open, last_activity_at: system_time()}
  end

  def handle_event(state, _event), do: state

  # Mockable system time for tests
  defp system_time, do: 0

  @doc """
  Handles physical button presses (e.g., from the box panel).
  """
  def handle_button_press(%__MODULE__{door_status: :closing} = state, :door_open) do
    %{state | door_status: :opening}
  end

  # Default: No change for unknown buttons or states
  def handle_button_press(%__MODULE__{} = state, _button), do: state

  @doc """
  Updates the current weight in the box.
  If weight exceeds weight_limit, sets status to :overload.
  """
  def update_weight(%__MODULE__{} = state, new_weight) do
    new_status = if new_weight > state.weight_limit, do: :overload, else: :normal
    %{state | weight: new_weight, status: new_status}
  end

  defp add_request(state, source, floor) do
    if {source, floor} in state.requests do
      state
    else
      %{state | requests: state.requests ++ [{source, floor}]}
    end
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

  defp has_requests_ahead?(%{heading: :up} = state), do: Enum.any?(state.requests, fn {_, f} -> f > state.current_floor end)
  defp has_requests_ahead?(%{heading: :down} = state), do: Enum.any?(state.requests, fn {_, f} -> f < state.current_floor end)
  defp has_requests_ahead?(_), do: false

  defp has_requests_behind?(%{heading: :up} = state), do: Enum.any?(state.requests, fn {_, f} -> f < state.current_floor end)
  defp has_requests_behind?(%{heading: :down} = state), do: Enum.any?(state.requests, fn {_, f} -> f > state.current_floor end)
  defp has_requests_behind?(%{heading: :idle} = state), do: Enum.any?(state.requests, fn {_, _} -> true end)

  defp reverse_heading(:up), do: :down
  defp reverse_heading(:down), do: :up
  defp reverse_heading(:idle), do: :up # Or logic to pick best start
end
