defmodule Elevator.Controller do
  @moduledoc """
  The Imperative Shell for the Elevator.
  Handles concurrency, state persistence, and timer-based behavior.
  """
  use GenServer
  alias Elevator.State

  @default_return_to_base_ms 300_000 # 5 minutes

  # ---------------------------------------------------------------------------
  # ## Client API
  # ---------------------------------------------------------------------------

  @doc "Starts a new elevator controller process."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  @doc "Adds a floor request asynchronously."
  def request_floor(pid, source, floor) do
    GenServer.cast(pid, {:request_floor, source, floor})
  end

  @doc "Fetches the current state snapshot."
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  # ---------------------------------------------------------------------------
  # ## Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    timer_ms = Keyword.get(opts, :timer_ms, @default_return_to_base_ms)

    data = %{
      state: build_initial_state(opts),
      timer_ms: timer_ms,
      timer: schedule_return_to_base(timer_ms)
    }

    {:ok, data}
  end

  @impl true
  def handle_cast({:request_floor, source, floor}, %{state: state, timer: timer, timer_ms: timer_ms} = data) do
    # 1. Update the functional core
    new_state = State.request_floor(state, source, floor)

    # 2. Reset the Return-to-Base timer (Rule 1.4 sliding window)
    Process.cancel_timer(timer)
    new_timer = schedule_return_to_base(timer_ms)

    {:noreply, %{data | state: new_state, timer: new_timer}}
  end

  @impl true
  def handle_call(:get_state, _from, data) do
    {:reply, data.state, data}
  end

  @impl true
  def handle_info(:return_to_base, %{state: state, timer_ms: timer_ms} = data) do
    # Rule 1.4: Auto-inject Hall request for Floor 1 after inactivity
    new_state = State.request_floor(state, :hall, 1)
    
    # Reschedule timer
    new_timer = schedule_return_to_base(timer_ms)

    {:noreply, %{data | state: new_state, timer: new_timer}}
  end

  # ---------------------------------------------------------------------------
  # ## Private Helpers
  # ---------------------------------------------------------------------------

  defp build_initial_state(opts) do
    case Keyword.get(opts, :type, :passenger) do
      :freight -> State.new_freight()
      _ -> State.new_passenger()
    end
  end

  defp schedule_return_to_base(ms) do
    Process.send_after(self(), :return_to_base, ms)
  end
end
