defmodule Elevator.World do
  @moduledoc """
  The physical simulation of the elevator's reality.
  Counterpart to Elevator.Core (which owns logical decisions).

  World subscribes to:
    "elevator:simulation" — clock ticks from Elevator.Time
    "elevator:hardware"   — motor events (running, crawling, stopping)

  World publishes to "elevator:hardware":
    {:floor_arrival, floor}  — elevator crossed a floor sensor
    :motor_stopped           — braking complete

  Physical constants (at 250ms/tick):
    @ticks_per_floor  running:  6  (6 × 250ms = 1500ms)
                      crawling: 18 (18 × 250ms = 4500ms)
    @brake_ticks               2  (2 × 250ms = 500ms)
  """
  use GenServer
  alias Elevator.Core

  @ticks_per_floor %{running: 6, crawling: 18}
  @brake_ticks 2

  # Physical direction: nil when stopped, :up/:down when moving.
  # Distinct from Core.direction(), which uses :idle instead of nil.
  @type direction :: :up | :down | nil

  @type t :: %{
          floor: Core.floor(),
          motor: Core.motor_status(),
          direction: direction(),
          tick_count: non_neg_integer(),
          brake_count: non_neg_integer(),
          pubsub: atom(),
          controller: pid() | atom() | nil
        }

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @doc "Starts a new World process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns the current physical state (diagnostics)."
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

    # Only subscribe to PubSub channels when running as a named (production) process.
    # Anonymous instances (tests) receive ticks and motor events via direct send.
    if Keyword.get(opts, :name) != nil do
      Phoenix.PubSub.subscribe(pubsub, "elevator:simulation")
      Phoenix.PubSub.subscribe(pubsub, "elevator:hardware")
    end

    controller = Keyword.get(opts, :controller)

    {:ok,
     %{
       floor: Keyword.get(opts, :floor, 0),
       motor: :stopped,
       direction: nil,
       tick_count: 0,
       brake_count: 0,
       pubsub: pubsub,
       controller: controller
     }}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ---------------------------------------------------------------------------
  # Motor events (from "elevator:hardware" or direct in tests)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:motor_running, direction}, state) do
    {:noreply, %{state | motor: :running, direction: direction, tick_count: 0}}
  end

  @impl true
  def handle_info({:motor_crawling, direction}, state) do
    {:noreply, %{state | motor: :crawling, direction: direction, tick_count: 0}}
  end

  @impl true
  def handle_info(:motor_stopping, state) do
    {:noreply, %{state | motor: :stopping, tick_count: 0, brake_count: 0}}
  end

  # ---------------------------------------------------------------------------
  # Tick events (from "elevator:simulation" or direct in tests)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:tick, _n}, %{motor: :stopping} = state) do
    brake_count = state.brake_count + 1

    if brake_count >= @brake_ticks do
      notify(state, :motor_stopped)
      if pid = registry_lookup(:motor), do: send(pid, :motor_stopped)
      {:noreply, %{state | motor: :stopped, direction: nil, brake_count: 0}}
    else
      {:noreply, %{state | brake_count: brake_count}}
    end
  end

  def handle_info({:tick, _n}, %{motor: status} = state) when status in [:running, :crawling] do
    tick_count = state.tick_count + 1
    threshold = @ticks_per_floor[status]

    if tick_count >= threshold do
      next_floor = advance_floor(state.floor, state.direction)
      notify(state, {:floor_arrival, next_floor})
      if pid = registry_lookup(:sensor), do: send(pid, {:floor_arrival, next_floor})
      {:noreply, %{state | floor: next_floor, tick_count: 0}}
    else
      {:noreply, %{state | tick_count: tick_count}}
    end
  end

  def handle_info({:tick, _n}, state) do
    # Motor is stopped — ticks are ignored
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    :telemetry.execute([:elevator, :world, :unexpected_message], %{}, %{message: msg})
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  @spec advance_floor(integer(), direction()) :: integer()
  defp advance_floor(floor, :up), do: floor + 1
  defp advance_floor(floor, :down), do: floor - 1

  # Notify the controller: injected pid takes priority (test isolation),
  # falling back to registry lookup, then PubSub broadcast (production).
  @spec notify(t(), term()) :: :ok
  defp notify(state, message) do
    cond do
      state.controller ->
        send(state.controller, message)

      pid = registry_lookup(:controller) ->
        send(pid, message)

      true ->
        Phoenix.PubSub.broadcast(state.pubsub, "elevator:hardware", message)
    end

    :ok
  end

  defp registry_lookup(key) do
    case Registry.lookup(Elevator.Registry, key) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end
end
