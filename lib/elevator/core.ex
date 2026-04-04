defmodule Elevator.Core do
  @moduledoc """
  The internal state of the elevator box.
  """
  alias __MODULE__, as: Core
  require Logger

  # ---------------------------------------------------------------------------
  # ## Data Structure & Initialization
  # ---------------------------------------------------------------------------

  defstruct current_floor: 0,
            heading: :idle,
            door_status: :closed,
            requests: [],
            last_activity_at: 0,
            phase: :idle,
            door_sensor: :clear,
            motor_status: :stopped,
            motor_speed: :normal

  @type action ::
          {:set_timer, atom(), integer()}
          | {:cancel_timer, atom()}
          | {:move_motor, atom(), atom()}
          | {:stop_motor}
          | {:open_door}
          | {:close_door}

  @type t :: %__MODULE__{
          current_floor: integer() | :unknown,
          heading: :up | :down | :idle,
          door_status: :open | :closed | :opening | :closing,
          requests: list({atom(), integer()}),
          last_activity_at: integer(),
          phase: :rehoming | :moving | :arriving | :docked | :leaving | :idle,
          door_sensor: :clear | :blocked,
          motor_status: :running | :stopping | :stopped
        }

  @door_wait_ms 5000

  @doc "Creates a standard passenger elevator state."
  @spec new_passenger() :: t()
  def new_passenger, do: %Core{}

  # ---------------------------------------------------------------------------
  # ## Public State Transitions
  # ---------------------------------------------------------------------------

  @doc """
  Adds a floor request to the state and updates the heading.
  """
  @spec request_floor(t(), atom(), integer()) :: {t(), [action()]}
  # Scenario 8.1 (different floor) / Scenario 4.6 (same floor)
  # Only fires when doors are confirmed closed — prevents motor start with open doors.
  def request_floor(%Core{phase: :idle, door_status: :closed} = state, source, floor)
      when is_integer(floor) do
    state = add_request(state, source, floor)

    new_state =
      if floor == state.current_floor do
        # Same floor — open door immediately, no motor cycle needed (Scenario 4.6)
        state
        |> fulfill_current_floor_requests()
        |> update_heading()
        |> Map.merge(%{door_status: :opening, phase: :arriving})
      else
        # Different floor — start moving (Scenario 8.1)
        state
        |> update_heading()
        |> Map.merge(%{phase: :moving, motor_status: :running, motor_speed: :normal})
      end

    {new_state, derive_actions(state, new_state)}
  end

  def request_floor(%Core{} = state, source, floor) when is_integer(floor) do
    new_state =
      state
      |> add_request(source, floor)
      |> update_heading()
      |> do_process_current_floor()

    {new_state, derive_actions(state, new_state)}
  end

  defp do_process_current_floor(state) do
    if should_stop_at?(state, state.current_floor) do
      if state.motor_status == :stopped do
        # Motor already stopped — skip the :stopping protocol entirely.
        # Sending a redundant stop to hardware causes a deadlock (no :motor_stopped reply).
        state
        |> fulfill_current_floor_requests()
        |> confirm_stopped_at_floor()
        |> apply_logic()
      else
        %{state | motor_status: :stopping}
        |> apply_logic()
      end
    else
      state
      |> apply_logic()
    end
  end

  @doc """
  Processes the current floor arrival logic.
  Initiates braking if this is a target floor.
  """
  @spec process_current_floor(t()) :: {t(), [action()]}
  def process_current_floor(%Core{} = state) do
    new_state = do_process_current_floor(state)
    {new_state, derive_actions(state, new_state)}
  end

  @doc """
  Central event handler for component confirmations.
  """
  @spec handle_event(t(), atom(), integer() | nil) :: {t(), [action()]}
  def handle_event(state, event, now) do
    new_state = do_handle_event(state, event, now)
    {new_state, derive_actions(state, new_state)}
  end

  # Scenario 5.6: Rehoming complete — go idle, NO door cycle.
  defp do_handle_event(%Core{phase: :rehoming} = state, :motor_stopped, _now) do
    %{state | motor_status: :stopped, phase: :idle, heading: :idle}
  end

  defp do_handle_event(state, :motor_stopped, _now) do
    state
    |> fulfill_current_floor_requests()
    |> confirm_stopped_at_floor()
    |> apply_logic()
  end

  defp do_handle_event(%Core{door_status: :opening} = state, :door_opened, now) do
    %{state | door_status: :open, last_activity_at: now}
    |> apply_logic(now)
  end

  defp do_handle_event(%Core{door_status: :closing} = state, :door_closed, _now) do
    %{state | door_status: :closed}
    |> apply_logic()
  end

  defp do_handle_event(%Core{door_status: :open} = state, :door_timeout, _now) do
    if state.phase != :rehoming and state.door_sensor == :clear do
      %{state | door_status: :closing}
      |> apply_logic()
    else
      state
      |> apply_logic()
    end
  end

  defp do_handle_event(state, :tick, now) do
    state
    |> apply_logic(now)
  end

  defp do_handle_event(state, :recovery_complete, floor) do
    %{state | current_floor: floor, phase: :idle}
    |> apply_logic()
  end

  defp do_handle_event(state, :rehoming_started, _now) do
    %{state | phase: :rehoming}
    |> apply_logic()
  end

  defp do_handle_event(%Core{door_status: :closing} = state, :door_obstructed, _now) do
    %{state | door_sensor: :blocked, door_status: :opening}
    |> apply_logic()
  end

  defp do_handle_event(state, :door_obstructed, _now) do
    %{state | door_sensor: :blocked}
    |> apply_logic()
  end

  defp do_handle_event(state, :door_cleared, _now) do
    %{state | door_sensor: :clear}
    |> apply_logic()
  end

  defp do_handle_event(state, event, _now) do
    Logger.warning("Unexpected event #{inspect(event)} in state: #{inspect(state)}")

    state
    |> apply_logic()
  end

  @doc """
  Handles physical button presses.
  """
  @spec handle_button_press(t(), atom(), integer()) :: {t(), [action()]}
  def handle_button_press(state, button, now) do
    new_state = do_handle_button_press(state, button, now)
    actions = derive_actions(state, new_state)

    # Some button presses might cause unique side effects (like timer cancellation)
    actions =
      case button do
        :door_close -> actions ++ [{:cancel_timer, :door_timeout}]
        _ -> actions
      end

    {new_state, actions}
  end

  defp do_handle_button_press(%Core{door_status: :closed} = state, :door_open, _now) do
    %{state | door_status: :opening}
    |> apply_logic()
  end

  defp do_handle_button_press(%Core{door_status: :closing} = state, :door_open, _now) do
    %{state | door_status: :opening}
    |> apply_logic()
  end

  defp do_handle_button_press(%Core{door_status: :open} = state, :door_open, now) do
    %{state | last_activity_at: now}
    |> apply_logic(now)
  end

  defp do_handle_button_press(%Core{door_status: :open} = state, :door_close, _now) do
    %{state | door_status: :closing}
    |> apply_logic()
  end

  defp do_handle_button_press(state, button, _now) do
    Logger.warning("Unexpected button press #{inspect(button)} in state: #{inspect(state)}")
    state
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
  end

  @doc "Processes a floor arrival with physical safety checks (Stop/Overshoot)."
  @spec process_arrival(t(), integer()) :: {t(), [action()]}
  # Scenario 5.4: Homing arrival — brake and anchor. Phase stays :rehoming until :motor_stopped.
  def process_arrival(%Core{phase: :rehoming} = state, floor) do
    new_state = %{state | current_floor: floor, motor_status: :stopping}
    {new_state, derive_actions(state, new_state)}
  end

  def process_arrival(state, floor) do
    new_state =
      %{state | current_floor: floor}
      |> do_process_arrival(floor)

    {new_state, derive_actions(state, new_state)}
  end

  defp do_process_arrival(state, floor) do
    if should_stop_at?(state, floor) or overshooting?(state) do
      %{state | heading: :idle}
      |> apply_logic()
    else
      state
      |> apply_logic()
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
    Enum.any?(state.requests, fn
      {:car, ^floor} -> true
      {:hall, ^floor} -> true
      _ -> false
    end)
  end

  @spec confirm_stopped_at_floor(t()) :: t()
  defp confirm_stopped_at_floor(state) do
    %{state | motor_status: :stopped, door_status: :opening}
  end

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

  @spec apply_logic(t(), integer() | nil) :: t()
  defp apply_logic(state, now \\ nil) do
    state
    |> start_rehoming_logic()
    |> start_servicing_request_logic(now)
    |> complete_servicing_request_logic()
    |> start_moving_logic()
    |> stop_moving_logic()
    |> enforce_safety_overrides()
    |> enforce_the_golden_rule()
  end

  defp start_rehoming_logic(%Core{phase: :rehoming} = state) do
    state = if state.door_status != :closed, do: %{state | door_status: :closing}, else: state
    %{state | heading: :down, motor_status: :running, motor_speed: :slow}
  end

  defp start_rehoming_logic(state), do: state

  defp start_servicing_request_logic(
         %Core{heading: h, door_status: :open, door_sensor: :clear} = state,
         now
       )
       when h != :idle and not is_nil(now) do
    if now - state.last_activity_at >= @door_wait_ms do
      %{state | door_status: :closing}
    else
      state
    end
  end

  defp start_servicing_request_logic(state, _now), do: state

  defp start_moving_logic(
         %Core{heading: h, door_status: :closed, motor_status: :stopped} = state
       )
       when h != :idle do
    %{state | motor_status: :running, motor_speed: :normal}
  end

  defp start_moving_logic(state), do: state

  defp stop_moving_logic(%Core{heading: :idle, motor_status: :running} = state) do
    %{state | motor_status: :stopping}
  end

  defp stop_moving_logic(state), do: state

  defp complete_servicing_request_logic(%Core{motor_status: :stopped, door_status: d} = state)
       when d in [:closed, :closing] do
    # If we are stopped at a floor that still needs service, open up.
    if should_stop_at?(state, state.current_floor) do
      %{state | door_status: :opening}
    else
      state
    end
  end

  defp complete_servicing_request_logic(state), do: state

  defp derive_actions(old, new) do
    []
    |> maybe_add_motor_action(old, new)
    |> maybe_add_door_action(old, new)
    |> maybe_add_timer_action(old, new)
  end

  defp maybe_add_motor_action(actions, old, new) do
    cond do
      new.motor_status == :stopping and old.motor_status != :stopping ->
        actions ++ [{:stop_motor}]

      new.motor_status == :running and
          (old.motor_status != :running or old.heading != new.heading) ->
        actions ++ [{:move_motor, new.heading, new.motor_speed}]

      true ->
        actions
    end
  end

  defp maybe_add_door_action(actions, old, new) do
    cond do
      new.door_status == :opening and old.door_status != :opening ->
        actions ++ [{:open_door}]

      new.door_status == :closing and old.door_status != :closing ->
        actions ++ [{:close_door}]

      true ->
        actions
    end
  end

  defp maybe_add_timer_action(actions, old, new) do
    cond do
      new.door_status == :open and
          (old.door_status != :open or old.last_activity_at != new.last_activity_at) ->
        actions ++ [{:set_timer, :door_timeout, @door_wait_ms}]

      new.door_status != :open and old.door_status == :open ->
        actions ++ [{:cancel_timer, :door_timeout}]

      true ->
        actions
    end
  end

  defp enforce_safety_overrides(state) do
    if state.door_sensor == :blocked do
      %{state | door_status: :opening}
    else
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
