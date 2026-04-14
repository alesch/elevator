defmodule Elevator.Core do
  @moduledoc """
  The internal state of the elevator box.
  Uses a pure FICS Architecture (Reality, Transient Signals, Logic Meaning).
  """
  alias __MODULE__, as: Core
  require Logger

  # ---------------------------------------------------------------------------
  # ## Data Structure & Initialization
  # ---------------------------------------------------------------------------

  @door_wait_ms 5000
  @inactivity_wait_ms 300_000
  @base_floor 0

  defstruct hardware: %{
              door_status: :closed,
              motor_status: :stopped,
              door_sensor: :clear,
              current_floor: :unknown
            },
            signal: nil,
            logic: %{
              phase: :booting,
              sweep: %Elevator.Sweep{},
              last_activity_at: 0
            }

  @type phase :: :booting | :idle | :moving | :arriving | :opening | :docked | :closing | :leaving | :rehoming
  @type door_status :: :closed | :opening | :open | :closing | :obstructed
  @type motor_status :: :stopped | :running | :stopping | :crawling

  @type direction :: :up | :down | :idle
  @type startup_payload :: %{vault: integer() | nil, sensor: integer() | nil}
  @type event_payload :: integer() | startup_payload() | nil
  @type floor :: integer()
  @type request :: {:car | :hall, floor}

  @type action ::
          {:set_timer, atom(), integer()}
          | {:cancel_timer, atom()}
          | {:move, direction()}
          | {:crawl, direction()}
          | {:stop_motor}
          | {:open_door}
          | {:close_door}
          | {:persist_arrival, integer()}

  @type t :: %__MODULE__{}

  # ---------------------------------------------------------------------------
  # ## Status Accessors (Public)
  # ---------------------------------------------------------------------------

  @spec phase(t()) :: phase()
  def phase(%Core{logic: %{phase: p}}), do: p

  @spec door_status(t()) :: door_status()
  def door_status(%Core{hardware: %{door_status: d}}), do: d

  @spec motor_status(t()) :: motor_status()
  def motor_status(%Core{hardware: %{motor_status: m}}), do: m

  @spec current_floor(t()) :: integer() | :unknown
  def current_floor(%Core{hardware: %{current_floor: f}}), do: f

  @doc "Ordered list of the floor queue."
  @spec queue(t()) :: [floor()]
  def queue(%Core{} = state),
    do: Elevator.Sweep.queue(state.logic.sweep, state.hardware.current_floor)

  @spec heading(t()) :: direction()
  def heading(%Core{logic: %{sweep: s}}), do: Elevator.Sweep.heading(s)

  @spec next_stop(t()) :: integer() | nil
  def next_stop(%Core{} = state) do
    Elevator.Sweep.next_stop(state.logic.sweep, state.hardware.current_floor)
  end

  # ---------------------------------------------------------------------------
  # ## State Factories (Public API)
  # ---------------------------------------------------------------------------

  @doc "Factory: Returns a fresh Elevator struct in :booting phase."
  @spec booting() :: t()
  def booting, do: %Core{}

  @deprecated "Use booting/0 instead"
  def init, do: booting()

  @doc """
  Factory: Returns an elevator in :rehoming phase.
  Drives from booting() via a mismatched :startup_check.
  """
  @spec rehoming() :: t()
  def rehoming do
    booting()
    |> handle_event(:startup_check, %{vault: nil, sensor: nil})
    |> elem(0)
    # Simulate hardware confirming the {:crawl, :down} action
    |> handle_event(:motor_crawling)
    |> elem(0)
  end

  @doc """
  Factory: Returns an elevator idle at the given floor.
  Zero-movement rehoming.
  """
  @spec idle_at(integer()) :: t()
  def idle_at(floor) do
    booting()
    |> handle_event(:startup_check, %{vault: floor, sensor: floor})
    |> elem(0)
  end

  @doc "Factory: Returns an elevator docked (door open) at the given floor."
  @spec docked_at(integer()) :: t()
  def docked_at(floor) do
    idle_at(floor)
    |> request_floor({:car, floor})
    |> elem(0)
    |> handle_event(:door_opened)
    |> elem(0)
  end

  @doc "Factory: Returns an elevator moving between two floors."
  @spec moving_to(integer(), integer()) :: t()
  def moving_to(from, to) do
    idle_at(from)
    |> request_floor({:car, to})
    |> elem(0)
    |> handle_event(:motor_running)
    |> elem(0)
  end

  # ---------------------------------------------------------------------------
  # ## Public API (Entry Points)
  # ---------------------------------------------------------------------------

  @spec request_floor(t(), request()) :: {t(), [action()]}
  def request_floor(%Core{logic: %{phase: phase}} = state, _request)
      when phase in [:booting, :rehoming],
      do: {state, []}

  def request_floor(%Core{} = state, {source, floor} = request) when is_integer(floor) do
    state
    |> Map.put(:signal, {:request, request})
    |> pulse()
  end

  @spec process_arrival(t(), integer()) :: {t(), [action()]}
  def process_arrival(%Core{} = state, floor) do
    state
    |> handle_event(:floor_arrival, floor)
  end

  @spec handle_button_press(t(), atom(), integer()) :: {t(), [action()]}
  def handle_button_press(%Core{logic: %{phase: phase}} = state, _button, _now)
      when phase in [:booting, :rehoming],
      do: {state, []}

  def handle_button_press(state, button, now) do
    state
    |> do_ingest_button(button, now)
    |> pulse()
  end

  @spec handle_event(t(), atom(), event_payload()) :: {t(), [action()]}
  def handle_event(state, event, payload \\ nil) do
    state
    |> do_ingest_event(event, payload)
    |> pulse()
  end

  # ---------------------------------------------------------------------------
  # ## The Engine (Pulse)
  # ---------------------------------------------------------------------------

  @spec pulse(t()) :: {t(), [action()]}
  def pulse(baseline) do
    reality_updated = ingest_signals(baseline)
    transitions_applied = reality_updated |> transit()

    actions = derive_actions(baseline, transitions_applied)

    final_state = %{transitions_applied | signal: nil}
    {final_state, actions}
  end

  @spec ingest_signals(t()) :: t()
  defp ingest_signals(%Core{signal: {:request, {source, floor}}} = state) do
    state
    |> add_sweep_request(source, floor)
  end

  defp ingest_signals(%Core{signal: :inactivity_timeout} = state) do
    if current_floor(state) != @base_floor do
      state
      |> add_sweep_request(:car, @base_floor)
    else
      state
    end
  end

  defp ingest_signals(state), do: state

  # ---------------------------------------------------------------------------
  # ## Hardware Ingestion Layer
  # ---------------------------------------------------------------------------

  # Hardware Ingestion
  @spec do_ingest_event(t(), atom(), event_payload()) :: t()
  defp do_ingest_event(state, :startup_check, %{vault: v, sensor: s}) do
    if warm_start?(v, s) do
      state
      |> put_in([Access.key(:hardware), :current_floor], v)
      |> Map.put(:signal, :recovery_complete)
    else
      state
      |> Map.put(:signal, :rehoming_started)
    end
  end

  defp do_ingest_event(state, :floor_arrival, floor),
    do: put_in(state.hardware.current_floor, floor)

  defp do_ingest_event(state, :motor_stopped, _),
    do: put_in(state.hardware.motor_status, :stopped)

  defp do_ingest_event(state, :motor_running, _),
    do: put_in(state.hardware.motor_status, :running)

  defp do_ingest_event(state, :motor_crawling, _),
    do: put_in(state.hardware.motor_status, :crawling)

  defp do_ingest_event(state, :door_opened, now) do
    state
    |> put_in([Access.key(:hardware), :door_status], :open)
    |> put_in([Access.key(:logic), :last_activity_at], now)
  end

  defp do_ingest_event(state, :door_closed, _), do: put_in(state.hardware.door_status, :closed)

  defp do_ingest_event(state, :door_opening, _), do: put_in(state.hardware.door_status, :opening)

  defp do_ingest_event(state, :door_closing, _), do: put_in(state.hardware.door_status, :closing)

  defp do_ingest_event(state, :door_obstructed, _) do
    state
    |> put_in([Access.key(:hardware), :door_status], :obstructed)
    |> put_in([Access.key(:hardware), :door_sensor], :blocked)
  end

  defp do_ingest_event(state, :door_cleared, _), do: put_in(state.hardware.door_sensor, :clear)

  defp do_ingest_event(%Core{logic: %{phase: :idle}} = state, :inactivity_timeout, _) do
    %{state | signal: :inactivity_timeout}
  end

  defp do_ingest_event(%Core{logic: %{phase: :docked}} = state, :door_timeout, _) do
    %{state | signal: :door_timeout}
  end

  defp do_ingest_event(state, _, _), do: state

  # Buttons
  @spec do_ingest_button(t(), atom(), integer()) :: t()
  defp do_ingest_button(%Core{logic: %{phase: :docked}} = state, :door_open, now) do
    state
    |> put_in([Access.key(:logic), :last_activity_at], now)
    |> Map.put(:signal, :door_open)
  end

  defp do_ingest_button(%Core{logic: %{phase: phase}} = state, :door_open, _now)
       when phase in [:idle, :leaving] do
    Map.put(state, :signal, :door_open)
  end

  defp do_ingest_button(state, :door_open, _now), do: state

  defp do_ingest_button(%Core{} = state, :door_close, _now) do
    Map.put(state, :signal, :door_close)
  end

  defp do_ingest_button(state, _, _), do: state

  # ---------------------------------------------------------------------------
  # ## Logical Transit Rules
  # ---------------------------------------------------------------------------

  @spec transit(t()) :: t()
  defp transit(%Core{} = state), do: do_transit(state)

  @spec do_transit(t()) :: t()
  # Booting
  defp do_transit(%Core{logic: %{phase: :booting}, signal: :recovery_complete} = state) do
    put_in(state.logic.phase, :idle)
  end

  defp do_transit(%Core{logic: %{phase: :booting}, signal: :rehoming_started} = state) do
    state
    |> put_in([Access.key(:logic), :phase], :rehoming)
    |> add_sweep_request(:car, 0)
  end

  # Rehoming -> Arriving
  defp do_transit(%Core{logic: %{phase: :rehoming}, hardware: %{current_floor: floor}} = state)
       when is_integer(floor) do
    put_in(state.logic.phase, :arriving)
  end

  # Idle -> Opening or Leaving
  defp do_transit(%Core{logic: %{phase: :idle}, signal: sig} = state) do
    nxt = next_stop(state)
    has_work = not is_nil(nxt)

    cond do
      has_work and nxt == current_floor(state) ->
        state |> put_in([Access.key(:logic), :phase], :opening) |> floor_serviced()

      has_work ->
        put_in(state.logic.phase, :leaving)

      sig == :door_open ->
        state |> put_in([Access.key(:logic), :phase], :opening) |> floor_serviced()

      true ->
        state
    end
  end

  # Moving -> Arriving
  defp do_transit(%Core{logic: %{phase: :moving}} = state) do
    if current_floor(state) == next_stop(state) do
      put_in(state.logic.phase, :arriving)
    else
      state
    end
  end

  # Arriving -> Opening
  defp do_transit(%Core{logic: %{phase: :arriving}, hardware: %{motor_status: :stopped}} = state) do
    put_in(state.logic.phase, :opening)
  end

  # Opening -> Docked
  defp do_transit(%Core{logic: %{phase: :opening}, hardware: %{door_status: :open}} = state) do
    state
    |> put_in([Access.key(:logic), :phase], :docked)
  end

  # Docked -> Closing
  defp do_transit(%Core{logic: %{phase: :docked}, signal: sig} = state)
       when sig in [:door_timeout, :door_close] do
    put_in(state.logic.phase, :closing)
  end

  # Closing -> Opening (Obstruction)
  defp do_transit(%Core{logic: %{phase: :closing}, hardware: %{door_sensor: :blocked}} = state) do
    put_in(state.logic.phase, :opening)
  end

  # Closing -> Settle (Idle or Leaving)
  defp do_transit(%Core{logic: %{phase: :closing}, hardware: %{door_status: :closed}} = state) do
    if heading(state) == :idle do
      put_in(state.logic.phase, :idle)
    else
      put_in(state.logic.phase, :leaving)
    end
  end

  # Leaving -> Moving
  defp do_transit(%Core{logic: %{phase: :leaving}, hardware: %{motor_status: status}} = state)
       when status in [:running, :crawling] do
    put_in(state.logic.phase, :moving)
  end

  # Default
  defp do_transit(state), do: state

  # ---------------------------------------------------------------------------
  # ## Calculation Helpers
  # ---------------------------------------------------------------------------

  @spec add_sweep_request(t(), Elevator.Sweep.source(), integer()) :: t()
  defp add_sweep_request(state, source, floor) do
    f = current_floor(state)

    Map.update!(state, :logic, fn logic ->
      Map.update!(logic, :sweep, &Elevator.Sweep.add_request(&1, source, floor, f))
    end)
  end

  @spec floor_serviced(t()) :: t()
  defp floor_serviced(state) do
    f = current_floor(state)

    Map.update!(state, :logic, fn logic ->
      Map.update!(logic, :sweep, &Elevator.Sweep.floor_serviced(&1, f))
    end)
  end

  @spec warm_start?(integer() | :unknown, integer() | :unknown) :: boolean()
  defp warm_start?(v, s), do: v == s and is_integer(v)

  # ---------------------------------------------------------------------------
  # ## Action Derivation
  # ---------------------------------------------------------------------------

  @spec derive_actions(t(), t()) :: [action()]
  defp derive_actions(baseline, transitions_applied) do
    []
    |> update_motor_action(baseline, transitions_applied)
    |> update_door_action(baseline, transitions_applied)
    |> update_timer_action(baseline, transitions_applied)
    |> update_persistence_action(baseline, transitions_applied)
    |> verify_golden_rule(transitions_applied)
  end

  @spec update_persistence_action([action()], t(), t()) :: [action()]
  defp update_persistence_action(actions, baseline, transitions_applied) do
    if floor_reached?(baseline, transitions_applied) do
      actions ++ [{:persist_arrival, transitions_applied.hardware.current_floor}]
    else
      actions
    end
  end

  @spec update_motor_action([action()], t(), t()) :: [action()]
  defp update_motor_action(actions, baseline, transitions_applied) do
    entered_arriving = phase_entered?(baseline, transitions_applied, :arriving)
    entered_leaving = phase_entered?(baseline, transitions_applied, :leaving)
    entered_rehoming = phase_entered?(baseline, transitions_applied, :rehoming)

    cond do
      entered_arriving and transitions_applied.hardware.motor_status != :stopped ->
        actions ++ [{:stop_motor}]

      entered_rehoming ->
        actions ++ [{:crawl, heading(transitions_applied)}]

      entered_leaving ->
        # [R-MOVE-LOOK] Heading should already be set by transit logic calling next_stop
        actions ++ [{:move, heading(transitions_applied)}]

      true ->
        actions
    end
  end

  @spec update_door_action([action()], t(), t()) :: [action()]
  defp update_door_action(actions, baseline, transitions_applied) do
    new_ready_open = phase_entered?(baseline, transitions_applied, :opening)
    new_ready_close = phase_entered?(baseline, transitions_applied, :closing)

    cond do
      new_ready_open and transitions_applied.hardware.door_status != :open ->
        actions ++ [{:open_door}]

      new_ready_close and transitions_applied.hardware.door_status != :closed ->
        actions ++ [{:close_door}]

      true ->
        actions
    end
  end

  @spec update_timer_action([action()], t(), t()) :: [action()]
  defp update_timer_action(actions, baseline, transitions_applied) do
    entered_docked = phase_entered?(baseline, transitions_applied, :docked)
    left_docked = phase_left?(baseline, transitions_applied, :docked)

    entered_idle = phase_entered?(baseline, transitions_applied, :idle)
    left_idle = phase_left?(baseline, transitions_applied, :idle)

    new_activity_at = transitions_applied.logic.last_activity_at
    old_activity_at = baseline.logic.last_activity_at

    docked_activity =
      transitions_applied.logic.phase == :docked and new_activity_at != old_activity_at

    cond do
      entered_docked or docked_activity ->
        actions ++ [{:set_timer, :door_timeout, @door_wait_ms}]

      left_docked ->
        actions ++ [{:cancel_timer, :door_timeout}]

      entered_idle ->
        actions ++ [{:set_timer, :inactivity_timeout, @inactivity_wait_ms}]

      left_idle ->
        actions ++ [{:cancel_timer, :inactivity_timeout}]

      true ->
        actions
    end
  end

  @spec verify_golden_rule([action()], t()) :: [action()]
  defp verify_golden_rule(actions, state) do
    moving_requested =
      Enum.any?(actions, fn a -> match?({:move, _}, a) or match?({:crawl, _}, a) end)

    motor_active = state.hardware.motor_status not in [:stopped, :stopping]
    doors_not_closed = state.hardware.door_status != :closed

    is_unsafe = doors_not_closed and (moving_requested or motor_active)

    if is_unsafe do
      :telemetry.execute([:elevator, :core, :safety_breach], %{}, %{
        phase: state.logic.phase,
        door_status: state.hardware.door_status,
        motor_status: state.hardware.motor_status,
        actions: actions
      })

      actions ++ [{:stop_motor}]
    else
      actions
    end
  end

  # ---------------------------------------------------------------------------
  # ## Semantic Helpers (Conditions with >1 check)
  # ---------------------------------------------------------------------------

  defp phase_entered?(baseline, transitions_applied, phase) do
    transitions_applied.logic.phase == phase and baseline.logic.phase != phase
  end

  defp phase_left?(baseline, transitions_applied, phase) do
    baseline.logic.phase == phase and transitions_applied.logic.phase != phase
  end

  defp floor_reached?(baseline, transitions_applied) do
    baseline.hardware.current_floor != transitions_applied.hardware.current_floor and
      is_integer(transitions_applied.hardware.current_floor)
  end

  defp door_ready_to_open?(state) do
    state.logic.phase == :opening
  end

  defp door_ready_to_close?(state) do
    state.logic.phase == :closing
  end
end
