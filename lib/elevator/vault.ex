defmodule Elevator.Vault do
  @moduledoc """
  The 'Black Box' of the system.
  Preserves the last known arrival floor across crashes.
  """
  use GenServer
  require Logger

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @doc "Starts a new elevator vault process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Updates the persistent floor."
  @spec put_floor(pid() | atom(), integer() | nil) :: :ok
  def put_floor(pid \\ __MODULE__, floor) do
    GenServer.cast(pid, {:put, floor})
  end

  @doc "Fetches the persistent floor."
  @spec get_floor(pid() | atom()) :: integer() | nil
  def get_floor(pid \\ __MODULE__) do
    GenServer.call(pid, :get)
  end

  # ---------------------------------------------------------------------------
  # ## Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(opts :: keyword()) :: {:ok, integer() | nil}
  def init(opts) do
    # Register brain only if it's a named process (Supervisor/Production)
    if Keyword.get(opts, :name) != nil do
      {:ok, _} = Registry.register(Elevator.Registry, :vault, nil)
    end
    {:ok, nil}
  end

  @impl true
  @spec handle_cast({:put, integer() | nil}, any()) :: {:noreply, integer() | nil}
  def handle_cast({:put, floor}, _state) do
    {:noreply, floor}
  end

  @impl true
  @spec handle_call(:get, GenServer.from(), integer() | nil) :: {:reply, integer() | nil, integer() | nil}
  def handle_call(:get, _from, floor) do
    {:reply, floor, floor}
  end

  @impl true
  @spec handle_info(term(), any()) :: {:noreply, any()}
  def handle_info(msg, state) do
    Logger.warning("Vault: Unexpected message #{inspect(msg)} in state: #{inspect(state)}")
    {:noreply, state}
  end
end
