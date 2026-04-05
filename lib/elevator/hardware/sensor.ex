defmodule Elevator.Hardware.Sensor do
  @moduledoc """
  The 'Nervous System' of the building.
  It listens for physical 'Motor Pulses' and emits logical 'Floor Arrivals.'
  """
  use GenServer
  require Logger

  defstruct [:current_floor, :controller]

  @type t :: %__MODULE__{
          current_floor: integer(),
          controller: pid() | atom() | nil
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
    # Register brain only if it's a named process (Supervisor/Production)
    if Keyword.get(opts, :name) != nil do
      {:ok, _} = Registry.register(Elevator.Registry, :sensor, nil)
    end

    # 1. Recover physical floor from the Vault
    vault = Keyword.get(opts, :vault)
    vault_floor = get_initial_floor(vault)

    # 2. Handle final bootstrap state
    floor = vault_floor || Keyword.get(opts, :current_floor, 0)
    controller = Keyword.get(opts, :controller)

    :telemetry.execute([:elevator, :hardware, :sensor, :init], %{}, %{
      floor: floor,
      recovered: not is_nil(vault_floor)
    })

    {:ok, %__MODULE__{current_floor: floor, controller: controller}}
  end

  @impl true
  @spec handle_call(:get_floor, GenServer.from(), t()) :: {:reply, integer() | :unknown, t()}
  def handle_call(:get_floor, _from, %{current_floor: floor} = state) do
    {:reply, floor, state}
  end

  @impl true
  @spec handle_info({:motor_pulse, :up | :down}, t()) :: {:noreply, t()}
  def handle_info({:motor_pulse, direction}, %{current_floor: current} = state) do
    # Calculate new floor based on physical direction pulse
    next_floor = calculate_next_floor(current, direction)

    :telemetry.execute([:elevator, :hardware, :sensor, :arrival], %{}, %{floor: next_floor})

    # Notify the Brain (Controller)
    notify_controller(state, next_floor)

    {:noreply, %{state | current_floor: next_floor}}
  end

  @impl true
  @spec handle_info(term(), t()) :: {:noreply, t()}
  def handle_info(msg, state) do
    Logger.warning("Sensor: Unexpected message #{inspect(msg)} in state: #{inspect(state)}")

    :telemetry.execute([:elevator, :hardware, :sensor, :unexpected_message], %{}, %{
      message: msg,
      state: state
    })

    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  @spec calculate_next_floor(integer(), :up | :down) :: integer()
  defp calculate_next_floor(current, :up), do: current + 1
  defp calculate_next_floor(current, :down), do: current - 1

  defp get_initial_floor(vault) do
    target = vault || lookup_vault()
    if target, do: Elevator.Vault.get_floor(target), else: nil
  end

  @spec notify_controller(t(), integer()) :: :ok
  defp notify_controller(state, floor) do
    target = state.controller || lookup_controller()

    if target do
      send(target, {:floor_arrival, floor})
    else
      :telemetry.execute([:elevator, :hardware, :sensor, :notification_failure], %{}, %{
        target: :controller,
        floor: floor
      })

      :ok
    end
  end

  defp lookup_vault do
    case Registry.lookup(Elevator.Registry, :vault) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end

  defp lookup_controller do
    case Registry.lookup(Elevator.Registry, :controller) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end
end
