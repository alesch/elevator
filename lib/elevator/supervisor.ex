defmodule Elevator.Supervisor do
  @moduledoc """
  The 'Fortress' of the building.
  Guarantees system integrity through a :one_for_all restart strategy.
  """
  use Supervisor
  alias Elevator.{Controller, Door, Motor, Sensor}

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    # Top-level: One For One
    # If the Hardware stack dies, we don't reboot the Vault.
    children = [
      {Elevator.Vault, [name: Vault]},
      {Supervisor, [strategy: :one_for_all, name: HardwareStack, children: hardware_children()]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp hardware_children do
    [
      # The Physical Muscle (Motor needs to know the Sensor)
      {Motor, [sensor: Sensor, name: Motor]},

      # The Nervous System (Sensor needs to know the Controller)
      {Sensor, [current_floor: 1, controller: Controller, name: Sensor]},

      # The Safety Boundary (Door needs to know the Controller)
      {Door, [controller: Controller, name: Door]},

      # The Orchestrator (The Brain - needs to know Motor and Door)
      {Controller, [current_floor: 1, name: Controller, motor: Motor, door: Door]}
    ]
  end
end
