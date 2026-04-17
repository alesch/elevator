defmodule Elevator.Hardware.Door do
  @moduledoc """
  The 'Safety Boundary' of the system.
  A 5-state machine: :opening, :open, :closing, :closed, :obstructed.

  Door subscribes to "elevator:hardware" and handles commands from Controller.
  World owns the physical timing — Door announces intent immediately, then
  World counts ticks and delivers :fully_opened / :fully_closed directly.
  """
  use GenServer

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
          pubsub: atom()
        }

  # ---------------------------------------------------------------------------
  # ## Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    pubsub = Keyword.get(opts, :pubsub, Elevator.PubSub)

    if Keyword.get(opts, :name) != nil do
      {:ok, _} = Registry.register(Elevator.Registry, :door, nil)
      Phoenix.PubSub.subscribe(pubsub, "elevator:hardware")
    end

    {:ok, %{status: :closed, pubsub: pubsub}}
  end

  @impl true
  @spec handle_call(:get_state, GenServer.from(), map()) :: {:reply, map(), map()}
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ---------------------------------------------------------------------------
  # Direct casts (used by tests and the public API)
  # ---------------------------------------------------------------------------

  @impl true
  @spec handle_cast(:open, t()) :: {:noreply, t()}
  def handle_cast(:open, %{status: status} = state) when status in [:open, :opening] do
    {:noreply, handle_redundant_request(state, :open)}
  end

  def handle_cast(:open, state) do
    :telemetry.execute([:elevator, :hardware, :door, :open], %{}, %{redundant: false})
    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", :door_opening)
    {:noreply, %{state | status: :opening}}
  end

  @impl true
  @spec handle_cast(:close, t()) :: {:noreply, t()}
  def handle_cast(:close, %{status: status} = state) when status in [:closed, :closing] do
    {:noreply, handle_redundant_request(state, :close)}
  end

  def handle_cast(:close, state) do
    :telemetry.execute([:elevator, :hardware, :door, :close], %{}, %{redundant: false})
    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", :door_closing)
    {:noreply, %{state | status: :closing}}
  end

  @impl true
  @spec handle_cast(:door_obstructed, t()) :: {:noreply, t()}
  def handle_cast(:door_obstructed, state) do
    :telemetry.execute([:elevator, :hardware, :door, :obstruction], %{}, %{})
    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", :door_obstructed)
    {:noreply, %{state | status: :obstructed}}
  end

  # ---------------------------------------------------------------------------
  # Commands received from the bus (sent by Controller)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:command, :open}, %{status: status} = state) when status in [:open, :opening] do
    {:noreply, handle_redundant_request(state, :open)}
  end

  def handle_info({:command, :open}, state) do
    :telemetry.execute([:elevator, :hardware, :door, :open], %{}, %{redundant: false})
    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", :door_opening)
    {:noreply, %{state | status: :opening}}
  end

  @impl true
  def handle_info({:command, :close}, %{status: status} = state)
      when status in [:closed, :closing] do
    {:noreply, handle_redundant_request(state, :close)}
  end

  def handle_info({:command, :close}, state) do
    :telemetry.execute([:elevator, :hardware, :door, :close], %{}, %{redundant: false})
    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", :door_closing)
    {:noreply, %{state | status: :closing}}
  end

  # ---------------------------------------------------------------------------
  # Physical completion — delivered by World after tick counting
  # ---------------------------------------------------------------------------

  @impl true
  @spec handle_info(:fully_opened, map()) :: {:noreply, map()}
  def handle_info(:fully_opened, state) do
    :telemetry.execute([:elevator, :hardware, :door, :transit_complete], %{}, %{result: :open})
    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", :door_opened)
    {:noreply, %{state | status: :open}}
  end

  @impl true
  @spec handle_info(:fully_closed, map()) :: {:noreply, map()}
  def handle_info(:fully_closed, state) do
    :telemetry.execute([:elevator, :hardware, :door, :transit_complete], %{}, %{result: :closed})
    Phoenix.PubSub.broadcast_from(state.pubsub, self(), "elevator:hardware", :door_closed)
    {:noreply, %{state | status: :closed}}
  end

  # Known hardware bus traffic not relevant to Door — ignore silently.
  # These are broadcast by Motor, Sensor, and Controller on "elevator:hardware".
  @impl true
  def handle_info({:command, :move, _}, state), do: {:noreply, state}
  def handle_info({:command, :crawl, _}, state), do: {:noreply, state}
  def handle_info({:command, :stop}, state), do: {:noreply, state}
  def handle_info({:motor_running, _}, state), do: {:noreply, state}
  def handle_info({:motor_crawling, _}, state), do: {:noreply, state}
  def handle_info(:motor_stopping, state), do: {:noreply, state}
  def handle_info(:motor_stopped, state), do: {:noreply, state}
  def handle_info({:floor_arrival, _}, state), do: {:noreply, state}

  @impl true
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info(msg, state) do
    :telemetry.execute([:elevator, :hardware, :door, :unexpected_message], %{}, %{message: msg})
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  @spec handle_redundant_request(t(), atom()) :: t()
  defp handle_redundant_request(%{status: status} = state, action) do
    :telemetry.execute([:elevator, :hardware, :door, action], %{}, %{
      status: status,
      redundant: true
    })

    state
  end
end
