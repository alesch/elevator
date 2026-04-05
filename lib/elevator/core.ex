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
            motor_status: :stopped

  @type action ::
          {:set_timer, atom(), integer()}
          | {:cancel_timer, atom()}
          | {:move, atom()}
          | {:crawl, atom()}
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
          motor_status: :running | :crawling | :stopping | :stopped
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
        |> Map.merge(%{phase: :moving, motor_status: :running})
      end

    {enforce_the_golden_rule(new_state), derive_actions(state, new_state)}
  end

  def request_floor(%Core{} = state, source, floor) when is_integer(floor) do
    new_state =
      state
      |> add_request(source, floor)
      |> update_heading()
      |> do_process_current_floor()
      |> enforce_the_golden_rule()

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
      else
        %{state | motor_status: :stopping}
      end
    else
      state
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
    new_state = state |> do_handle_event(event, now) |> enforce_the_golden_rule()
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
  end

  # Scenario 8.3: Doors confirm open while arriving — transition to :docked.
  defp do_handle_event(%Core{phase: :arriving} = state, :door_opened, now) do
    %{state | door_status: :open, phase: :docked, last_activity_at: now}
  end

  defp do_handle_event(%Core{door_status: :opening} = state, :door_opened, now) do
    %{state | door_status: :open, last_activity_at: now}
  end

  # Scenario 8.5 / 8.6: Door closed after leaving — go to :moving or :idle.
  defp do_handle_event(%Core{phase: :leaving} = state, :door_closed, _now) do
    state = %{state | door_status: :closed}

    if state.heading != :idle do
      %{state | phase: :moving, motor_status: :running}
    else
      %{state | phase: :idle}
    end
  end

  defp do_handle_event(%Core{door_status: :closing} = state, :door_closed, _now) do
    %{state | door_status: :closed}
  end

  # Scenario 8.4: Timeout fires while docked — begin leaving.
  defp do_handle_event(%Core{phase: :docked, door_sensor: :clear} = state, :door_timeout, _now) do
    %{state | door_status: :closing, phase: :leaving}
  end

  defp do_handle_event(%Core{door_status: :open} = state, :door_timeout, _now) do
    if state.phase != :rehoming and state.door_sensor == :clear do
      %{state | door_status: :closing}
    else
      state
    end
  end

  defp do_handle_event(state, :recovery_complete, floor) do
    %{state | current_floor: floor, phase: :idle}
  end

  defp do_handle_event(state, :rehoming_started, _now) do
    %{state | phase: :rehoming, heading: :down, motor_status: :crawling}
  end

  # Scenario 8.7: Obstruction while leaving — revert to :docked, re-open door.
  defp do_handle_event(%Core{phase: :leaving} = state, :door_obstructed, _now) do
    %{state | door_sensor: :blocked, door_status: :opening, phase: :docked}
  end

  defp do_handle_event(%Core{door_status: :closing} = state, :door_obstructed, _now) do
    %{state | door_sensor: :blocked, door_status: :opening}
  end

  defp do_handle_event(state, :door_obstructed, _now) do
    %{state | door_sensor: :blocked}
  end

  defp do_handle_event(state, :door_cleared, _now) do
    %{state | door_sensor: :clear}
  end

  defp do_handle_event(
         %Core{phase: :idle, current_floor: floor} = state,
         :inactivity_timeout,
         _now
       )
       when floor != 0 do
    {new_state, _} = request_floor(state, :car, 0)
    new_state
  end

  defp do_handle_event(state, event, _now) do
    Logger.warning("Unexpected event #{inspect(event)} in state: #{inspect(state)}")
    state
  end

  @doc """
  Handles physical button presses.
  """
  @spec handle_button_press(t(), atom(), integer()) :: {t(), [action()]}
  def handle_button_press(state, button, now) do
    new_state = state |> do_handle_button_press(button, now) |> enforce_the_golden_rule()
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
  end

  defp do_handle_button_press(%Core{door_status: :closing} = state, :door_open, _now) do
    %{state | door_status: :opening}
  end

  defp do_handle_button_press(%Core{door_status: :open} = state, :door_open, now) do
    %{state | last_activity_at: now}
  end

  defp do_handle_button_press(%Core{door_status: :open} = state, :door_close, _now) do
    %{state | door_status: :closing}
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
    {enforce_the_golden_rule(new_state), derive_actions(state, new_state)}
  end

  # Scenario 8.2: Arriving at target floor while moving — begin braking, transition to :arriving.
  def process_arrival(%Core{phase: :moving} = state, floor) do
    new_state = %{state | current_floor: floor}

    new_state =
      if should_stop_at?(new_state, floor) or overshooting?(new_state) do
        %{new_state | motor_status: :stopping, phase: :arriving}
      else
        new_state
      end

    {enforce_the_golden_rule(new_state), derive_actions(state, new_state)}
  end

  def process_arrival(state, floor) do
    new_state =
      %{state | current_floor: floor}
      |> do_process_arrival(floor)
      |> enforce_the_golden_rule()

    {new_state, derive_actions(state, new_state)}
  end

  defp do_process_arrival(state, floor) do
    if should_stop_at?(state, floor) or overshooting?(state) do
      %{state | heading: :idle}
    else
      state
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
  # ## Action Derivation & Safety
  # ---------------------------------------------------------------------------

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
        actions ++ [{:move, new.heading}]

      new.motor_status == :crawling and
          (old.motor_status != :crawling or old.heading != new.heading) ->
        actions ++ [{:crawl, new.heading}]

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

  defp enforce_the_golden_rule(state) do
    # "The Golden Rule": Motor stays stopped unless doors are closed.
    # This should never fire in normal operation — if it does, a phase handler has a bug.
    if state.door_status != :closed and state.motor_status == :running do
      Logger.warning(
        "Golden Rule fired — motor forced stopped. Phase: #{state.phase}, door: #{state.door_status}"
      )

      %{state | motor_status: :stopped}
    else
      state
    end
  end
end
