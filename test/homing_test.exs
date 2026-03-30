defmodule Elevator.HomingTest do
  @moduledoc """
  Verifies the Smart Homing logic: Persistence and Recovery.
  """
  use ExUnit.Case, async: false
  alias Elevator.{Vault, Controller}

  setup do
    vault = start_supervised!({Vault, [name: nil]})
    %{vault: vault}
  end

  test "Smart Homing: Crash on F0 (Ground) results in Zero-Move Recovery", %{vault: vault} do
    Vault.put_floor(vault, 0)

    test_pid = self()
    motor = spawn_link(fn -> motor_loop(test_pid) end)
    sensor = spawn_link(fn -> static_sensor_loop(0) end)
    door = spawn_link(fn -> door_loop() end)

    {:ok, ctrl} = Controller.start_link(
      vault: vault, motor: motor, sensor: sensor, door: door, name: nil
    )

    refute_receive {:motor_command, {:move, :down, _}}, 500

    state = Controller.get_state(ctrl)
    assert state.status == :normal
    assert state.current_floor == 0
  end

  test "Smart Homing: Mid-floor crash results in Physical Homing", %{vault: vault} do
    Vault.put_floor(vault, 3)

    test_pid = self()
    motor = spawn_link(fn -> motor_loop(test_pid) end)
    sensor = spawn_link(fn -> static_sensor_loop(nil) end) 
    door = spawn_link(fn -> door_loop() end)

    {:ok, ctrl} = Controller.start_link(
      vault: vault, motor: motor, sensor: sensor, door: door, name: nil
    )

    assert_receive {:motor_command, {:move, :down, [speed: :slow]}}, 1000

    state = Controller.get_state(ctrl)
    assert state.status == :rehoming
  end

  test "Smart Homing: Cold Start results in Physical Homing", %{vault: vault} do
    test_pid = self()
    motor = spawn_link(fn -> motor_loop(test_pid) end)
    sensor = spawn_link(fn -> static_sensor_loop(1) end) 
    door = spawn_link(fn -> door_loop() end)

    {:ok, ctrl} = Controller.start_link(
      vault: vault, motor: motor, sensor: sensor, door: door, name: nil
    )

    assert_receive {:motor_command, {:move, :down, [speed: :slow]}}, 1000

    state = Controller.get_state(ctrl)
    assert state.status == :rehoming
    
    send(ctrl, {:floor_arrival, 0})
    
    state = Controller.get_state(ctrl)
    assert state.status == :normal
    assert state.current_floor == 0
  end

  test "Smart Homing: Requests are ignored during rehoming", %{vault: vault} do
    test_pid = self()
    motor = spawn_link(fn -> motor_loop(test_pid) end)
    sensor = spawn_link(fn -> static_sensor_loop(nil) end) 
    door = spawn_link(fn -> door_loop() end)

    {:ok, ctrl} = Controller.start_link(
      vault: vault, motor: motor, sensor: sensor, door: door, name: nil
    )

    # Use a longer timeout for the initial homing command to ensure it arrives
    assert_receive {:motor_command, {:move, :down, _}}, 2000
    
    assert Controller.get_state(ctrl).status == :rehoming

    Controller.request_floor(ctrl, :car, 2)
    
    state = Controller.get_state(ctrl)
    assert state.requests == []
    refute_receive {:motor_command, {:move, :up, _}}, 500
  end

  # --- Mock Helpers ---

  defp motor_loop(test_pid) do
    receive do
      {:"$gen_cast", cmd} -> 
        send(test_pid, {:motor_command, cmd})
        motor_loop(test_pid)
    end
  end

  defp static_sensor_loop(floor) do
    receive do
      {:"$gen_call", from, :get_floor} ->
        GenServer.reply(from, floor)
        static_sensor_loop(floor)
    end
  end

  defp door_loop do
    receive do
      _ -> door_loop()
    end
  end
end
