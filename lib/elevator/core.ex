defmodule Elevator.Core do
  @moduledoc """
  The internal state of the elevator box.
  """
  alias __MODULE__, as: Core
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
            motor_speed: :normal,
            weight: 0,
            weight_limit: 1000

  @type t :: %__MODULE__{
          current_floor: integer() | :unknown,
          heading: :up | :down | :idle,
          door_status: :open | :closed | :opening | :closing,
          requests: list({atom(), integer()}),
          last_activity_at: integer(),
          status: :normal | :overload | :emergency | :rehoming,
          door_sensor: :clear | :blocked,
          motor_status: :running | :stopping | :stopped,
          weight: integer(),
          weight_limit: integer()
        }

  @doc "Creates a standard passenger elevator state."
  @spec new_passenger() :: t()
  def new_passenger, do: %Core{weight_limit: 1000}

  @doc "Creates a heavy-duty freight elevator state."
  @spec new_freight() :: t()
  def new_freight, do: %Core{weight_limit: 5000}

  # ---------------------------------------------------------------------------
  # ## Public State Transitions
  # ---------------------------------------------------------------------------

  @doc """
  Adds a floor request to the state and updates the heading.
  """
  @spec request_floor(t(), atom(), integer()) :: t()
  def request_floor(%Core{} = state, source, floor) when is_integer(floor) do
    state
    |> add_request(source, floor)
    |> update_heading()
    |> process_current_floor()
    |> apply_constraints()
  end

  @doc """
  Processes the current floor arrival logic.
  Initiates braking if this is a target floor.
  """
  @spec process_current_floor(t()) :: t()
  def process_current_floor(%Core{} = state) do
    if should_stop_at?(state, state.current_floor) do
      %{state | motor_status: :stopping}
      |> apply_constraints()
    else
      state
      |> apply_constraints()
    end
  end

  @doc """
  Central event handler for component confirmations.
  """
  @spec handle_event(t(), atom(), integer() | nil) :: t()
  def handle_event(state, :motor_stopped, _now) do
    state
    |> fulfill_current_floor_requests()
    |> confirm_stopped_at_floor()
    |> apply_constraints()
  end

  def handle_event(%Core{door_status: :opening} = state, :door_opened, now) do
    %{state | door_status: :open, last_activity_at: now}
    |> apply_constraints()
  end

  def handle_event(%Core{door_status: :closing} = state, :door_closed, _now) do
    %{state | door_status: :closed}
    |> apply_constraints()
  end

  def handle_event(state, :recovery_complete, floor) do
    %{state | current_floor: floor, status: :normal}
    |> apply_constraints()
  end

  def handle_event(state, :rehoming_started, _now) do
    %{state | status: :rehoming}
    |> apply_constraints()
  end

  def handle_event(%Core{door_status: :closing} = state, :door_obstructed, _now) do
    %{state | door_sensor: :blocked, door_status: :opening}
    |> apply_constraints()
  end

  def handle_event(state, :door_obstructed, _now) do
    %{state | door_sensor: :blocked}
    |> apply_constraints()
  end

  def handle_event(state, :door_cleared, _now) do
    %{state | door_sensor: :clear}
    |> apply_constraints()
  end

  def handle_event(state, event, _now) do
    Logger.warning("Unexpected event #{inspect(event)} in state: #{inspect(state)}")

    state
    |> apply_constraints()
  end

  @doc """
  Handles physical button presses.
  """
  @spec handle_button_press(t(), atom(), integer()) :: t()
  def handle_button_press(%Core{door_status: :closing} = state, :door_open, _now) do
    %{state | door_status: :opening}
    |> apply_constraints()
  end

  def handle_button_press(%Core{door_status: :open} = state, :door_open, now) do
    %{state | last_activity_at: now}
    |> apply_constraints()
  end

  def handle_button_press(state, button, _now) do
    Logger.warning("Unexpected button press #{inspect(button)} in state: #{inspect(state)}")
    state
  end

  @doc """
  Updates the current weight and checks for overload.
  """
  @spec update_weight(t(), integer()) :: t()
  def update_weight(%Core{} = state, new_weight) do
    state
    |> set_weight(new_weight)
    |> update_overload_status()
    |> apply_constraints()
  end

  # ---------------------------------------------------------------------------
  # ## Private Internal Logic
  # ---------------------------------------------------------------------------

  @doc "Updates the heading based on current floor and requests."
  @spec update_heading(t()) :: t()
  def update_heading(state) do
    cond do
      any_requests_above?(state) -> %{state | heading: :up}
      any_requests_below?(state) -> %{state | heading: :down}
      true -> %{state | heading: :idle}
    end
    |> apply_constraints()
  end

  @doc "Processes a floor arrival with physical safety checks (Stop/Overshoot)."
  @spec process_arrival(t(), integer()) :: t()
  def process_arrival(state, floor) do
    # 1. Update floor in state
    state = %{state | current_floor: floor}

    # 2. Check for mandatory safety stops
    if should_stop_at?(state, floor) or overshooting?(state) do
      %{state | heading: :idle}
      |> apply_constraints()
    else
      # Passing through: Maintain current heading
      state
      |> apply_constraints()
    end
  end

  @spec overshooting?(t()) :: boolean()
  defp overshooting?(state) do
    cond do
      state.heading == :up and not any_requests_above?(state) -> true
      state.heading == :down and not any_requests_below?(state) -> true
      true -> false
    end
  end

  @spec fulfill_current_floor_requests(t()) :: t()
  defp fulfill_current_floor_requests(state) do
    state
    |> Map.update!(:requests, fn reqs ->
      Enum.reject(reqs, fn {_, f} -> f == state.current_floor end)
    end)
  end

  @spec should_stop_at?(t(), integer()) :: boolean()
  defp should_stop_at?(state, floor) do
    # 1. Always stop for Car requests
    # 2. Stop for Hall requests only if capacity > 100kg
    Enum.any?(state.requests, fn
      {:car, ^floor} -> true
      {:hall, ^floor} -> remaining_capacity(state) >= 100
      _ -> false
    end)
  end

  @spec confirm_stopped_at_floor(t()) :: t()
  defp confirm_stopped_at_floor(state) do
    %{state | motor_status: :stopped, door_status: :opening}
  end

  @spec set_weight(t(), integer()) :: t()
  defp set_weight(state, weight), do: %{state | weight: weight}

  @spec update_overload_status(t()) :: t()
  defp update_overload_status(state) do
    new_status = if state.weight > state.weight_limit, do: :overload, else: :normal
    %{state | status: new_status}
  end

  @spec remaining_capacity(t()) :: integer()
  defp remaining_capacity(state), do: state.weight_limit - state.weight

  @spec any_requests_above?(t()) :: boolean()
  defp any_requests_above?(state) do
    Enum.any?(state.requests, fn {_, f} -> f > state.current_floor end)
  end

  @spec any_requests_below?(t()) :: boolean()
  defp any_requests_below?(state) do
    Enum.any?(state.requests, fn {_, f} -> f < state.current_floor end)
  end

  @spec add_request(t(), atom(), integer()) :: t()
  defp add_request(state, source, floor) do
    if {source, floor} in state.requests do
      state
    else
      %{state | requests: state.requests ++ [{source, floor}]}
    end
  end

  # ---------------------------------------------------------------------------
  # ## Autonomous Intent & Safety Pipeline
  # ---------------------------------------------------------------------------

  @spec apply_constraints(t()) :: t()
  defp apply_constraints(state) do
    state
    |> start_rehoming()
    |> start_servicing_request()
    |> complete_servicing_request()
    |> start_moving()
    |> stop_moving()
    |> enforce_safety_overrides()
    |> enforce_the_golden_rule()
  end

  defp start_rehoming(%Core{status: :rehoming} = state) do
    # During rehoming, we must ensure doors are closed and move down at slow speed.
    # We do NOT auto-complete here based on floor 1, because the sensor
    # confirmation is what actually completes rehoming.
    state = if state.door_status != :closed, do: %{state | door_status: :closing}, else: state
    %{state | heading: :down, motor_status: :running, motor_speed: :slow}
  end

  defp start_rehoming(state), do: state

  defp start_servicing_request(
         %Core{heading: h, door_status: :open, status: :normal, door_sensor: :clear} = state
       )
       when h != :idle do
    %{state | door_status: :closing}
  end

  defp start_servicing_request(state), do: state

  defp start_moving(
         %Core{heading: h, door_status: :closed, motor_status: :stopped, status: :normal} = state
       )
       when h != :idle do
    %{state | motor_status: :running, motor_speed: :normal}
  end

  defp start_moving(state), do: state

  defp stop_moving(%Core{heading: :idle, motor_status: :running} = state) do
    %{state | motor_status: :stopping}
  end

  defp stop_moving(state), do: state

  defp complete_servicing_request(
         %Core{heading: :idle, motor_status: :stopped, door_status: d} = state
       )
       when d in [:closed, :closing] do
    # If we are idle at a floor that still needs service (or just got a request), open up.
    if should_stop_at?(state, state.current_floor) do
      %{state | door_status: :opening}
    else
      state
    end
  end

  defp complete_servicing_request(state), do: state

  defp enforce_safety_overrides(state) do
    cond do
      state.door_sensor == :blocked ->
        # Obstruction forces opening
        %{state | door_status: :opening}

      state.status == :overload ->
        # Overload forces opening/prevents closing.
        # If already open, stay open.
        if state.door_status == :open do
          state
        else
          %{state | door_status: :opening}
        end

      true ->
        state
    end
  end

  defp enforce_the_golden_rule(state) do
    # "The Golden Rule": Motor stays stopped unless doors are closed.
    if state.door_status != :closed and state.motor_status == :running do
      %{state | motor_status: :stopped}
    else
      state
    end
  end
end
