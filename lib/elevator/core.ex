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

  @type phase ::
          :booting
          | :idle
          | :moving
          | :arriving
          | :opening
          | :docked
          | :closing
          | :leaving
          | :rehoming
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
  Drives through the post-docking sequence: docked -> closing -> idle.
  """
  @spec idle_at(integer()) :: t()
  def idle_at(floor) do
    docked_at(floor)
    |> handle_event(:door_timeout)
    |> elem(0)
    |> handle_event(:door_closed)
    |> elem(0)
  end

  @doc """
  Factory: Returns an elevator docked (door open) at the given floor.
  Drives through the cold-start rehoming sequence: rehoming -> arriving -> opening -> docked.
  """
  @spec docked_at(integer()) :: t()
  def docked_at(floor) do
    booting()
    |> handle_event(:startup_check, %{vault: nil, sensor: nil})
    |> elem(0)
    |> handle_event(:motor_crawling)
    |> elem(0)
    |> handle_event(:floor_arrival, floor)
    |> elem(0)
    |> handle_event(:motor_stopped)
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
  def request_floor(%Core{} = state, {_source, floor} = request) when is_integer(floor) do
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
  defp pulse(state) do
    new_state = state |> ingest_signals() |> transit()
    {clear_signal(new_state), derive_actions(new_state)}
  end

  defp clear_signal(state), do: %{state | signal: nil}

  @spec ingest_signals(t()) :: t()
  defp ingest_signals(state), do: state

  # ---------------------------------------------------------------------------
  # ## Hardware Ingestion Layer
  # ---------------------------------------------------------------------------

  # Hardware Ingestion
  @spec do_ingest_event(t(), atom(), event_payload()) :: t()
  defp do_ingest_event(state, :startup_check, %{vault: vault, sensor: sensor}) do
    state
    |> update_current_floor(sensor)
    |> Map.put(:signal, {:startup_check, vault, sensor})
  end

  defp do_ingest_event(state, :floor_arrival, floor) do
    state
    |> put_in([Access.key(:hardware), :current_floor], floor)
    |> Map.put(:signal, :floor_arrival)
  end

  defp do_ingest_event(state, :motor_stopped, _) do
    state
    |> put_in([Access.key(:hardware), :motor_status], :stopped)
    |> Map.put(:signal, :motor_stopped)
  end

  defp do_ingest_event(state, :motor_running, _) do
    state
    |> put_in([Access.key(:hardware), :motor_status], :running)
    |> Map.put(:signal, :motor_running)
  end

  defp do_ingest_event(state, :motor_crawling, _),
    do: put_in(state.hardware.motor_status, :crawling)

  defp do_ingest_event(state, :door_opened, now) do
    state
    |> put_in([Access.key(:hardware), :door_status], :open)
    |> put_in([Access.key(:logic), :last_activity_at], now)
    |> Map.put(:signal, :door_opened)
  end

  defp do_ingest_event(state, :door_closed, _) do
    state
    |> put_in([Access.key(:hardware), :door_status], :closed)
    |> Map.put(:signal, :door_closed)
  end

  defp do_ingest_event(state, :door_opening, _), do: put_in(state.hardware.door_status, :opening)

  defp do_ingest_event(state, :door_closing, _), do: put_in(state.hardware.door_status, :closing)

  defp do_ingest_event(state, :door_obstructed, _) do
    state
    |> put_in([Access.key(:hardware), :door_status], :obstructed)
    |> put_in([Access.key(:hardware), :door_sensor], :blocked)
    |> Map.put(:signal, :door_obstructed)
  end

  defp do_ingest_event(state, :door_cleared, _), do: put_in(state.hardware.door_sensor, :clear)

  defp do_ingest_event(state, :inactivity_timeout, _) do
    %{state | signal: :inactivity_timeout}
  end

  defp do_ingest_event(state, :door_timeout, _) do
    %{state | signal: :door_timeout}
  end

  defp do_ingest_event(state, _, _), do: state

  # Buttons
  @spec do_ingest_button(t(), atom(), integer()) :: t()
  defp do_ingest_button(%Core{logic: %{phase: :docked}} = state, :door_open, now) do
    Map.put(state, :signal, {:door_open, now})
  end

  defp do_ingest_button(%Core{logic: %{phase: phase}} = state, :door_open, _now)
       when phase in [:idle, :leaving, :closing] do
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
  defp do_transit(
         %Core{logic: %{phase: :booting}, signal: {:startup_check, vault, sensor}} = state
       ) do
    if warm_start?(vault, sensor) do
      put_in(state.logic.phase, :opening)
    else
      put_in(state.logic.phase, :rehoming)
    end
  end

  # Rehoming -> Arriving
  defp do_transit(%Core{logic: %{phase: :rehoming}, signal: :floor_arrival} = state) do
    put_in(state.logic.phase, :arriving)
  end

  # Idle -> Opening or Leaving
  defp do_transit(%Core{logic: %{phase: :idle}, signal: signal} = state) do
    state
    |> queue_request(signal)
    |> idle_transition(signal)
  end

  # Moving -> Arriving
  defp do_transit(%Core{logic: %{phase: :moving}, signal: :floor_arrival} = state) do
    if current_floor(state) == next_stop(state) do
      put_in(state.logic.phase, :arriving)
    else
      state
    end
  end

  # Arriving -> Opening
  defp do_transit(%Core{logic: %{phase: :arriving}, signal: :motor_stopped} = state) do
    put_in(state.logic.phase, :opening)
  end

  # Opening -> Docked: service the current floor, start door timer
  defp do_transit(%Core{logic: %{phase: :opening}, signal: :door_opened} = state) do
    state
    |> floor_serviced()
    |> put_in([Access.key(:logic), :phase], :docked)
  end

  # Docked -> record activity (door_open button extends timer)
  defp do_transit(%Core{logic: %{phase: :docked}, signal: {:door_open, now}} = state) do
    put_in(state, [Access.key(:logic), :last_activity_at], now)
  end

  # Docked -> Closing
  defp do_transit(%Core{logic: %{phase: :docked}, signal: sig} = state)
       when sig in [:door_timeout, :door_close] do
    put_in(state.logic.phase, :closing)
  end

  # Closing -> Opening (Obstruction or manual reopen)
  defp do_transit(%Core{logic: %{phase: :closing}, signal: sig} = state)
       when sig in [:door_obstructed, :door_open] do
    put_in(state.logic.phase, :opening)
  end

  # Closing -> Settle (Idle or Leaving)
  defp do_transit(%Core{logic: %{phase: :closing}, signal: :door_closed} = state) do
    if heading(state) == :idle do
      put_in(state.logic.phase, :idle)
    else
      put_in(state.logic.phase, :leaving)
    end
  end

  # Leaving -> Moving
  defp do_transit(%Core{logic: %{phase: :leaving}, signal: :motor_running} = state) do
    put_in(state.logic.phase, :moving)
  end

  # Queue floor requests in all active phases (booting/rehoming fall through here, request is dropped)
  defp do_transit(%Core{logic: %{phase: phase}, signal: {:request, {source, floor}}} = state)
       when phase not in [:booting, :rehoming] do
    add_sweep_request(state, source, floor)
  end

  # Default
  defp do_transit(state), do: state

  # ---------------------------------------------------------------------------
  # ## Calculation Helpers
  # ---------------------------------------------------------------------------

  defp queue_request(state, {:request, {source, floor}}),
    do: add_sweep_request(state, source, floor)

  defp queue_request(state, :inactivity_timeout) do
    if current_floor(state) != @base_floor,
      do: add_sweep_request(state, :car, @base_floor),
      else: state
  end

  defp queue_request(state, _signal), do: state

  defp idle_transition(state, signal) do
    cond do
      already_at_next_stop?(state) ->
        state |> put_in([Access.key(:logic), :phase], :opening) |> floor_serviced()

      has_next_stop?(state) ->
        put_in(state.logic.phase, :leaving)

      signal == :door_open ->
        state |> put_in([Access.key(:logic), :phase], :opening) |> floor_serviced()

      true ->
        state
    end
  end

  @spec update_current_floor(t(), integer() | nil) :: t()
  defp update_current_floor(state, floor) when is_integer(floor),
    do: put_in(state.hardware.current_floor, floor)

  defp update_current_floor(state, _floor), do: state

  @spec add_sweep_request(t(), Elevator.Sweep.source(), integer()) :: t()
  defp add_sweep_request(state, source, floor) do
    f = current_floor(state)

    Map.update!(state, :logic, fn logic ->
      Map.update!(logic, :sweep, &Elevator.Sweep.add_request(&1, source, floor, f))
    end)
  end

  defp has_next_stop?(state), do: not is_nil(next_stop(state))

  defp already_at_next_stop?(state) do
    nxt = next_stop(state)
    not is_nil(nxt) and nxt == current_floor(state)
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

  @spec derive_actions(t()) :: [action()]
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp derive_actions(
         %Core{
           logic: %{phase: phase},
           signal: signal,
           hardware: %{motor_status: motor_status, current_floor: current_floor}
         } = state
       ) do
    case {phase, signal} do
      # Booting -> Rehoming (cold start)
      {:rehoming, {:startup_check, _, _}} ->
        [{:crawl, :down}]

      # Rehoming -> Arriving: persist position and stop motor
      {:arriving, :floor_arrival} when motor_status == :crawling ->
        [{:persist_arrival, current_floor}, {:stop_motor}]

      # Moving -> Arriving: stop motor only
      {:arriving, :floor_arrival} ->
        [{:stop_motor}]

      # -> Opening: open the door (from any entry path)
      {:opening, {:startup_check, _, _}} ->
        [{:open_door}]

      {:opening, {:request, _}} ->
        [{:open_door}]

      {:opening, :motor_stopped} ->
        [{:open_door}]

      {:opening, :door_obstructed} ->
        [{:open_door}]

      {:opening, :door_open} ->
        [{:open_door}]

      # Opening -> Docked: start door timer
      {:docked, :door_opened} ->
        [{:set_timer, :door_timeout, @door_wait_ms}]

      # Docked: door_open button resets timer
      {:docked, {:door_open, _}} ->
        [{:set_timer, :door_timeout, @door_wait_ms}]

      # Docked -> Closing: close the door
      {:closing, :door_timeout} ->
        [{:close_door}]

      {:closing, :door_close} ->
        [{:cancel_timer, :door_timeout}, {:close_door}]

      # Closing -> Idle: start inactivity timer
      {:idle, :door_closed} ->
        [{:set_timer, :inactivity_timeout, @inactivity_wait_ms}]

      # Idle -> Leaving (request): cancel inactivity timer and move
      {:leaving, {:request, _}} ->
        [{:cancel_timer, :inactivity_timeout}, {:move, heading(state)}]

      # Idle -> Leaving (inactivity): cancel timer and move
      {:leaving, :inactivity_timeout} ->
        [{:cancel_timer, :inactivity_timeout}, {:move, heading(state)}]

      # Closing -> Leaving (pending requests): move
      {:leaving, :door_closed} ->
        [{:move, heading(state)}]

      # Leaving -> Moving: motor confirmed, no external action needed
      {:moving, :motor_running} ->
        []

      # No action for hardware-only updates and all other cases
      _ ->
        []
    end
    |> verify_golden_rule(state)
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
end
