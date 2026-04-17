defmodule Elevator.HardwareSupervisor do
  @moduledoc """
  Manages the physical elevator components with a :one_for_all strategy.
  If any hardware actor crashes, we reboot the entire stack to ensure
  logical consistency between the brain (Controller) and the limbs.
  """
  use Supervisor

  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  @spec init(any()) :: {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init(_init_arg) do
    # Individual components discover each other via Registry.
    # No more manual PID injection at startup.
    children = [
      # 1. The Physical Simulation
      {Elevator.World, [name: Elevator.World, floor: 1]},

      # 2. The Physical Muscle
      {Elevator.Hardware.Motor, [name: Elevator.Hardware.Motor]},

      # 3. The Nervous System
      {Elevator.Hardware.Sensor, [current_floor: 0, name: Elevator.Hardware.Sensor]},

      # 4. The Safety Boundary
      {Elevator.Hardware.Door, [name: Elevator.Hardware.Door]},

      # 5. The Orchestrator (The Brain)
      {Elevator.Controller, [name: Elevator.Controller]}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
