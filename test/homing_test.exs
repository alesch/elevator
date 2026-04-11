defmodule Elevator.HomingTest do
  @moduledoc """
  Verifies the Smart Homing logic using Real Components (No manual mocks).
  """
  use ExUnit.Case, async: false
  alias Elevator.{Controller, Core, Vault}
  alias Elevator.Hardware.{Door, Motor, Sensor}

  setup do
    # Start the Vault first with a unique name
    vault = start_supervised!({Vault, [name: nil]})
    %{vault: vault}
  end

  test "[S-HOME-ZERO]: Smart Homing - Crash on F0 (Ground) results in Zero-Move Recovery", %{
    vault: vault
  } do
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
    send(ctrl, {:recovery_complete, 0})
    _ = Controller.get_state(ctrl)

    state = Controller.get_state(ctrl)
    assert Core.phase(state) == :idle
    assert Core.current_floor(state) == 0

    # Motor should still be stopped
    assert Motor.get_state(motor).status == :stopped
  end

  test "[S-HOME-MOVE]: Smart Homing - Mid-floor crash results in Physical Homing", %{vault: vault} do
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

    # Controller should be :rehoming (auto-triggered by mismatch)
    state = Controller.get_state(ctrl)
    assert Core.phase(state) == :rehoming

    # Motor should be moving :down at :crawling speed
    motor_state = Motor.get_state(motor)
    assert motor_state.status == :crawling
    assert motor_state.direction == :down
  end

  test "[S-HOME-COLD] & [S-HOME-ANCHOR]: Smart Homing - Cold Start (Vault empty) results in Physical Homing and Anchoring",
       %{
         vault: vault
       } do
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
    state = Controller.get_state(ctrl)
    assert Core.phase(state) == :rehoming
    assert Motor.get_state(motor).status == :crawling
    
    # Ingest reality: motor is actually crawling now
    send(ctrl, :motor_crawling)
    assert Core.motor_status(Controller.get_state(ctrl)) == :crawling

    # 3. [S-HOME-ANCHOR]: Floor arrival during rehoming — anchor (brake), phase stays :rehoming
    send(ctrl, {:floor_arrival, 0})
    _ = Controller.get_state(ctrl)
    _ = Vault.get_floor(vault)

    state = Controller.get_state(ctrl)
    assert Core.phase(state) == :rehoming
    assert state.hardware.current_floor == 0
    # Reality: still crawling until stopped confirmation processed
    assert state.hardware.motor_status == :crawling
    assert Vault.get_floor(vault) == 0

    # Wait for physical braking to complete (500ms + buffer)
    Process.sleep(600)
    assert Motor.get_state(motor).status == :stopped

    # 4. [S-HOME-NO-DOOR]: Motor confirms stopped — phase transitions to :idle, no door cycle
    send(ctrl, :motor_stopped)
    _ = Controller.get_state(ctrl)

    state = Controller.get_state(ctrl)
    assert Core.phase(state) == :idle
    assert state.door_status == :closed
  end

  @tag :capture_log
  test "[S-HOME-BLOCK-REQ]: Smart Homing - Requests are ignored during rehoming", %{vault: vault} do
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
    assert Core.phase(Controller.get_state(ctrl)) == :rehoming

    # 2. Send a request
    Controller.request_floor(ctrl, :car, 2)

    # 3. Verify it was ignored
    state = Controller.get_state(ctrl)
    assert Core.requests(state) == []
    assert Core.phase(state) == :rehoming
  end
end
