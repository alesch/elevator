defmodule Elevator.Sensor do
  @moduledoc """
  The 'Nervous System' of the building.
  It listens for physical 'Motor Pulses' and emits logical 'Floor Arrivals.'
  """
  use GenServer
  require Logger

  # --- API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Peeks at the current sensor floor."
  def get_floor(pid \\ __MODULE__) do
    GenServer.call(pid, :get_floor)
  end

  # --- Callbacks ---

  def init(opts) do
    # 1. Recover vault dependency
    vault = Keyword.get(opts, :vault, Elevator.Vault)

    # 2. Try to recover floor from the Vault
    vault_floor = Elevator.Vault.get_floor(vault)

    # 3. Handle state
    floor = vault_floor || Keyword.get(opts, :current_floor, 1)
    controller = Keyword.get(opts, :controller)
    {:ok, %{current_floor: floor, controller: controller, vault: vault}}
  end

  def handle_call(:get_floor, _from, %{current_floor: floor} = state) do
    {:reply, floor, state}
  end

  def handle_info({:motor_pulse, direction}, %{current_floor: current} = state) do
    # Calculate the new floor based on the physical direction pulse
    next_floor = calculate_next_floor(current, direction)

    Logger.info("Sensor: [Box Arrival] Detected at Floor #{next_floor}")

    # Notify the Controller (The Brain)
    notify_controller(state, next_floor)

    {:noreply, %{state | current_floor: next_floor}}
  end

  # --- Private Helpers ---

  defp calculate_next_floor(current, :up), do: current + 1
  defp calculate_next_floor(current, :down), do: current - 1

  defp notify_controller(%{controller: nil}, _floor), do: :ok
  defp notify_controller(%{controller: controller}, floor) do
    # Message: {:floor_arrival, floor} (As per PROTOCOL_SPEC)
    send(controller, {:floor_arrival, floor})
  end
end
