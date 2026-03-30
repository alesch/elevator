defmodule ElevatorWeb.Telemetry do
  @moduledoc """
  The Telemetry Bridge for the Elevator.
  Defines the metrics and events that make our industrial system 'Observable.'
  """
  use Supervisor
  import Telemetry.Metrics

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @doc "Starts the Telemetry supervision tree."
  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  @spec init(term()) :: {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init(_arg) do
    children = [
      # Telemetry poller for VM/OS stats
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add custom metric storage here if using StatsD or Prometheus
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Exposes the industrial metrics we wish to track."
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      # Hardware Metrics
      counter("elevator.hardware.pulse.count", description: "Total floor transit pulses"),
      last_value("elevator.hardware.door.state", description: "Current door binary state"),

      # Safety Metrics
      counter("elevator.safety.overload.count", description: "Total overload events"),

      # VM Metrics
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      )
    ]
  end

  # ---------------------------------------------------------------------------
  # ## Private Helpers
  # ---------------------------------------------------------------------------

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/2.
      # {ElevatorWeb, :count_users, []}
    ]
  end
end
