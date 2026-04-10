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

  @type t :: %__MODULE__{}

  # ---------------------------------------------------------------------------
  # ## Status Accessors (Public)
  # ---------------------------------------------------------------------------

  def phase(%Core{logic: %{phase: p}}), do: p
  def door_status(%Core{hardware: %{door_status: d}}), do: d
  def motor_status(%Core{hardware: %{motor_status: m}}), do: m
  def current_floor(%Core{hardware: %{current_floor: f}}), do: f

  def requests(%Core{logic: %{sweep: s}, hardware: %{current_floor: f}}) do
    if is_integer(f), do: Elevator.Sweep.queue(s, f), else: []
  end

  def heading(%Core{logic: %{phase: :booting}}), do: :idle
  def heading(%Core{logic: %{phase: :rehoming}, hardware: %{current_floor: :unknown}}), do: :down
  def heading(%Core{logic: %{sweep: s}}), do: Elevator.Sweep.heading(s)

  def next_stop(%Core{logic: %{sweep: s}, hardware: %{current_floor: f}}) do
    if is_integer(f), do: Elevator.Sweep.next_stop(s, f), else: nil
  end

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
    |> handle_event(:motor_stopped, nil)
    |> elem(0)
    |> handle_event(:door_opened, 0)
    |> elem(0)
  end

  @doc "Factory: Returns an elevator moving between two floors."
  @spec moving_to(integer(), integer()) :: t()
  def moving_to(from, to) do
    idle_at(from)
    |> request_floor(:car, to)
    |> elem(0)
    |> handle_event(:motor_running, nil)
    |> elem(0)
  end

  # ---------------------------------------------------------------------------
  # ## Public API (Entry Points)
  # ---------------------------------------------------------------------------

  def request_floor(%Core{logic: %{phase: phase}} = state, _source, _floor)
      when phase in [:booting, :rehoming],
      do: {state, []}

  def request_floor(%Core{} = state, source, floor) when is_integer(floor) do
    state
    |> Map.put(:signal, {:request, source, floor})
    |> pulse()
  end

  def process_arrival(%Core{} = state, floor) do
    state
    |> handle_event(:arrival, floor)
  end

  def handle_button_press(%Core{logic: %{phase: phase}} = state, _button, _now)
      when phase in [:booting, :rehoming],
      do: {state, []}

  def handle_button_press(state, button, now) do
    state
    |> do_ingest_button(button, now)
    |> pulse()
  end

  def handle_event(state, event, payload \\ nil) do
    state
    |> do_ingest_event(event, payload)
    |> pulse()
  end

  # ---------------------------------------------------------------------------
  # ## The Engine (Pulse)
  # ---------------------------------------------------------------------------

  def pulse(state) do
    state_ready = ingest_signals(state)
    new_state = state_ready |> transit()

    actions = derive_actions(state, new_state)

    final_state = %{new_state | signal: nil}
    {final_state, actions}
  end

  defp ingest_signals(%Core{signal: {:request, source, floor}} = state) do
    state
    |> add_sweep_request(source, floor)
    |> update_sweep_heading()
  end

  defp ingest_signals(%Core{signal: :inactivity_timeout} = state) do
    if current_floor(state) != @base_floor do
      state
      |> add_sweep_request(:car, @base_floor)
      |> update_sweep_heading()
    else
      state
    end
  end

  defp ingest_signals(state), do: state

  # ---------------------------------------------------------------------------
  # ## Hardware Ingestion Layer
  # ---------------------------------------------------------------------------

  defp do_ingest_event(state, :startup_check, %{vault: v, sensor: s}) do
    if warm_start?(v, s) do
      state
      |> put_in([Access.key(:hardware), :current_floor], v)
      |> Map.put(:signal, :warm_start)
    else
      Map.put(state, :signal, :rehoming_started)
    end
  end

  defp do_ingest_event(state, :recovery_complete, floor) do
    state
    |> put_in([Access.key(:hardware), :current_floor], floor)
    |> Map.put(:signal, :recovery_complete)
  end

  defp do_ingest_event(state, :arrival, floor), do: put_in(state.hardware.current_floor, floor)

  defp do_ingest_event(state, :motor_stopped, _),
    do: put_in(state.hardware.motor_status, :stopped)

  defp do_ingest_event(state, :motor_running, _),
    do: put_in(state.hardware.motor_status, :running)

  defp do_ingest_event(state, :door_opened, now) do
    state
    |> put_in([Access.key(:hardware), :door_status], :open)
    |> put_in([Access.key(:logic), :last_activity_at], now)
  end

  defp do_ingest_event(state, :door_closed, _), do: put_in(state.hardware.door_status, :closed)

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

  defp transit(%Core{} = state), do: do_transit(state)

  # Booting
  defp do_transit(%Core{logic: %{phase: :booting}, signal: :warm_start} = state) do
    put_in(state.logic.phase, :idle)
  end

  defp do_transit(%Core{logic: %{phase: :booting}, signal: :recovery_complete} = state) do
    put_in(state.logic.phase, :idle)
  end

  defp do_transit(%Core{logic: %{phase: :booting}, signal: :rehoming_started} = state) do
    put_in(state.logic.phase, :rehoming)
  end

  # Rehoming
  defp do_transit(
         %Core{
           logic: %{phase: :rehoming},
           hardware: %{current_floor: floor, motor_status: :stopped}
         } = state
       )
       when is_integer(floor) do
    put_in(state.logic.phase, :idle)
  end

  # Idle
  defp do_transit(%Core{logic: %{phase: :idle}, signal: sig} = state) do
    nxt = next_stop(state)
    has_work = not is_nil(nxt)

    cond do
      has_work and nxt == current_floor(state) ->
        state |> put_in([Access.key(:logic), :phase], :arriving) |> floor_serviced()

      has_work ->
        put_in(state.logic.phase, :moving)

      sig == :door_open ->
        state |> put_in([Access.key(:logic), :phase], :arriving) |> floor_serviced()

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

  # Arriving -> Docked
  defp do_transit(%Core{logic: %{phase: :arriving}, hardware: %{door_status: :open}} = state) do
    state
    |> put_in([Access.key(:logic), :phase], :docked)
    |> floor_serviced()
  end

  # Docked -> Leaving
  defp do_transit(%Core{logic: %{phase: :docked}, signal: sig} = state)
       when sig in [:door_timeout, :door_close] do
    put_in(state.logic.phase, :leaving)
  end

  # Leaving -> Arriving (Obstruction or Open)
  defp do_transit(%Core{logic: %{phase: :leaving}, hardware: %{door_sensor: :blocked}} = state) do
    put_in(state.logic.phase, :arriving)
  end

  defp do_transit(%Core{logic: %{phase: :leaving}, signal: :door_open} = state) do
    put_in(state.logic.phase, :arriving)
  end

  # Leaving -> Settle
  defp do_transit(%Core{logic: %{phase: :leaving}, hardware: %{door_status: :closed}} = state) do
    state = update_sweep_heading(state)

    if heading(state) == :idle do
      put_in(state.logic.phase, :idle)
    else
      put_in(state.logic.phase, :moving)
    end
  end

  # Default
  defp do_transit(state), do: state

  # ---------------------------------------------------------------------------
  # ## Calculation Helpers
  # ---------------------------------------------------------------------------

  defp add_sweep_request(state, source, floor) do
    Map.update!(state, :logic, fn logic ->
      Map.update!(logic, :sweep, &Elevator.Sweep.add_request(&1, source, floor))
    end)
  end

  defp update_sweep_heading(state) do
    f = current_floor(state)

    if is_integer(f) do
      Map.update!(state, :logic, fn logic ->
        Map.update!(logic, :sweep, &Elevator.Sweep.update_heading(&1, f))
      end)
    else
      state
    end
  end

  defp floor_serviced(state) do
    f = current_floor(state)

    if is_integer(f) do
      Map.update!(state, :logic, fn logic ->
        Map.update!(logic, :sweep, &Elevator.Sweep.floor_serviced(&1, f))
      end)
    else
      state
    end
  end

  defp warm_start?(v, s), do: v == s and is_integer(v)

  # ---------------------------------------------------------------------------
  # ## Action Derivation
  # ---------------------------------------------------------------------------

  defp derive_actions(old, new) do
    []
    |> verify_golden_rule(new)
    |> update_motor_action(old, new)
    |> update_door_action(old, new)
    |> update_timer_action(old, new)
    |> update_persistence_action(old, new)
  end

  defp update_persistence_action(actions, old, new) do
    if old.hardware.current_floor != new.hardware.current_floor and
         is_integer(new.hardware.current_floor) do
      actions ++ [{:persist_arrival, new.hardware.current_floor}]
    else
      actions
    end
  end

  defp update_motor_action(actions, old, new) do
    entered_arriving = new.logic.phase == :arriving and old.logic.phase != :arriving
    entered_idle = new.logic.phase == :idle and old.logic.phase != :idle
    entered_rehoming = new.logic.phase == :rehoming and old.logic.phase != :rehoming
    entered_moving = new.logic.phase == :moving and old.logic.phase != :moving

    cond do
      entered_arriving and new.hardware.motor_status != :stopped ->
        actions ++ [{:stop_motor}]

      entered_idle and new.hardware.motor_status != :stopped ->
        actions ++ [{:stop_motor}]

      entered_rehoming ->
        actions ++ [{:crawl, heading(new)}]

      entered_moving ->
        actions ++ [{:move, heading(new)}]

      new.logic.phase == :moving and heading(old) != heading(new) ->
        actions ++ [{:move, heading(new)}]

      true ->
        actions
    end
  end

  defp update_door_action(actions, old, new) do
    old_ready_open = old.logic.phase == :arriving and old.hardware.motor_status == :stopped
    new_ready_open = new.logic.phase == :arriving and new.hardware.motor_status == :stopped

    old_ready_close = old.logic.phase == :leaving
    new_ready_close = new.logic.phase == :leaving

    cond do
      new_ready_open and not old_ready_open and new.hardware.door_status != :open ->
        actions ++ [{:open_door}]

      new_ready_close and not old_ready_close and new.hardware.door_status != :closed ->
        actions ++ [{:close_door}]

      true ->
        actions
    end
  end

  defp update_timer_action(actions, old, new) do
    entered_docked = new.logic.phase == :docked and old.logic.phase != :docked

    docked_activity =
      new.logic.phase == :docked and new.logic.last_activity_at != old.logic.last_activity_at

    left_docked = old.logic.phase == :docked and new.logic.phase != :docked

    cond do
      entered_docked or docked_activity ->
        actions ++ [{:set_timer, :door_timeout, @door_wait_ms}]

      left_docked ->
        actions ++ [{:cancel_timer, :door_timeout}]

      true ->
        actions
    end
  end

  defp verify_golden_rule(actions, new) do
    cond do
      new.hardware.door_status != :closed and
          new.hardware.motor_status not in [:stopped, :stopping] ->
        Logger.error("CRITICAL SAFETY BREACH: Golden Rule Violated.")
        actions ++ [{:stop_motor}]

      true ->
        actions
    end
  end
end
