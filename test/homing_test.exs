defmodule Elevator.HomingTest do
  @moduledoc """
  Verifies the Smart Homing logic using Real Components (No manual mocks).
  """
  use ExUnit.Case, async: false
  alias Elevator.{Vault, Controller}
  alias Elevator.Hardware.{Motor, Sensor, Door}

  setup do
    # Start the Vault first with a unique name
    vault = start_supervised!({Vault, [name: nil]})
    %{vault: vault}
  end

  test "Smart Homing: Crash on F0 (Ground) results in Zero-Move Recovery", %{vault: vault} do
    # 1. Simulate Reality: Vault knows F0, and Sensor sees F0
    Vault.put_floor(vault, 0)

    # 2. Start hardware stack
    motor = start_supervised!({Motor, [name: nil]})
    sensor = start_supervised!({Sensor, [vault: vault, current_floor: 0, name: nil]})
    door = start_supervised!({Door, [name: nil]})

    # 3. Boot the Controller
    {:ok, ctrl} =
      Controller.start_link(
        vault: vault,
        motor: motor,
        sensor: sensor,
        door: door,
        name: nil
      )

    # 4. Verification (State-Based)
    # Give it a millisecond for handle_continue to finish
    _ = Controller.get_state(ctrl)

    state = Controller.get_state(ctrl)
    assert state.status == :normal
    assert state.current_floor == 0

    # Motor should still be stopped
    assert Motor.get_state(motor).status == :stopped
  end

  test "Smart Homing: Mid-floor crash results in Physical Homing", %{vault: vault} do
    # 1. Vault knows F3
    Vault.put_floor(vault, 3)

    motor = start_supervised!({Motor, [name: nil]})
    # 2. Force Sensor to be at a DIFFERENT floor (F1) to simulate physical movement
    sensor = start_supervised!({Sensor, [vault: nil, current_floor: 1, name: nil]})
    door = start_supervised!({Door, [name: nil]})

    {:ok, ctrl} =
      Controller.start_link(
        vault: vault,
        motor: motor,
        sensor: sensor,
        door: door,
        name: nil
      )

    # 3. Verification
    _ = Controller.get_state(ctrl)

    # Controller should be :rehoming
    state = Controller.get_state(ctrl)
    assert state.status == :rehoming

    # Motor should be moving :down at :slow speed
    motor_state = Motor.get_state(motor)
    assert motor_state.status == :moving
    assert motor_state.direction == :down
    assert motor_state.speed == :slow
  end

  test "Smart Homing: Cold Start (Vault empty) results in Physical Homing", %{vault: vault} do
    # 1. Vault is empty (never used)

    motor = start_supervised!({Motor, [name: nil]})
    # Defaults to F1
    sensor = start_supervised!({Sensor, [vault: vault, name: nil]})
    door = start_supervised!({Door, [name: nil]})

    {:ok, ctrl} =
      Controller.start_link(
        vault: vault,
        motor: motor,
        sensor: sensor,
        door: door,
        name: nil
      )

    # 2. Verification
    _ = Controller.get_state(ctrl)
    assert Controller.get_state(ctrl).status == :rehoming
    assert Motor.get_state(motor).speed == :slow

    # 3. Simulating arrival at Floor 0 to finish homing
    send(ctrl, {:floor_arrival, 0})

    # Give it a tiny bit to process the message
    _ = Controller.get_state(ctrl)

    state = Controller.get_state(ctrl)
    assert state.status == :normal
    assert state.current_floor == 0
    assert Vault.get_floor(vault) == 0
  end

  @tag :capture_log
  test "Smart Homing: Requests are ignored during rehoming", %{vault: vault} do
    # 1. Force rehoming status
    motor = start_supervised!({Motor, [name: nil]})
    sensor = start_supervised!({Sensor, [vault: vault, current_floor: nil, name: nil]})
    door = start_supervised!({Door, [name: nil]})

    {:ok, ctrl} =
      Controller.start_link(
        vault: vault,
        motor: motor,
        sensor: sensor,
        door: door,
        name: nil
      )

    _ = Controller.get_state(ctrl)
    assert Controller.get_state(ctrl).status == :rehoming

    # 2. Send a request
    Controller.request_floor(ctrl, :car, 2)

    # 3. Verify it was ignored
    state = Controller.get_state(ctrl)
    assert state.requests == []
    assert state.status == :rehoming
  end
end
