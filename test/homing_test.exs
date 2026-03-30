defmodule Elevator.HomingTest do
  @moduledoc """
  Verifies the Smart Homing logic: Persistence and Recovery.
  """
  use ExUnit.Case, async: false
  alias Elevator.{Vault, Controller}

  setup do
    # Start the Vault first
    vault_pid = start_supervised!(Vault)
    %{vault: vault_pid}
  end

  test "Smart Homing: Crash on F0 (Ground) results in Zero-Move Recovery", %{vault: vault} do
    # 1. Simulate Reality: Elevator is at F0
    Vault.put_floor(vault, 0)

    # 2. Start the Hardware with mocks
    # We use a Task to capture casts
    test_pid = self()
    motor = spawn(fn -> motor_loop(test_pid) end)
    sensor = spawn(fn -> sensor_loop(test_pid, 0) end)
    door = spawn(fn -> door_loop() end)

    # 3. Boot the Controller
    {:ok, ctrl} = Controller.start_link(
      name: :homing_controller,
      vault: vault,
      motor: motor,
      sensor: sensor,
      door: door,
      current_floor: nil # Force vault/sensor lookup
    )

    # 4. Verification
    # It should decide to skip homing move because Vault(0) == Sensor(0)
    # So we should NOT receive a :move, :down message
    refute_receive {:motor_command, {:move, :down}}, 500

    # 5. Check if it's in :normal status
    state = Controller.get_state(ctrl)
    assert state.status == :normal
    assert state.current_floor == 0
  end

  # --- Mock Helpers ---

  defp motor_loop(test_pid) do
    receive do
      {:"$gen_cast", cmd} -> 
        send(test_pid, {:motor_command, cmd})
        motor_loop(test_pid)
    end
  end

  defp sensor_loop(test_pid, floor) do
    receive do
      {:"$gen_call", from, :get_floor} ->
        GenServer.reply(from, floor)
        sensor_loop(test_pid, floor)
    end
  end

  defp door_loop do
    receive do
      _ -> door_loop()
    end
  end
end
