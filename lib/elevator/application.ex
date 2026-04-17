defmodule Elevator.Application do
  @moduledoc """
  The Application entry point for the Elevator system.
  Manages the root supervision tree, including discovery, persistence,
  and the hardware stack.
  """
  use Application

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @impl true
  @spec start(Application.start_type(), any()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    # Discovery and Observability Layer must be first.
    children =
      [
        # 1. Industrial Discovery Layer
        {Registry, [keys: :unique, name: Elevator.Registry]},

        # 2. Industrial Monitoring (Telemetry)
        {ElevatorWeb.Telemetry, []},
        {Elevator.TelemetryLogger, []},

        # 3. Messaging Bridge
        {Phoenix.PubSub, [name: Elevator.PubSub]},

        # 4. Persistence Layer (Vault)
        {Elevator.Vault, [name: Elevator.Vault]},

        # 5. Virtual Clock
        {Elevator.Time, [name: Elevator.Time]}
      ] ++ hardware_profile()

    opts = [strategy: :one_for_one, name: Elevator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  @spec config_change(keyword(), keyword(), [atom()]) :: :ok
  def config_change(changed, _new, removed) do
    ElevatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  @spec hardware_profile() :: [module() | Supervisor.child_spec()]
  defp hardware_profile do
    # We avoid Mix.env() runtime switches by defining our profile explicitly.
    # In a production environment, this could be driven by Application.get_env/2.
    case Application.fetch_env!(:elevator, :hardware_stack_enabled) do
      true -> [Elevator.HardwareSupervisor, ElevatorWeb.Endpoint]
      false -> []
    end
  end
end
