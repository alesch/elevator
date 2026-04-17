defmodule Elevator.Hardware.Sensor do
  @moduledoc """
  The 'Nervous System' of the building.
  A passive floor memory: it tracks the elevator's position by listening
  for {:floor_arrival, floor} events from World.
  World is the authoritative source of floor crossings.
  """
  use GenServer

  defstruct [:current_floor, :pubsub]

  @type t :: %__MODULE__{
          current_floor: integer(),
          pubsub: atom()
        }

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @doc "Starts a new elevator sensor process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Peeks at the current sensor floor."
  @spec get_floor(pid() | atom()) :: integer() | :unknown
  def get_floor(pid \\ __MODULE__) do
    GenServer.call(pid, :get_floor)
  end

  # ---------------------------------------------------------------------------
  # ## Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, t()} | {:stop, term()}
  def init(opts) do
    pubsub = Keyword.get(opts, :pubsub, Elevator.PubSub)

    if Keyword.get(opts, :name) != nil do
      {:ok, _} = Registry.register(Elevator.Registry, :sensor, nil)
    end

    vault = Keyword.get(opts, :vault)
    vault_floor = get_initial_floor(vault)

    floor = vault_floor || Keyword.get(opts, :current_floor, 0)

    :telemetry.execute([:elevator, :hardware, :sensor, :init], %{}, %{
      floor: floor,
      recovered: not is_nil(vault_floor)
    })

    {:ok, %__MODULE__{current_floor: floor, pubsub: pubsub}}
  end

  @impl true
  @spec handle_call(:get_floor, GenServer.from(), t()) :: {:reply, integer() | :unknown, t()}
  def handle_call(:get_floor, _from, %{current_floor: floor} = state) do
    {:reply, floor, state}
  end

  @impl true
  @spec handle_info({:floor_arrival, integer()}, t()) :: {:noreply, t()}
  def handle_info({:floor_arrival, floor}, state) do
    :telemetry.execute([:elevator, :hardware, :sensor, :arrival], %{}, %{floor: floor})
    Phoenix.PubSub.broadcast(state.pubsub, "elevator:hardware", {:floor_arrival, floor})
    {:noreply, %{state | current_floor: floor}}
  end

  @impl true
  @spec handle_info(term(), t()) :: {:noreply, t()}
  def handle_info(msg, state) do
    :telemetry.execute([:elevator, :hardware, :sensor, :unexpected_message], %{}, %{message: msg})
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  defp get_initial_floor(vault) do
    target = vault || lookup_vault()
    if target, do: Elevator.Vault.get_floor(target), else: nil
  end

  defp lookup_vault do
    case Registry.lookup(Elevator.Registry, :vault) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end
end
