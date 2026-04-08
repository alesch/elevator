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
  def init, do: %Core{}

  @doc """
  Factory: Returns an elevator idle at the given floor.
  Bypasses rehoming by simulating a successful recovery.
  """
  def idle_at(floor) do
    init()
    |> handle_event(:recovery_complete, floor)
    |> elem(0)
  end

  @doc "Factory: Returns an elevator docked (door open) at the given floor."
  def docked_at(floor) do
    idle_at(floor)
    |> request_floor(:car, floor)
    |> elem(0)
    |> handle_event(:door_opened)
    |> elem(0)
  end

  @doc "Factory: Returns an elevator moving between two floors."
  def moving_to(from, to) do
    idle_at(from)
    |> request_floor(:car, to)
    |> elem(0)
  end

  # ---------------------------------------------------------------------------
  # ## Status Accessors (Public)
  # ---------------------------------------------------------------------------

  @doc "Returns the current request queue via the LOOK algorithm."
  def requests(%Core{sweep: s, current_floor: f}), do: Elevator.Sweep.queue(s, f)

  @doc "Returns the current heading."
  def heading(%Core{sweep: s}), do: Elevator.Sweep.heading(s)

  @doc "Returns the current operational phase."
  def phase(%Core{phase: p}), do: p

  @doc "Returns the physical door status."
  def door_status(%Core{door_status: d}), do: d

  @doc "Returns the physical motor status."
  def motor_status(%Core{motor_status: m}), do: m

  @doc "Returns the confirmed current floor."
  def current_floor(%Core{current_floor: f}), do: f

  @doc "Returns the next immediate stop according to LOOK."
  def next_stop(%Core{sweep: s, current_floor: f}), do: Elevator.Sweep.next_stop(s, f)

  # ---------------------------------------------------------------------------
  # ## Public API (Entry Points)
  # ---------------------------------------------------------------------------

  @doc "Adds a floor request and triggers a transit pulse."
  @spec request_floor(t(), atom(), integer()) :: {t(), [action()]}
  def request_floor(%Core{phase: :booting} = state, _source, _floor), do: {state, []}

  def request_floor(%Core{} = state, source, floor) when is_integer(floor) do
    state
    |> add_sweep_request(source, floor)
    |> update_sweep_heading()
    |> pulse()
  end

  @doc "Processes physical arrival at a floor and triggers a transit pulse."
  @spec process_arrival(t(), integer()) :: {t(), [action()]}
  def process_arrival(%Core{} = state, floor) do
    state
    |> Map.put(:current_floor, floor)
    |> pulse()
  end

  @doc "Handles physical button presses and triggers a transit pulse."
  @spec handle_button_press(t(), atom(), integer()) :: {t(), [action()]}
  def handle_button_press(state, button, now) do
    state
    |> do_ingest_button(button, now)
    |> pulse()
  end

  @doc "Central event handler for component confirmations and triggers a transit pulse."
  @spec handle_event(t(), atom(), integer() | nil) :: {t(), [action()]}
  def handle_event(state, event, payload \\ nil) do
    state
    |> do_ingest_event(event, payload)
    |> pulse()
  end

  # ---------------------------------------------------------------------------
  # ## The Engine (Pulse)
  # ---------------------------------------------------------------------------

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

  # Rule: Wakeup: Completely Idle (No Requests)
  defp do_transit(%Core{phase: :idle} = state) do
    case heading(state) do
      :idle ->
        if state.door_command == :open do
          state
          |> Map.put(:phase, :arriving)
          |> Map.put(:door_status, :opening)
          |> Map.put(:door_command, nil)
          |> perform_floor_service()
        else
          state
        end

      _heading ->
        if state.current_floor == next_stop(state) do
          state
          |> Map.put(:phase, :arriving)
          |> Map.put(:door_status, :opening)
          |> perform_floor_service()
        else
          %{state | phase: :moving, motor_status: :running}
        end
    end
  end

  # Rule: Gateway Reversal -> Transition to arriving AND opening doors
  defp do_transit(%Core{phase: :leaving, door_status: :obstructed} = state) do
    %{state | phase: :arriving, door_status: :opening}
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
      |> perform_floor_service()
      |> Map.put(:door_status, :opening)
    else
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

  # ---------------------------------------------------------------------------
  # ## Data Ingestion Helpers
  # ---------------------------------------------------------------------------

  defp do_ingest_event(state, :recovery_complete, floor) do
    %{state | phase: :idle, current_floor: floor}
  end

  defp do_ingest_event(state, :rehoming_started, _) do
    state
    |> Map.put(:phase, :rehoming)
    |> update_in([Access.key(:sweep), Access.key(:heading)], fn _ -> :down end)
    |> Map.put(:motor_status, :crawling)
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

  defp perform_floor_service(state) do
    service_sweep_floor(state)
  end

  defp add_sweep_request(state, source, floor) do
    Map.update!(state, :sweep, &Elevator.Sweep.add_request(&1, source, floor))
  end

  defp update_sweep_heading(state) do
    Map.update!(state, :sweep, &Elevator.Sweep.update_heading(&1, state.current_floor))
  end

  defp service_sweep_floor(state) do
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
  end

  defp update_motor_action(actions, old, new) do
    cond do
      new.motor_status in [:stopping, :stopped] and old.motor_status not in [:stopping, :stopped] ->
        actions ++ [{:stop_motor}]

      new.motor_status == :running and
          (old.motor_status != :running or heading(old) != heading(new)) ->
        actions ++ [{:move, heading(new)}]

      new.motor_status == :crawling and
          (old.motor_status != :crawling or heading(old) != heading(new)) ->
        actions ++ [{:crawl, heading(new)}]

      true ->
        actions
    end
  end

  defp update_door_action(actions, old, new) do
    cond do
      new.door_status in [:opening, :obstructed] and
          old.door_status not in [:opening, :obstructed] ->
        actions ++ [{:open_door}]

      new.door_status == :closing and old.door_status != :closing ->
        actions ++ [{:close_door}]

      true ->
        actions
    end
  end

  defp update_timer_action(actions, old, new) do
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
    if state.door_status != :closed and state.motor_status != :stopped do
      Logger.warning(
        "The Golden Rule: Motor forced stopped. Phase: #{state.phase}, door: #{state.door_status}"
      )

      %{state | motor_status: :stopped}
    else
      state
    end
  end
end
