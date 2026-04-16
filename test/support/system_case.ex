defmodule Elevator.SystemCase do
  @moduledoc """
  Test helper that starts the hardware stack under ExUnit's supervised process
  tree, wiring it into the Vault, Time, and World already running from the
  Application.

  All components register in Elevator.Registry under their standard keys,
  exactly as in production. Time runs at the speed configured in test.exs
  (default 1000.0×) so the full scenario completes in milliseconds.

  Options:
    * `:vault_floor`  — floor pre-seeded in the Vault (default: `0`)
    * `:sensor_floor` — starting floor reported by the Sensor (default: `0`)
  """

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  alias Elevator.Vault
  alias Elevator.Hardware.{Motor, Sensor, Door}
  alias Elevator.Controller

  @spec start_system(keyword()) :: :ok
  def start_system(opts \\ []) do
    vault_floor = Keyword.get(opts, :vault_floor, 0)
    sensor_floor = Keyword.get(opts, :sensor_floor, 0)

    Vault.put_floor(Vault, vault_floor)

    start_supervised!({Motor, [name: Motor]})
    start_supervised!({Sensor, [name: Sensor, current_floor: sensor_floor]})
    start_supervised!({Door, [name: Door]})
    start_supervised!({Controller, [name: Controller]})

    :ok
  end
end
