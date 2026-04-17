defmodule Elevator.Hardware.Motor do
  @moduledoc """
  The 'Dumb Muscle' of the system.
  Pulls cables in a direction until told to stop.
  Publishes motor status events to "elevator:hardware".
  World owns the physical timing — Motor just broadcasts its intent.
  """
  use GenServer

  @type t :: %{
          status: :stopped | :running | :crawling | :stopping,
          direction: :up | :down | nil,
          pubsub: atom()
        }

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

  @doc "Begins the stopping sequence."
  @spec stop(pid() | atom()) :: :ok
  def stop(pid \\ __MODULE__) do
    GenServer.cast(pid, :stop_now)
  end

  @doc "Peeks at the internal state (Diagnostics)."
  @spec get_state(pid() | atom()) :: t()
  def get_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_state)
  end

  # ---------------------------------------------------------------------------
  # ## Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    pubsub = Keyword.get(opts, :pubsub, Elevator.PubSub)

    if Keyword.get(opts, :name) != nil do
      {:ok, _} = Registry.register(Elevator.Registry, :motor, nil)
      Phoenix.PubSub.subscribe(pubsub, "elevator:hardware")
    end

    {:ok, %{status: :stopped, direction: nil, pubsub: pubsub}}
  end

  @impl true
  def handle_cast({:move, direction}, state) do
    :telemetry.execute([:elevator, :hardware, :motor, :move], %{}, %{
      direction: direction,
      speed: :running
    })

    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", {:motor_running, direction})
    {:noreply, %{state | status: :running, direction: direction}}
  end

  @impl true
  def handle_cast({:crawl, direction}, state) do
    :telemetry.execute([:elevator, :hardware, :motor, :move], %{}, %{
      direction: direction,
      speed: :crawling
    })

    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", {:motor_crawling, direction})
    {:noreply, %{state | status: :crawling, direction: direction}}
  end

  def handle_cast(:stop_now, %{status: status} = state) when status in [:stopped, :stopping] do
    :telemetry.execute([:elevator, :hardware, :motor, :stop], %{}, %{
      status: status,
      redundant: true
    })

    {:noreply, state}
  end

  def handle_cast(:stop_now, state) do
    :telemetry.execute([:elevator, :hardware, :motor, :stop], %{}, %{})
    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", :motor_stopping)
    {:noreply, %{state | status: :stopping}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # Commands received from the bus (sent by Controller)

  @impl true
  def handle_info({:command, :move, direction}, state) do
    :telemetry.execute([:elevator, :hardware, :motor, :move], %{}, %{
      direction: direction,
      speed: :running
    })

    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", {:motor_running, direction})
    {:noreply, %{state | status: :running, direction: direction}}
  end

  @impl true
  def handle_info({:command, :crawl, direction}, state) do
    :telemetry.execute([:elevator, :hardware, :motor, :move], %{}, %{
      direction: direction,
      speed: :crawling
    })

    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", {:motor_crawling, direction})
    {:noreply, %{state | status: :crawling, direction: direction}}
  end

  @impl true
  def handle_info({:command, :stop}, %{status: status} = state) when status in [:stopped, :stopping] do
    :telemetry.execute([:elevator, :hardware, :motor, :stop], %{}, %{
      status: status,
      redundant: true
    })

    {:noreply, state}
  end

  def handle_info({:command, :stop}, state) do
    :telemetry.execute([:elevator, :hardware, :motor, :stop], %{}, %{})
    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", :motor_stopping)
    {:noreply, %{state | status: :stopping}}
  end

  # World signals braking is complete; Motor announces on bus and updates state.

  @impl true
  def handle_info(:motor_stopped, state) do
    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", :motor_stopped)
    {:noreply, %{state | status: :stopped, direction: nil}}
  end

  @impl true
  def handle_info(msg, state) do
    :telemetry.execute([:elevator, :hardware, :motor, :unexpected_message], %{}, %{message: msg})
    {:noreply, state}
  end
end
