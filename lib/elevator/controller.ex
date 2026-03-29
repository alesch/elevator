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

  @doc "Fetches the internal timer reference (Diagnostics only)."
  def get_timer_ref(pid) do
    GenServer.call(pid, :get_timer_ref)
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
  def handle_cast({:request_floor, source, floor}, data) do
    new_data =
      data
      |> update_core_state(source, floor)
      |> reset_inactivity_timer()

    {:noreply, new_data}
  end

  @impl true
  def handle_call(:get_state, _from, data) do
    {:reply, data.state, data}
  end

  @impl true
  def handle_call(:get_timer_ref, _from, data) do
    {:reply, data.timer, data}
  end

  @impl true
  def handle_info(:return_to_base, data) do
    new_data =
      data
      |> update_core_state(:hall, 1)
      |> reset_inactivity_timer()

    {:noreply, new_data}
  end

  # ---------------------------------------------------------------------------
  # ## Private Helpers
  # ---------------------------------------------------------------------------

  defp build_initial_state(opts) do
    opts
    |> create_base_state()
    |> position_at_provided_floor(opts)
  end

  defp create_base_state(opts) do
    case Keyword.get(opts, :type, :passenger) do
      :freight -> State.new_freight()
      _ -> State.new_passenger()
    end
  end

  defp position_at_provided_floor(state, opts) do
    if floor = Keyword.get(opts, :current_floor) do
      %{state | current_floor: floor}
    else
      state
    end
  end

  defp update_core_state(data, source, floor) do
    %{data | state: State.request_floor(data.state, source, floor)}
  end

  defp reset_inactivity_timer(%{timer: timer, timer_ms: ms} = data) do
    Process.cancel_timer(timer)
    %{data | timer: schedule_return_to_base(ms)}
  end

  defp schedule_return_to_base(ms) do
    Process.send_after(self(), :return_to_base, ms)
  end
end
