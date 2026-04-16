defmodule Elevator.Time do
  @moduledoc """
  The system clock.
  Ticks at a configurable rate and publishes each tick to the simulation channel.
  Schedules scaled timers for other modules — all delays are divided by the
  speed multiplier, so tests can run at e.g. 100x without waiting for real time.
  """
  use GenServer

  @default_tick_ms 250
  @default_speed 1.0

  @type t :: %{
          tick_ms: pos_integer(),
          speed: float(),
          counter: non_neg_integer(),
          pubsub: atom()
        }

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @doc "Starts a new Time process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Schedules `message` to be sent to `target` after `delay_ms` milliseconds,
  scaled by the current speed multiplier.
  Returns a timer reference that can be passed to `cancel/2`.
  """
  @spec send_after(pid() | atom(), pid(), pos_integer(), term()) :: reference()
  def send_after(pid \\ __MODULE__, target, delay_ms, message) do
    GenServer.call(pid, {:send_after, target, delay_ms, message})
  end

  @doc "Cancels a pending timer. Safe to call on an already-fired timer."
  @spec cancel(pid() | atom(), reference()) :: :ok
  def cancel(_pid \\ __MODULE__, ref) do
    Process.cancel_timer(ref)
    :ok
  end

  @doc "Returns the current internal state (diagnostics)."
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
    if Keyword.get(opts, :name) != nil do
      {:ok, _} = Registry.register(Elevator.Registry, :time, nil)
    end

    tick_ms = Keyword.get(opts, :tick_ms, @default_tick_ms)

    default_speed =
      if Keyword.get(opts, :name) != nil,
        do: Application.get_env(:elevator, :time_speed, @default_speed),
        else: @default_speed

    speed = Keyword.get(opts, :speed, default_speed)
    pubsub = Keyword.get(opts, :pubsub, Elevator.PubSub)

    state = %{
      tick_ms: tick_ms,
      speed: speed,
      counter: 0,
      pubsub: pubsub
    }

    schedule_tick(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:send_after, target, delay_ms, message}, _from, state) do
    scaled_ms = round(delay_ms / state.speed)
    ref = Process.send_after(target, message, scaled_ms)
    {:reply, ref, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:tick, state) do
    counter = state.counter + 1
    Phoenix.PubSub.broadcast(state.pubsub, "elevator:simulation", {:tick, counter})
    new_state = %{state | counter: counter}
    schedule_tick(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    :telemetry.execute([:elevator, :time, :unexpected_message], %{}, %{message: msg})
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  @spec schedule_tick(t()) :: reference()
  defp schedule_tick(%{tick_ms: tick_ms, speed: speed}) do
    scaled_ms = round(tick_ms / speed)
    Process.send_after(self(), :tick, scaled_ms)
  end
end
