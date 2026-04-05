defmodule Elevator.Hardware.Motor do
  @moduledoc """
  The 'Dumb Muscle' of the system.
  It pulls cables indefinitely until told to stop.
  """
  use GenServer
  require Logger

  # 1.5 seconds between floors (Leaving 500ms for braking to reach 2s total)
  @transit_ms 1500
  # 500ms delay for physical braking
  @brake_ms 500

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @doc "Starts a new elevator motor process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Starts pulling cables in the specified direction at normal speed."
  @spec move(pid() | atom(), :up | :down) :: :ok
  def move(pid \\ __MODULE__, direction) when direction in [:up, :down] do
    GenServer.cast(pid, {:move, direction})
  end

  @doc "Starts pulling cables in the specified direction at slow speed."
  @spec crawl(pid() | atom(), :up | :down) :: :ok
  def crawl(pid \\ __MODULE__, direction) when direction in [:up, :down] do
    GenServer.cast(pid, {:crawl, direction})
  end

  @doc "Stops all motion immediately."
  @spec stop(pid() | atom()) :: :ok
  def stop(pid \\ __MODULE__) do
    GenServer.cast(pid, :stop_now)
  end

  @doc "Peeks at the internal state (Diagnostics)."
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
    # Only register in the global registry if a name was provided (Production/Supervisor)
    # Unit tests often start anonymous processes that should not collide.
    if Keyword.get(opts, :name) != nil do
      {:ok, _} = Registry.register(Elevator.Registry, :motor, nil)
    end

    # Keep track of dependencies if injected (Testing), else fallback to discovery (Prod)
    sensor = Keyword.get(opts, :sensor)
    controller = Keyword.get(opts, :controller)

    {:ok,
     %{
       status: :stopped,
       direction: nil,
       timer: nil,
       sensor: sensor,
       controller: controller
     }}
  end

  @impl true
  @spec handle_cast({:move, :up | :down}, map()) :: {:noreply, map()}
  def handle_cast({:move, direction}, state) do
    :telemetry.execute([:elevator, :hardware, :motor, :move], %{}, %{
      direction: direction,
      speed: :normal
    })

    state =
      state
      |> cancel_timer()
      |> update_motion_state(:running, direction)
      |> start_transit_timer()

    {:noreply, state}
  end

  @impl true
  @spec handle_cast({:crawl, :up | :down}, map()) :: {:noreply, map()}
  def handle_cast({:crawl, direction}, state) do
    :telemetry.execute([:elevator, :hardware, :motor, :move], %{}, %{
      direction: direction,
      speed: :slow
    })

    state =
      state
      |> cancel_timer()
      |> update_motion_state(:crawling, direction)
      |> start_transit_timer()

    {:noreply, state}
  end

  @impl true
  @spec handle_cast(:stop_now, map()) :: {:noreply, map()}
  def handle_cast(:stop_now, %{status: status} = state) when status in [:stopped, :stopping] do
    Logger.warning("Hardware: Redundant Motor Stop request while already #{inspect(status)}")
    {:noreply, state}
  end

  def handle_cast(:stop_now, state) do
    :telemetry.execute([:elevator, :hardware, :motor, :stop], %{}, %{})

    state =
      state
      |> cancel_timer()
      |> update_motion_state(:stopping, state.direction)
      |> start_brake_timer()

    {:noreply, state}
  end


  @impl true
  @spec handle_call(:get_state, GenServer.from(), map()) :: {:reply, map(), map()}
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  @spec handle_info(:brake_complete, map()) :: {:noreply, map()}
  def handle_info(:brake_complete, state) do
    state = %{update_motion_state(state, :stopped, nil) | timer: nil}
    notify_controller(state, :motor_stopped)
    {:noreply, state}
  end

  @impl true
  @spec handle_info({:pulse, :up | :down}, map()) :: {:noreply, map()}
  def handle_info({:pulse, direction}, state) do
    :telemetry.execute([:elevator, :hardware, :motor, :pulse], %{}, %{direction: direction})
    notify_sensor(state, direction)
    {:noreply, start_transit_timer(state)}
  end

  @impl true
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info(msg, state) do
    Logger.warning("Motor: Unexpected message #{inspect(msg)} in state: #{inspect(state)}")
    {:noreply, state}
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

  @spec update_motion_state(map(), :running | :crawling | :stopping | :stopped, :up | :down | nil) ::
          map()
  defp update_motion_state(state, status, direction) do
    %{state | status: status, direction: direction}
  end

  @spec start_brake_timer(map()) :: map()
  defp start_brake_timer(state) do
    timer = Process.send_after(self(), :brake_complete, @brake_ms)
    %{state | timer: timer}
  end

  @spec start_transit_timer(map()) :: map()
  defp start_transit_timer(%{status: status, direction: direction} = state) do
    ms =
      case status do
        :crawling -> 4500
        _ -> @transit_ms
      end

    timer = Process.send_after(self(), {:pulse, direction}, ms)
    %{state | timer: timer}
  end

  @spec cancel_timer(map()) :: map()
  defp cancel_timer(%{timer: nil} = state), do: state

  defp cancel_timer(%{timer: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timer: nil}
  end

  @spec notify_sensor(map(), :up | :down) :: :ok
  defp notify_sensor(state, direction) do
    # 1. Try injected reference first (The Test Way)
    # 2. Falling back to logical discovery (The Industrial Way)
    target = state.sensor || lookup_sensor()
    if target, do: send(target, {:motor_pulse, direction}), else: :ok
  end

  defp lookup_sensor do
    case Registry.lookup(Elevator.Registry, :sensor) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end
end
