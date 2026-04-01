defmodule Elevator.Hardware.Motor do
  @moduledoc """
  The 'Dumb Muscle' of the system.
  It pulls cables indefinitely until told to stop.
  """
  use GenServer
  require Logger

  # 2 seconds per floor
  @transit_ms 2000

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @doc "Starts a new elevator motor process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Starts pulling cables in the specified direction."
  @spec move(pid() | atom(), :up | :down, keyword()) :: :ok
  def move(pid \\ __MODULE__, direction, opts \\ []) when direction in [:up, :down] do
    GenServer.cast(pid, {:move, direction, opts})
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
       speed: :normal,
       timer: nil,
       sensor: sensor,
       controller: controller
     }}
  end

  @impl true
  @spec handle_cast({:move, :up | :down, keyword()}, map()) :: {:noreply, map()}
  def handle_cast({:move, direction, opts}, state) do
    speed = Keyword.get(opts, :speed, :normal)

    :telemetry.execute([:elevator, :hardware, :motor, :move], %{}, %{
      direction: direction,
      speed: speed
    })

    state =
      state
      |> cancel_timer()
      |> update_motion_state(:moving, direction, speed)
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
      |> update_motion_state(:stopped, nil, :normal)

    notify_controller(state, :motor_stopped)
    {:noreply, state}
  end

  @impl true
  @spec handle_call(:get_state, GenServer.from(), map()) :: {:reply, map(), map()}
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
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

  @spec update_motion_state(map(), :moving | :stopped, :up | :down | nil, :normal | :slow) ::
          map()
  defp update_motion_state(state, status, direction, speed) do
    %{state | status: status, direction: direction, speed: speed}
  end

  @spec start_transit_timer(map()) :: map()
  defp start_transit_timer(%{direction: direction, speed: speed} = state) do
    ms =
      case speed do
        :slow -> 5000
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
