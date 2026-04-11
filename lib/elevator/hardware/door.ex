defmodule Elevator.Hardware.Door do
  @moduledoc """
  The 'Safety Boundary' of the system.
  A 5-state machine: :opening, :open, :closing, :closed, :obstructed.
  """
  use GenServer
  require Logger

  # 1 second for opening/closing
  @op_ms 1000

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @doc "Starts a new elevator door process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Commands the door to start opening."
  @spec open(pid() | atom()) :: :ok
  def open(pid \\ __MODULE__) do
    GenServer.cast(pid, :open)
  end

  @doc "Commands the door to start closing."
  @spec close(pid() | atom()) :: :ok
  def close(pid \\ __MODULE__) do
    GenServer.cast(pid, :close)
  end

  @doc "Simulates a hardware-level obstruction event."
  @spec simulate_obstruction(pid() | atom()) :: :ok
  def simulate_obstruction(pid \\ __MODULE__) do
    GenServer.cast(pid, :door_obstructed)
  end

  @doc "Peeks at the door state."
  @spec get_state(pid() | atom()) :: map()
  def get_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_state)
  end

  @type t :: %{
          status: :open | :closed | :opening | :closing | :obstructed,
          timer: reference() | nil,
          controller: pid() | nil
        }

  # ---------------------------------------------------------------------------
  # ## Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    # Register brain only if it's a named process (Supervisor/Production)
    if Keyword.get(opts, :name) != nil do
      {:ok, _} = Registry.register(Elevator.Registry, :door, nil)
    end

    controller = Keyword.get(opts, :controller)

    {:ok, %{status: :closed, timer: nil, controller: controller}}
  end

  @impl true
  @spec handle_call(:get_state, GenServer.from(), map()) :: {:reply, map(), map()}
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  @spec handle_cast(:open, t()) :: {:noreply, t()}
  def handle_cast(:open, %{status: status} = state) when status in [:open, :opening] do
    {:noreply, handle_redundant_request(state, :open)}
  end

  def handle_cast(:open, state) do
    :telemetry.execute([:elevator, :hardware, :door, :open], %{}, %{redundant: false})
    {:noreply, start_transit(state, :opening, :fully_opened)}
  end

  @impl true
  @spec handle_cast(:close, t()) :: {:noreply, t()}
  def handle_cast(:close, %{status: status} = state) when status in [:closed, :closing] do
    {:noreply, handle_redundant_request(state, :close)}
  end

  def handle_cast(:close, state) do
    :telemetry.execute([:elevator, :hardware, :door, :close], %{}, %{redundant: false})
    {:noreply, start_transit(state, :closing, :fully_closed)}
  end

  @impl true
  @spec handle_cast(:door_obstructed, t()) :: {:noreply, t()}
  def handle_cast(:door_obstructed, state) do
    :telemetry.execute([:elevator, :hardware, :door, :obstruction], %{}, %{})

    state =
      state
      |> cancel_timer()
      |> update_status(:obstructed)

    notify_controller(state, :door_obstructed)

    {:noreply, state}
  end

  @impl true
  @spec handle_info(:fully_opened, map()) :: {:noreply, map()}
  def handle_info(:fully_opened, state) do
    :telemetry.execute([:elevator, :hardware, :door, :transit_complete], %{}, %{result: :open})
    notify_controller(state, :door_opened)
    new_state = %{update_status(state, :open) | timer: nil}
    {:noreply, new_state}
  end

  @impl true
  @spec handle_info(:fully_closed, map()) :: {:noreply, map()}
  def handle_info(:fully_closed, state) do
    :telemetry.execute([:elevator, :hardware, :door, :transit_complete], %{}, %{result: :closed})
    notify_controller(state, :door_closed)
    new_state = %{update_status(state, :closed) | timer: nil}
    {:noreply, new_state}
  end

  @impl true
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info(msg, state) do
    Logger.warning("Door: Unexpected message #{inspect(msg)} in state: #{inspect(state)}")

    :telemetry.execute([:elevator, :hardware, :door, :unexpected_message], %{}, %{
      message: msg,
      state: state
    })

    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  @spec start_transit(t(), atom(), term()) :: t()
  defp start_transit(state, new_status, timer_msg) do
    state
    |> cancel_timer()
    |> start_timer(timer_msg, @op_ms)
    |> update_status(new_status)
  end

  @spec handle_redundant_request(t(), atom()) :: t()
  defp handle_redundant_request(%{status: status} = state, action) do
    :telemetry.execute([:elevator, :hardware, :door, action], %{}, %{
      status: status,
      redundant: true
    })

    state
  end

  @spec update_status(t(), atom()) :: t()
  defp update_status(state, status) do
    :telemetry.execute([:elevator, :hardware, :door, :state_change], %{}, %{status: status})
    %{state | status: status}
  end

  @spec start_timer(t(), term(), integer()) :: t()
  defp start_timer(state, msg, ms) do
    timer = Process.send_after(self(), msg, ms)
    %{state | timer: timer}
  end

  @spec cancel_timer(t()) :: t()
  defp cancel_timer(%{timer: nil} = state), do: state

  defp cancel_timer(%{timer: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timer: nil}
  end

  @spec notify_controller(map(), atom()) :: :ok
  defp notify_controller(state, msg) do
    target = state.controller || lookup_controller()
    if target, do: send(target, msg), else: :ok
  end

  defp lookup_controller do
    case Registry.lookup(Elevator.Registry, :controller) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end
end
