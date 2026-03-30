defmodule Elevator.Hardware.Door do
  @moduledoc """
  The 'Safety Boundary' of the system.
  A 5-state machine: :opening, :open, :closing, :closed, :obstructed.
  """
  use GenServer
  require Logger

  @op_ms 1000 # 1 second for opening/closing

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

  @doc "Stops the door and enters a stable OBSTRUCTED state."
  @spec obstruct(pid() | atom()) :: :ok
  def obstruct(pid \\ __MODULE__) do
    GenServer.cast(pid, :door_obstructed)
  end

  @doc "Peeks at the door state."
  @spec get_state(pid() | atom()) :: map()
  def get_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_state)
  end

  # ---------------------------------------------------------------------------
  # ## Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, map()}
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
  @spec handle_cast(:open, map()) :: {:noreply, map()}
  def handle_cast(:open, state) do
    state = 
      state
      |> cancel_timer()
      |> start_timer(:fully_opened, @op_ms)
      |> update_status(:opening)

    {:noreply, state}
  end

  @impl true
  @spec handle_cast(:close, map()) :: {:noreply, map()}
  def handle_cast(:close, state) do
    state = 
      state
      |> cancel_timer()
      |> start_timer(:fully_closed, @op_ms)
      |> update_status(:closing)

    {:noreply, state}
  end

  @impl true
  @spec handle_cast(:door_obstructed, map()) :: {:noreply, map()}
  def handle_cast(:door_obstructed, state) do
    :telemetry.execute([:elevator, :hardware, :safety, :obstruction], %{})

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
    notify_controller(state, :door_opened)
    {:noreply, %{state | status: :open, timer: nil}}
  end

  @impl true
  @spec handle_info(:fully_closed, map()) :: {:noreply, map()}
  def handle_info(:fully_closed, state) do
    notify_controller(state, :door_closed)
    {:noreply, %{state | status: :closed, timer: nil}}
  end

  @impl true
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info(msg, state) do
    Logger.warning("Door: Unexpected message #{inspect(msg)} in state: #{inspect(state)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  @spec update_status(map(), atom()) :: map()
  defp update_status(state, status) do
    :telemetry.execute([:elevator, :hardware, :safety, :door], %{status: status})
    Logger.info("Door: [State Change] Transitioned to #{status}")
    %{state | status: status}
  end

  @spec start_timer(map(), term(), integer()) :: map()
  defp start_timer(state, msg, ms) do
    timer = Process.send_after(self(), msg, ms)
    %{state | timer: timer}
  end

  @spec cancel_timer(map()) :: map()
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
