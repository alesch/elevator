defmodule Elevator.World do
  @moduledoc """
  The physical simulation of the elevator's reality.
  Counterpart to Elevator.Core (which owns logical decisions).

  World subscribes to:
    "elevator:simulation" — clock ticks from Elevator.Time
    "elevator:hardware"   — motor events (running, crawling, stopping)
                            door events  (opening, closing, obstructed)

  World delivers physical reality directly to hardware components via registry lookup:
    {:floor_arrival, floor} → Sensor  (Sensor then broadcasts on "elevator:hardware")
    :motor_stopped          → Motor   (Motor then broadcasts on "elevator:hardware")
    :fully_opened           → Door    (Door  then broadcasts on "elevator:hardware")
    :fully_closed           → Door    (Door  then broadcasts on "elevator:hardware")

  Test injection: pass `sensor_pid:` and `motor_pid:` opts to bypass registry lookup.

  Physical constants (at 250ms/tick):
    @ticks_per_floor         running:  6  (6 × 250ms = 1500ms)
                             crawling: 18 (18 × 250ms = 4500ms)
    @brake_ticks                       2  (2 × 250ms = 500ms)
    @ticks_per_door_transit            4  (4 × 250ms = 1000ms)
  """
  use GenServer
  alias Elevator.Core

  @ticks_per_floor %{running: 6, crawling: 18}
  @brake_ticks 2
  @ticks_per_door_transit 4

  # Physical direction: nil when stopped, :up/:down when moving.
  # Distinct from Core.direction(), which uses :idle instead of nil.
  @type direction :: :up | :down | nil

  @type t :: %{
          floor: Core.floor(),
          motor: Core.motor_status(),
          direction: direction(),
          tick_count: non_neg_integer(),
          brake_count: non_neg_integer(),
          door: :idle | :opening | :closing,
          door_tick_count: non_neg_integer(),
          pubsub: atom(),
          sensor_pid: pid() | atom() | nil,
          motor_pid: pid() | atom() | nil
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

    sensor_pid = Keyword.get(opts, :sensor_pid)
    motor_pid = Keyword.get(opts, :motor_pid)

    {:ok,
     %{
       # floor is the physical position of the elevator car
       floor: Keyword.get(opts, :floor, 0),
       motor: :stopped,
       direction: nil,
       tick_count: 0,
       brake_count: 0,
       door: :idle,
       door_tick_count: 0,
       pubsub: pubsub,
       sensor_pid: sensor_pid,
       motor_pid: motor_pid
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
  # Door events (from "elevator:hardware" or direct in tests)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:door_opening, state) do
    {:noreply, %{state | door: :opening, door_tick_count: 0}}
  end

  @impl true
  def handle_info(:door_closing, state) do
    {:noreply, %{state | door: :closing, door_tick_count: 0}}
  end

  @impl true
  def handle_info(:door_obstructed, state) do
    {:noreply, %{state | door: :idle, door_tick_count: 0}}
  end

  # ---------------------------------------------------------------------------
  # Tick events (from "elevator:simulation" or direct in tests)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:tick, _n}, %{motor: :stopping} = state) do
    brake_count = state.brake_count + 1

    motor_state =
      if brake_count >= @brake_ticks do
        send_to_motor(state, :motor_stopped)
        %{state | motor: :stopped, direction: nil, brake_count: 0}
      else
        %{state | brake_count: brake_count}
      end

    {:noreply, tick_door(motor_state)}
  end

  def handle_info({:tick, _n}, %{motor: status} = state) when status in [:running, :crawling] do
    tick_count = state.tick_count + 1
    threshold = @ticks_per_floor[status]

    motor_state =
      if tick_count >= threshold do
        next_floor = advance_floor(state.floor, state.direction)
        pid = state.sensor_pid || registry_lookup(:sensor)
        if pid, do: send(pid, {:floor_arrival, next_floor})
        %{state | floor: next_floor, tick_count: 0}
      else
        %{state | tick_count: tick_count}
      end

    {:noreply, tick_door(motor_state)}
  end

  def handle_info({:tick, _n}, state) do
    {:noreply, tick_door(state)}
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

  # Door transit tick — runs independently of motor physics on every tick.
  @spec tick_door(t()) :: t()
  defp tick_door(%{door: :idle} = state), do: state

  defp tick_door(%{door: mode, door_tick_count: count} = state) do
    new_count = count + 1

    if new_count >= @ticks_per_door_transit do
      msg = if mode == :opening, do: :fully_opened, else: :fully_closed
      if pid = registry_lookup(:door), do: send(pid, msg)
      %{state | door: :idle, door_tick_count: 0}
    else
      %{state | door_tick_count: new_count}
    end
  end

  # Send a message to Motor: injected pid takes priority (test isolation),
  # falling back to registry lookup. Motor then broadcasts on the bus.
  @spec send_to_motor(t(), term()) :: :ok
  defp send_to_motor(state, message) do
    pid = state.motor_pid || registry_lookup(:motor)
    if pid, do: send(pid, message)
    :ok
  end

  defp registry_lookup(key) do
    case Registry.lookup(Elevator.Registry, key) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end
end
