defmodule Elevator.State do
  @moduledoc """
  The internal state of the elevator box.
  """
  alias __MODULE__, as: State
  require Logger

  # ---------------------------------------------------------------------------
  # ## Data Structure & Initialization
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # ## Public State Transitions
  # ---------------------------------------------------------------------------

  @doc """
  Adds a floor request to the state and updates the heading.
  """
  @spec request_floor(t(), atom(), integer()) :: t()
  def request_floor(%State{} = state, source, floor) when is_integer(floor) do
    state
    |> add_request(source, floor)
    |> update_heading()
  end

  @doc """
  Processes the current floor arrival logic.
  Initiates braking if this is a target floor.
  """
  @spec process_current_floor(t()) :: t()
  def process_current_floor(%State{} = state) do
    if should_stop_at?(state, state.current_floor) do
      %{state | motor_status: :stopping}
    else
      state
    end
  end

  @doc """
  Central event handler for component confirmations.
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
  Handles physical button presses.
  """
  @spec handle_button_press(t(), atom(), integer()) :: t()
  def handle_button_press(%State{door_status: :closing} = state, :door_open, _now) do
    %{state | door_status: :opening}
  end

  def handle_button_press(%State{door_status: :open} = state, :door_open, now) do
    %{state | last_activity_at: now}
  end

  def handle_button_press(state, button, _now) do
    Logger.warning("Unexpected button press #{inspect(button)} in state: #{inspect(state)}")
    state
  end

  @doc """
  Updates the current weight and checks for overload.
  """
  @spec update_weight(t(), integer()) :: t()
  def update_weight(%State{} = state, new_weight) do
    state
    |> set_weight(new_weight)
    |> update_overload_status()
  end

  # ---------------------------------------------------------------------------
  # ## Private Internal Logic
  # ---------------------------------------------------------------------------

  defp update_heading(state) do
    cond do
      any_requests_above?(state) -> %{state | heading: :up}
      any_requests_below?(state) -> %{state | heading: :down}
      true -> %{state | heading: :idle}
    end
  end

  defp fulfill_current_floor_requests(state) do
    state
    |> Map.update!(:requests, fn reqs ->
      Enum.reject(reqs, fn {_, f} -> f == state.current_floor end)
    end)
  end

  defp should_stop_at?(state, floor) do
    # 1. Always stop for Car requests
    # 2. Stop for Hall requests only if capacity > 100kg
    Enum.any?(state.requests, fn
      {:car, ^floor} -> true
      {:hall, ^floor} -> remaining_capacity(state) > 100
      _ -> false
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

  defp any_requests_above?(state) do
    Enum.any?(state.requests, fn {_, f} -> f > state.current_floor end)
  end

  defp any_requests_below?(state) do
    Enum.any?(state.requests, fn {_, f} -> f < state.current_floor end)
  end

  defp add_request(state, source, floor) do
    if {source, floor} in state.requests do
      state
    else
      %{state | requests: state.requests ++ [{source, floor}]}
    end
  end
end
