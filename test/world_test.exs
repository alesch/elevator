defmodule Elevator.WorldTest do
  @moduledoc """
  Proves the physical simulation behavior of Elevator.World.

  World subscribes to "elevator:simulation" (ticks) and "elevator:hardware"
  (motor events). It fires {:floor_arrival, floor} onto "elevator:hardware"
  after the correct number of ticks for a given motor speed.

  Physical constants under test:
    @ticks_per_floor_running  6   (6 × 250ms = 1500ms)
    @ticks_per_floor_crawling 18  (18 × 250ms = 4500ms)
    @brake_ticks              2   (2 × 250ms = 500ms)
  """
  use ExUnit.Case, async: true

  alias Elevator.World

  setup do
    # Inject self() as the controller so World sends events directly to this
    # test process. This avoids PubSub cross-test pollution in async: true mode.
    pid = start_supervised!({World, [name: nil, floor: 0, controller: self()]})
    %{world: pid}
  end

  # Convenience: send a tick directly to World (bypasses PubSub, controls timing)
  defp tick(world, n) do
    Enum.each(1..n, fn _ -> send(world, {:tick, :_}) end)
  end

  # ---------------------------------------------------------------------------
  # Floor crossings at running speed (6 ticks)
  # ---------------------------------------------------------------------------

  test "[S-WORLD]: no floor_arrival when motor is stopped", %{world: pid} do
    tick(pid, 6)
    refute_receive {:floor_arrival, _}, 50
  end

  test "[S-WORLD]: floor_arrival fires after 6 ticks at running speed", %{world: pid} do
    send(pid, {:motor_running, :up})
    tick(pid, 6)
    assert_receive {:floor_arrival, 1}
  end

  test "[S-WORLD]: floor_arrival fires after 6 ticks going down", %{world: _pid} do
    pid2 = start_supervised!({World, [name: nil, floor: 3, controller: self()]}, id: :world_down)
    send(pid2, {:motor_running, :down})
    tick(pid2, 6)
    assert_receive {:floor_arrival, 2}
  end

  test "[S-WORLD]: ticks before 6 do not fire floor_arrival", %{world: pid} do
    send(pid, {:motor_running, :up})
    tick(pid, 5)
    refute_receive {:floor_arrival, _}, 50
  end

  test "[S-WORLD]: floor_arrival fires on each subsequent floor while motor runs", %{world: pid} do
    send(pid, {:motor_running, :up})
    tick(pid, 6)
    assert_receive {:floor_arrival, 1}
    tick(pid, 6)
    assert_receive {:floor_arrival, 2}
  end

  # ---------------------------------------------------------------------------
  # Floor crossings at crawling speed (18 ticks)
  # ---------------------------------------------------------------------------

  test "[S-WORLD]: floor_arrival fires after 18 ticks at crawling speed", %{world: pid} do
    send(pid, {:motor_crawling, :down})
    tick(pid, 18)
    assert_receive {:floor_arrival, -1}
  end

  test "[S-WORLD]: 6 ticks at crawling speed do not fire floor_arrival", %{world: pid} do
    send(pid, {:motor_crawling, :down})
    tick(pid, 6)
    refute_receive {:floor_arrival, _}, 50
  end

  # ---------------------------------------------------------------------------
  # Motor stopping and braking
  # ---------------------------------------------------------------------------

  test "[S-WORLD]: motor stopping mid-transit cancels pending floor crossing", %{world: pid} do
    send(pid, {:motor_running, :up})
    tick(pid, 3)
    # Motor stop command arrives — World enters braking countdown
    send(pid, :motor_stopping)
    # Remaining transit ticks do not fire a floor_arrival
    tick(pid, 3)
    refute_receive {:floor_arrival, _}, 50
  end

  test "[S-WORLD]: motor_stopped fires after 2 brake ticks", %{world: pid} do
    send(pid, {:motor_running, :up})
    send(pid, :motor_stopping)
    tick(pid, 2)
    assert_receive :motor_stopped
  end

  test "[S-WORLD]: motor_stopped does not fire before brake ticks complete", %{world: pid} do
    send(pid, {:motor_running, :up})
    send(pid, :motor_stopping)
    tick(pid, 1)
    refute_receive :motor_stopped, 50
  end

  # ---------------------------------------------------------------------------
  # State inspection
  # ---------------------------------------------------------------------------

  test "[S-WORLD]: get_state returns current floor and motor status", %{world: pid} do
    state = World.get_state(pid)
    assert state.floor == 0
    assert state.motor == :stopped
  end

  test "[S-WORLD]: floor updates after a floor_arrival is fired", %{world: pid} do
    send(pid, {:motor_running, :up})
    tick(pid, 6)
    assert_receive {:floor_arrival, 1}
    assert World.get_state(pid).floor == 1
  end
end
