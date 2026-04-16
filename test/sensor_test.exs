defmodule Elevator.SensorTest do
  @moduledoc """
  Proves Sensor is a passive floor tracker.
  It updates its floor when it receives {:floor_arrival, floor} from World.
  No controller notification — World notifies Controller directly.
  """
  use ExUnit.Case, async: true

  alias Elevator.Hardware.Sensor

  setup do
    vault = start_supervised!({Elevator.Vault, [name: nil]})
    pid = start_supervised!({Sensor, [current_floor: 1, vault: vault, name: nil]})
    %{sensor: pid}
  end

  test "[S-HW-SENSOR]: starts at the specified floor", %{sensor: pid} do
    assert Sensor.get_floor(pid) == 1
  end

  test "[S-HW-SENSOR]: floor_arrival updates the tracked floor upward", %{sensor: pid} do
    send(pid, {:floor_arrival, 2})
    _ = Sensor.get_floor(pid)
    assert Sensor.get_floor(pid) == 2
  end

  test "[S-HW-SENSOR]: floor_arrival updates the tracked floor downward", %{sensor: _pid} do
    vault = start_supervised!({Elevator.Vault, [name: nil]}, id: :vault2)

    pid =
      start_supervised!({Sensor, [current_floor: 3, vault: vault, name: nil]}, id: :sensor2)

    send(pid, {:floor_arrival, 2})
    _ = Sensor.get_floor(pid)
    assert Sensor.get_floor(pid) == 2
  end

  test "[S-HW-SENSOR]: consecutive arrivals update floor each time", %{sensor: pid} do
    send(pid, {:floor_arrival, 2})
    _ = Sensor.get_floor(pid)
    send(pid, {:floor_arrival, 3})
    _ = Sensor.get_floor(pid)
    assert Sensor.get_floor(pid) == 3
  end
end
