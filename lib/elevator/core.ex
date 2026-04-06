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
            heading: :idle,
            door_status: :closed,
            requests: [],
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
          heading: :up | :down | :idle,
          door_status: :open | :closed | :opening | :closing | :obstructed,
          requests: list({atom(), integer()}),
          last_activity_at: integer(),
          phase: :booting | :rehoming | :moving | :arriving | :docked | :leaving | :idle,
          door_sensor: :clear | :blocked,
          motor_status: :running | :crawling | :stopping | :stopped
        }

  # ---------------------------------------------------------------------------
  # ## Public API (Entry Points)
  # ---------------------------------------------------------------------------

  @doc "Adds a floor request and triggers a transit pulse."
  @spec request_floor(t(), atom(), integer()) :: {t(), [action()]}
  def request_floor(%Core{phase: :booting} = state, _source, _floor), do: {state, []}

  def request_floor(%Core{} = state, source, floor) when is_integer(floor) do
    state
    |> add_request(source, floor)
    |> update_heading()
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
    state
    |> transit_logic()
  end

  # Internal recursive-ready transit loop (but maintains single-step logic per plan)
  defp transit_logic(state) do
    state
    |> do_transit()
  end

  # Rule: Transition from Booting to Idle via Recovery
  defp do_transit(%Core{phase: :booting} = state), do: state

  # Rule: Transition from Rehoming to Arriving (Braking)
  defp do_transit(%Core{phase: :rehoming, current_floor: 0, motor_status: m} = state)
       when m in [:running, :crawling] do
    %{state | motor_status: :stopping, phase: :arriving}
  end

  # Rule: Transition from Moving/Idle to Arriving (Braking)
  defp do_transit(%Core{phase: p, motor_status: m} = state)
       when p in [:moving, :idle] and m in [:running, :crawling] do
    if should_stop_at?(state, state.current_floor) or overshooting?(state) do
      %{state | motor_status: :stopping, phase: :arriving}
    else
      state
    end
  end

  # Rule: Transition from Idle to Moving
  defp do_transit(%Core{phase: :idle, heading: h, door_status: :closed} = state)
       when h != :idle do
    %{state | phase: :moving, motor_status: :running}
  end

  # Rule: Gateway Exit -> Transition to :leaving when doors begin closing
  defp do_transit(%Core{phase: p, door_status: :closing} = state)
       when p in [:arriving, :docked] do
    %{state | phase: :leaving}
  end

  # Rule: Gateway Exit -> Transition to :docked when doors are open
  defp do_transit(%Core{phase: :arriving, door_status: :open} = state) do
    %{state | phase: :docked}
  end

  # Rule: Gateway Settle -> Initiate door opening once motor stops
  defp do_transit(%Core{phase: :arriving, motor_status: :stopped} = state) do
    if state.door_status in [:closed, :obstructed] do
      state
      |> fulfill_current_floor_requests()
      |> Map.put(:door_status, :opening)
    else
      state
    end
  end

  # Rule: Settlement from Leaving
  defp do_transit(%Core{phase: :leaving, door_status: :closed} = state) do
    state = update_heading(state)
    new_phase = if state.heading == :idle, do: :idle, else: :moving
    new_motor = if new_phase == :idle, do: :stopped, else: :running
    %{state | phase: new_phase, motor_status: new_motor}
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
    %{state | phase: :rehoming, heading: :down, motor_status: :crawling}
  end

  defp do_ingest_event(state, :motor_stopped, _), do: %{state | motor_status: :stopped}
  defp do_ingest_event(state, :door_opened, now), do: %{state | door_status: :open, last_activity_at: now}
  defp do_ingest_event(state, :door_closed, _), do: %{state | door_status: :closed}
  defp do_ingest_event(state, :door_obstructed, _), do: %{state | door_status: :obstructed, door_sensor: :blocked}
  defp do_ingest_event(state, :door_cleared, _), do: %{state | door_sensor: :clear}

  defp do_ingest_event(%Core{phase: :idle} = state, :inactivity_timeout, _) do
    if state.current_floor != @base_floor do
      add_request(state, :car, @base_floor) |> update_heading()
    else
      state
    end
  end

  defp do_ingest_event(%Core{phase: :docked} = state, :door_timeout, _) do
    if state.door_sensor == :clear do
      %{state | door_status: :closing}
    else
      state
    end
  end

  defp do_ingest_event(state, _, _), do: state

  defp do_ingest_button(state, :door_open, now) do
    if state.door_status in [:closed, :closing] do
      %{state | door_status: :opening}
    else
      %{state | last_activity_at: now}
    end
  end

  defp do_ingest_button(state, :door_close, _) do
    if state.door_status == :open do
      %{state | door_status: :closing}
    else
      state
    end
  end

  defp do_ingest_button(state, _, _), do: state

  # ---------------------------------------------------------------------------
  # ## Calculation Helpers
  # ---------------------------------------------------------------------------

  def update_heading(state) do
    cond do
      any_requests_above?(state) -> %{state | heading: :up}
      any_requests_below?(state) -> %{state | heading: :down}
      true -> %{state | heading: :idle}
    end
  end

  defp overshooting?(state) do
    cond do
      state.heading == :up and not any_requests_above?(state) -> true
      state.heading == :down and not any_requests_below?(state) -> true
      true -> false
    end
  end

  defp fulfill_current_floor_requests(state) do
    state |> Map.update!(:requests, fn reqs ->
      Enum.reject(reqs, fn {_, f} -> f == state.current_floor end)
    end)
  end

  defp should_stop_at?(state, floor) do
    Enum.any?(state.requests, fn {_, f} -> f == floor end)
  end

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
          (old.motor_status != :running or old.heading != new.heading) ->
        actions ++ [{:move, new.heading}]

      new.motor_status == :crawling and
          (old.motor_status != :crawling or old.heading != new.heading) ->
        actions ++ [{:crawl, new.heading}]

      true ->
        actions
    end
  end

  defp update_door_action(actions, old, new) do
    cond do
      new.door_status in [:opening, :obstructed] and old.door_status not in [:opening, :obstructed] -> actions ++ [{:open_door}]
      new.door_status == :closing and old.door_status != :closing -> actions ++ [{:close_door}]
      true -> actions
    end
  end

  defp update_timer_action(actions, old, new) do
    cond do
      new.door_status == :open and (old.door_status != :open or old.last_activity_at != new.last_activity_at) ->
        actions ++ [{:set_timer, :door_timeout, @door_wait_ms}]
      new.door_status != :open and old.door_status == :open ->
        actions ++ [{:cancel_timer, :door_timeout}]
      true -> actions
    end
  end

  defp enforce_the_golden_rule(state) do
    if state.door_status != :closed and state.motor_status != :stopped do
      Logger.warning("The Golden Rule: Motor forced stopped. Phase: #{state.phase}, door: #{state.door_status}")
      %{state | motor_status: :stopped}
    else
      state
    end
  end
end
