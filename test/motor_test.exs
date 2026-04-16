defmodule Elevator.MotorTest do
  @moduledoc """
  Proves the event-broadcasting behavior of Motor.

  Motor is a thin broadcaster: it publishes motor events to "elevator:hardware"
  and transitions state when World confirms braking is complete (:motor_stopped).
  All physical timing is owned by World.
  """
  use ExUnit.Case, async: true

  alias Elevator.Hardware.Motor

  setup do
    # Subscribe before starting Motor to avoid missing the first broadcast.
    Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:hardware")
    pid = start_supervised!({Motor, [name: nil]})
    %{motor: pid}
  end

  # ---------------------------------------------------------------------------
  # Initial state
  # ---------------------------------------------------------------------------

  test "[S-HW-MOTOR]: starts in a stopped state", %{motor: pid} do
    state = Motor.get_state(pid)
    assert state.status == :stopped
    assert state.direction == nil
    refute Map.has_key?(state, :timer)
  end

  # ---------------------------------------------------------------------------
  # Move broadcasts
  # ---------------------------------------------------------------------------

  test "[S-HW-MOTOR]: move/2 broadcasts {:motor_running, direction} and updates state",
       %{motor: pid} do
    Motor.move(pid, :up)

    assert_receive {:motor_running, :up}
    state = Motor.get_state(pid)
    assert state.status == :running
    assert state.direction == :up
  end

  test "[S-HW-MOTOR]: crawl/2 broadcasts {:motor_crawling, direction} and updates state",
       %{motor: pid} do
    Motor.crawl(pid, :down)

    assert_receive {:motor_crawling, :down}
    state = Motor.get_state(pid)
    assert state.status == :crawling
    assert state.direction == :down
  end

  # ---------------------------------------------------------------------------
  # Stop broadcasts
  # ---------------------------------------------------------------------------

  test "[S-HW-MOTOR]: stop/1 broadcasts :motor_stopping and enters :stopping state",
       %{motor: pid} do
    Motor.move(pid, :up)
    assert_receive {:motor_running, :up}

    Motor.stop(pid)

    assert_receive :motor_stopping
    state = Motor.get_state(pid)
    assert state.status == :stopping
  end

  test "[S-HW-MOTOR]: stop/1 is idempotent when already stopped", %{motor: pid} do
    Motor.stop(pid)

    state = Motor.get_state(pid)
    assert state.status == :stopped
  end

  # ---------------------------------------------------------------------------
  # World feedback
  # ---------------------------------------------------------------------------

  test "[S-HW-MOTOR]: :motor_stopped from World transitions to :stopped", %{motor: pid} do
    Motor.move(pid, :up)
    assert_receive {:motor_running, :up}
    Motor.stop(pid)
    assert_receive :motor_stopping

    send(pid, :motor_stopped)

    state = Motor.get_state(pid)
    assert state.status == :stopped
    assert state.direction == nil
  end

  # ---------------------------------------------------------------------------
  # Direction change
  # ---------------------------------------------------------------------------

  test "[S-HW-MOTOR]: a second move updates direction and broadcasts new event",
       %{motor: pid} do
    Motor.move(pid, :up)
    assert_receive {:motor_running, :up}

    Motor.crawl(pid, :down)
    assert_receive {:motor_crawling, :down}

    state = Motor.get_state(pid)
    assert state.status == :crawling
    assert state.direction == :down
  end
end
