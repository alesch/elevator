defmodule Elevator.SensorTest do
  @moduledoc """
  Proves the Nervous System: Floor detection and Notification.
  """
  use ExUnit.Case, async: false
  alias Elevator.Sensor

  setup do
    # Start the Vault first to satisfy the dependency in Sensor.init
    # We use name: nil to avoid name collisions between parallel tests.
    vault = start_supervised!({Elevator.Vault, [name: nil]})

    # Inject self() as the controller to catch notifications locally
    pid = start_supervised!({Sensor, [current_floor: 1, vault: vault, controller: self(), name: nil]})
    %{sensor: pid, vault: vault}
  end

  test "starts at the specified floor", %{sensor: pid} do
    assert Sensor.get_floor(pid) == 1
  end

  test "motor pulse UP increments the floor", %{sensor: pid} do
    # Simulate a pulse from the Motor
    send(pid, {:motor_pulse, :up})

    # Wait for the async process (Sync peek)
    _ = Sensor.get_floor(pid)
    
    assert Sensor.get_floor(pid) == 2
  end

  test "motor pulse DOWN decrements the floor", %{sensor: _pid, vault: vault} do
    # Stop the default sensor from setup to start a new one with F3
    stop_supervised!(Sensor)
    pid = start_supervised!({Sensor, [current_floor: 3, vault: vault, controller: self(), name: nil]})

    send(pid, {:motor_pulse, :down})

    _ = Sensor.get_floor(pid)
    
    assert Sensor.get_floor(pid) == 2
  end

  test "sensor notifies the Controller upon arrival", %{sensor: pid} do
    send(pid, {:motor_pulse, :up})

    # The Sensor should notify the Controller (the test process): {:floor_arrival, 2}
    assert_receive {:floor_arrival, 2}
  end
end
