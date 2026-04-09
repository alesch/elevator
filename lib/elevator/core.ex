defmodule Elevator.Core do
  @moduledoc """
  The internal state of the elevator box.
  Uses a declarative Pulse Architecture for state transitions.
  """
  alias __MODULE__, as: Core
  require Logger

  # ---------------------------------------------------------------------------
  # ## Data Structure & Initialization
  # ---------------------------------------------------------------------------

  @door_wait_ms 5000
  @base_floor 0

  defstruct current_floor: :unknown,
            sweep: %Elevator.Sweep{},
            door_status: :closed,
            door_command: nil,
            last_activity_at: 0,
            phase: :booting,
            door_sensor: :clear,
            motor_status: :stopped

  @type direction :: :up | :down | :idle
  @type startup_payload :: %{vault: integer() | nil, sensor: integer() | nil}
  @type event_payload :: integer() | startup_payload() | nil

  @type action ::
          {:set_timer, atom(), integer()}
          | {:cancel_timer, atom()}
          | {:move, direction()}
          | {:crawl, direction()}
          | {:stop_motor}
          | {:open_door}
          | {:close_door}
          | {:persist_arrival, integer()}

  @type t :: %__MODULE__{
          current_floor: integer() | :unknown,
          sweep: Elevator.Sweep.t(),
          door_status: :open | :closed | :opening | :closing | :obstructed,
          door_command: :open | :close | nil,
          last_activity_at: integer(),
          phase: :booting | :rehoming | :moving | :arriving | :docked | :leaving | :idle,
          door_sensor: :clear | :blocked,
          motor_status: :running | :crawling | :stopping | :stopped
        }

  # ---------------------------------------------------------------------------
  # ## State Factories (Public API)
  # ---------------------------------------------------------------------------

  @doc "Factory: Returns a fresh Elevator struct."
  @spec init() :: t()
  def init, do: %Core{}

  @doc """
  Factory: Returns an elevator idle at the given floor.
  Bypasses rehoming by simulating a successful recovery.
  """
  @spec idle_at(integer()) :: t()
  def idle_at(floor) do
    init()
    |> handle_event(:recovery_complete, floor)
    |> elem(0)
  end

  @doc "Factory: Returns an elevator docked (door open) at the given floor."
  @spec docked_at(integer()) :: t()
  def docked_at(floor) do
    idle_at(floor)
    |> request_floor(:car, floor)
    |> elem(0)
    |> handle_event(:door_opened)
    |> elem(0)
  end

  @doc "Factory: Returns an elevator moving between two floors."
  @spec moving_to(integer(), integer()) :: t()
  def moving_to(from, to) do
    idle_at(from)
    |> request_floor(:car, to)
    |> elem(0)
  end

  # ---------------------------------------------------------------------------
  # ## Status Accessors (Public)
  # ---------------------------------------------------------------------------

  @doc "Returns the current request queue via the LOOK algorithm."
  @spec requests(t()) :: [Elevator.Sweep.request()]
  def requests(%Core{sweep: s, current_floor: f}), do: Elevator.Sweep.queue(s, f)

  @doc "Returns the current heading based on Phase or Sweep logic."
  @spec heading(t()) :: direction()
  def heading(%Core{phase: :booting}), do: :idle
  def heading(%Core{phase: :rehoming, current_floor: :unknown}), do: :down
  def heading(%Core{sweep: s}), do: Elevator.Sweep.heading(s)

  @doc "Returns the current operational phase."
  @spec phase(t()) :: atom()
  def phase(%Core{phase: p}), do: p

  @doc "Returns the physical door status."
  @spec door_status(t()) :: atom()
  def door_status(%Core{door_status: d}), do: d

  @doc "Returns the physical motor status."
  @spec motor_status(t()) :: atom()
  def motor_status(%Core{motor_status: m}), do: m

  @doc "Returns the confirmed current floor."
  @spec current_floor(t()) :: integer() | :unknown
  def current_floor(%Core{current_floor: f}), do: f

  @doc "Returns the next immediate stop according to LOOK."
  @spec next_stop(t()) :: integer() | nil
  def next_stop(%Core{sweep: s, current_floor: f}), do: Elevator.Sweep.next_stop(s, f)

  # ---------------------------------------------------------------------------
  # ## Public API (Entry Points)
  # ---------------------------------------------------------------------------

  @doc "Adds a floor request and triggers a transit pulse."
  @spec request_floor(t(), atom(), integer()) :: {t(), [action()]}
  def request_floor(%Core{phase: phase} = state, _source, _floor)
      when phase in [:booting, :rehoming],
      do: {state, []}

  def request_floor(%Core{} = state, source, floor) when is_integer(floor) do
    state
    |> add_sweep_request(source, floor)
    |> update_sweep_heading()
    |> pulse()
  end

  @doc "Processes physical arrival at a floor and triggers a transit pulse."
  @spec process_arrival(t(), integer()) :: {t(), [action()]}
  def process_arrival(%Core{} = state, floor) do
    new_state =
      state
      |> Map.put(:current_floor, floor)
      |> transit()
      |> enforce_the_golden_rule()

    {new_state, derive_actions(state, new_state)}
  end

  @doc "Handles physical button presses and triggers a transit pulse."
  @spec handle_button_press(t(), atom(), integer()) :: {t(), [action()]}
  def handle_button_press(%Core{phase: phase} = state, _button, _now)
      when phase in [:booting, :rehoming],
      do: {state, []}

  def handle_button_press(state, button, now) do
    state
    |> do_ingest_button(button, now)
    |> pulse()
  end

  @doc "Central event handler for component confirmations and triggers a transit pulse."
  @spec handle_event(t(), atom(), event_payload()) :: {t(), [action()]}
  def handle_event(state, event, payload \\ nil) do
    state
    |> do_ingest_event(event, payload)
    |> pulse()
  end

  # ---------------------------------------------------------------------------
  # ## The Engine (Pulse)
  # ---------------------------------------------------------------------------

  @doc "Internal pulse implementation (Transition + Action Derivation)."
  @spec pulse(t()) :: {t(), [action()]}
  def pulse(state) do
    new_state = state |> transit() |> enforce_the_golden_rule()
    {new_state, derive_actions(state, new_state)}
  end

  # ---------------------------------------------------------------------------
  # ## Rules (The Brain)
  # ---------------------------------------------------------------------------

  defp transit(%Core{} = state) do
    state |> do_transit()
  end

  # Rule: Transition from Booting to Idle via Recovery
  defp do_transit(%Core{phase: :booting} = state), do: state

  # Rule: Transition from Rehoming to Arriving (Braking)
  defp do_transit(%Core{phase: :rehoming, current_floor: floor, motor_status: m} = state)
       when is_integer(floor) and m in [:running, :crawling] do
    %{state | motor_status: :stopping}
  end

  defp do_transit(
         %Core{phase: :rehoming, motor_status: :stopped, current_floor: :unknown} = state
       ) do
    %{state | motor_status: :crawling}
  end

  defp do_transit(%Core{phase: :rehoming, current_floor: floor, motor_status: :stopped} = state)
       when is_integer(floor) do
    %{state | phase: :idle}
  end

  # Rule: Transition from Moving to Arriving (Braking)
  defp do_transit(%Core{phase: :moving} = state) do
    if state.current_floor == next_stop(state) do
      %{state | motor_status: :stopping, phase: :arriving}
    else
      state
    end
  end

  # Rule: Gateway Reversal -> Transition to arriving AND opening doors
  defp do_transit(%Core{phase: :leaving, door_status: :obstructed} = state) do
    %{state | phase: :arriving, door_status: :opening}
  end

  # [R-MOVE-WAKEUP]: Wakeup: Completely Idle (No Requests)
  defp do_transit(%Core{phase: :idle} = state) do
    do_idle_transit(state, heading(state), next_stop(state))
  end

  # Rule: Gateway Reversal -> Manual Door Open Command
  defp do_transit(%Core{phase: :leaving, door_command: :open} = state) do
    %{state | phase: :arriving, door_status: :opening, door_command: nil}
  end

  # Rule: Transition door to closing when leaving
  defp do_transit(%Core{phase: :leaving, door_status: :open} = state) do
    %{state | door_status: :closing}
  end

  # Rule: Gateway Exit -> Transition to :docked when doors are open
  defp do_transit(%Core{phase: :arriving, door_status: :open} = state) do
    %{state | phase: :docked}
  end

  # Rule: Door Command Close (Timeout or Button) -> Transition to leaving
  defp do_transit(%Core{phase: :docked, door_command: :close} = state) do
    %{state | phase: :leaving, door_status: :closing, door_command: nil}
  end

  # Rule: Gateway Settle -> Initiate door opening once motor stops
  defp do_transit(%Core{phase: :arriving, motor_status: :stopped} = state) do
    if state.door_status in [:closed, :obstructed] do
      state
      |> floor_serviced()
      |> Map.put(:door_status, :opening)
    else
      # Stable: Doors are already :opening or :open (waiting for hardware)
      state
    end
  end

  # Rule: Settlement from Leaving
  defp do_transit(%Core{phase: :leaving, door_status: :closed} = state) do
    state = update_sweep_heading(state)

    if heading(state) == :idle do
      %{state | phase: :idle, motor_status: :stopped}
    else
      %{state | phase: :moving, motor_status: :running}
    end
  end

  # Default: Stable
  defp do_transit(state), do: state

  defp do_idle_transit(%Core{door_command: :open} = state, :idle, _next) do
    state
    |> Map.put(:phase, :arriving)
    |> Map.put(:door_status, :opening)
    |> Map.put(:door_command, nil)
    |> floor_serviced()
  end

  defp do_idle_transit(state, _heading, next) when next == state.current_floor do
    state
    |> Map.put(:phase, :arriving)
    |> Map.put(:door_status, :opening)
    |> floor_serviced()
  end

  defp do_idle_transit(state, :idle, _next), do: state

  defp do_idle_transit(state, _heading, _next) do
    %{state | phase: :moving, motor_status: :running}
  end

  # ---------------------------------------------------------------------------
  # ## Data Ingestion Helpers
  # ---------------------------------------------------------------------------

  defp do_ingest_event(state, :startup_check, %{vault: v, sensor: s}) do
    if warm_start?(v, s) do
      # CASE 1: Perfect agreement (Zero-move recovery)
      %{state | phase: :idle, current_floor: v}
    else
      # CASE 2: Ambiguity or Cold Start (Perform physical homing)
      do_ingest_event(state, :rehoming_started, nil)
    end
  end

  defp do_ingest_event(state, :recovery_complete, floor) do
    %{state | phase: :idle, current_floor: floor}
  end

  defp do_ingest_event(state, :rehoming_started, _) do
    %{state | phase: :rehoming}
  end

  defp do_ingest_event(state, :motor_stopped, _), do: %{state | motor_status: :stopped}

  defp do_ingest_event(state, :door_opened, now),
    do: %{state | door_status: :open, last_activity_at: now}

  defp do_ingest_event(state, :door_closed, _), do: %{state | door_status: :closed}

  defp do_ingest_event(state, :door_obstructed, _),
    do: %{state | door_status: :obstructed, door_sensor: :blocked}

  defp do_ingest_event(state, :door_cleared, _), do: %{state | door_sensor: :clear}

  defp do_ingest_event(%Core{phase: :idle} = state, :inactivity_timeout, _) do
    if state.current_floor != @base_floor do
      state
      |> add_sweep_request(:car, @base_floor)
      |> update_sweep_heading()
    else
      state
    end
  end

  defp do_ingest_event(%Core{phase: :docked} = state, :door_timeout, _) do
    %{state | door_command: :close}
  end

  defp do_ingest_event(state, _, _), do: state

  defp do_ingest_button(%Core{phase: :docked} = state, :door_open, now) do
    %{state | last_activity_at: now}
  end

  defp do_ingest_button(%Core{phase: :idle} = state, :door_open, _now) do
    %{state | door_command: :open}
  end

  defp do_ingest_button(%Core{phase: :leaving} = state, :door_open, _now) do
    %{state | door_command: :open}
  end

  defp do_ingest_button(state, :door_open, _now), do: state

  defp do_ingest_button(%Core{} = state, :door_close, _now) do
    %{state | door_command: :close}
  end

  defp do_ingest_button(state, _, _), do: state

  # ---------------------------------------------------------------------------
  # ## Calculation Helpers
  # ---------------------------------------------------------------------------

  defp add_sweep_request(state, source, floor) do
    Map.update!(state, :sweep, &Elevator.Sweep.add_request(&1, source, floor))
  end

  defp update_sweep_heading(state) do
    Map.update!(state, :sweep, &Elevator.Sweep.update_heading(&1, state.current_floor))
  end

  defp floor_serviced(state) do
    Map.update!(state, :sweep, &Elevator.Sweep.floor_serviced(&1, state.current_floor))
  end

  # ---------------------------------------------------------------------------
  # ## Action Derivation & Safety
  # ---------------------------------------------------------------------------

  defp derive_actions(old, new) do
    []
    |> update_motor_action(old, new)
    |> update_door_action(old, new)
    |> update_timer_action(old, new)
    |> update_persistence_action(old, new)
  end

  defp update_persistence_action(actions, old, new) do
    if has_arrived?(old, new) do
      actions ++ [{:persist_arrival, new.current_floor}]
    else
      actions
    end
  end

  defp update_motor_action(actions, old, new) do
    cond do
      # Case: Crossing the arrival threshold (Moving -> Stopping)
      braking?(old, new) ->
        actions ++ [{:stop_motor}]

      # Case: Start moving or change direction
      # Note: The state machine ensures a stop occurs before heading reversals.
      is_running?(new) and intent_changed?(old, new) ->
        actions ++ [{:move, heading(new)}]

      # Case: Start crawling or change direction (rehoming)
      is_crawling?(new) and intent_changed?(old, new) ->
        actions ++ [{:crawl, heading(new)}]

      true ->
        actions
    end
  end

  defp update_door_action(actions, old, new) do
    cond do
      door_opening_requested?(old, new) ->
        actions ++ [{:open_door}]

      door_closing_requested?(old, new) ->
        actions ++ [{:close_door}]

      true ->
        actions
    end
  end

  defp update_timer_action(actions, old, new) do
    cond do
      should_reset_timer?(old, new) ->
        actions ++ [{:set_timer, :door_timeout, @door_wait_ms}]

      should_cancel_timer?(old, new) ->
        actions ++ [{:cancel_timer, :door_timeout}]

      true ->
        actions
    end
  end

  defp enforce_the_golden_rule(state) do
    if state.door_status != :closed and state.motor_status != :stopped do
      Logger.warning(
        "The Golden Rule: Motor forced stopped. Phase: #{state.phase}, door: #{state.door_status}"
      )

      %{state | motor_status: :stopped}
    else
      state
    end
  end

  # ---------------------------------------------------------------------------
  # ## Semantic Helpers
  # ---------------------------------------------------------------------------

  # --- Door Helpers ---

  defp door_opening_requested?(old, new), do: is_opening?(new) and not is_opening?(old)
  defp door_closing_requested?(old, new), do: is_closing?(new) and not is_closing?(old)

  defp is_opening?(state), do: state.door_status in [:opening, :obstructed]
  defp is_closing?(state), do: state.door_status == :closing
  defp is_open?(state), do: state.door_status == :open

  # --- Timer Helpers ---

  defp should_reset_timer?(old, new) do
    is_open?(new) and (not is_open?(old) or activity_changed?(old, new))
  end

  defp should_cancel_timer?(old, new), do: not is_open?(new) and is_open?(old)
  defp activity_changed?(old, new), do: old.last_activity_at != new.last_activity_at

  # --- Motor Helpers ---

  defp braking?(old, new), do: is_stopping?(new) and is_moving?(old)

  defp intent_changed?(old, new) do
    motor_status_changed?(old, new) or heading_changed?(old, new)
  end

  defp is_moving?(state), do: state.motor_status in [:running, :crawling]
  defp is_stopping?(state), do: state.motor_status in [:stopping, :stopped]
  defp is_running?(state), do: state.motor_status == :running
  defp is_crawling?(state), do: state.motor_status == :crawling

  defp motor_status_changed?(old, new), do: old.motor_status != new.motor_status
  defp heading_changed?(old, new), do: heading(old) != heading(new)
  defp floor_changed?(old, new), do: old.current_floor != new.current_floor

  defp has_arrived?(old, new), do: floor_changed?(old, new) and known_position?(new.current_floor)

  # --- Startup Helpers ---

  defp warm_start?(v, s), do: v == s and known_position?(v)

  defp known_position?(nil), do: false
  defp known_position?(:unknown), do: false
  defp known_position?(_), do: true
end
