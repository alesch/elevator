defmodule Elevator.MotorTest do
  @moduledoc """
  Proves the 2-second transit physics of the Motor actor.
  """
  use ExUnit.Case, async: true
  alias Elevator.Hardware.Motor

  setup do
    # Inject self() as the sensor to catch pulses locally
    # Use name: nil to prevent global registration and avoid collisions in parallel tests
    pid = start_supervised!({Motor, [sensor: self(), name: nil]})
    %{motor: pid}
  end

  test "[S-HW-MOTOR]: starts in a stopped state", %{motor: pid} do
    assert %{status: :stopped, direction: nil, timer: nil} = Motor.get_state(pid)
    # Verify the speed field is gone (Simplified state)
    refute Map.has_key?(Motor.get_state(pid), :speed)
  end

  test "[S-HW-MOTOR]: move/2 starts the normal transit timer", %{motor: pid} do
    Motor.move(pid, :up)

    state = Motor.get_state(pid)
    assert state.status == :running
    assert state.direction == :up
    assert is_reference(state.timer)

    # Deterministic Proof: Audit the timer remaining time (~1500ms)
    remaining = Process.read_timer(state.timer)
    assert remaining > 0 and remaining <= 1500
  end

  test "[S-HW-MOTOR]: crawl/2 starts the slow transit timer", %{motor: pid} do
    Motor.crawl(pid, :up)

    state = Motor.get_state(pid)
    assert state.status == :crawling
    assert state.direction == :up
    assert is_reference(state.timer)

    # Deterministic Proof: Audit the timer remaining time (~4500ms)
    remaining = Process.read_timer(state.timer)
    assert remaining > 1500 and remaining <= 4500
  end

  test "[S-HW-MOTOR]: stopping motion enters :stopping state with a brake timer", %{motor: pid} do
    # Start moving
    Motor.move(pid, :up)

    # Stop moving
    Motor.stop(pid)

    state = Motor.get_state(pid)
    assert state.status == :stopping
    assert is_reference(state.timer)

    # Deterministic Proof of brake timer (500ms)
    remaining = Process.read_timer(state.timer)
    assert remaining > 0 and remaining <= 500
  end

  test "[S-HW-MOTOR]: motor transitions to :stopped after braking", %{motor: pid} do
    Motor.move(pid, :up)
    Motor.stop(pid)

    # Wait for brake timer to fire (500ms + margin)
    Process.sleep(600)

    state = Motor.get_state(pid)
    assert state.status == :stopped
    assert state.timer == nil
  end

  test "[S-HW-MOTOR]: consecutive moves reset the timer correctly", %{motor: pid} do
    Motor.move(pid, :up)
    %{} = state1 = Motor.get_state(pid)
    ref1 = state1.timer

    Motor.crawl(pid, :down)
    %{} = state2 = Motor.get_state(pid)
    ref2 = state2.timer

    assert ref1 != ref2
    # Verify the first timer was cancelled
    assert Process.read_timer(ref1) == false
    # Verify the new timer is active (with slow timing)
    remaining = Process.read_timer(ref2)
    assert is_integer(remaining)
    assert remaining > 1500
  end

  test "[S-HW-MOTOR]: motor notifies the sensor upon pulse", %{motor: pid} do
    # Start moving to trigger pulses
    Motor.move(pid, :up)

    # Manually trigger the pulse info to bypass waiting 2s
    send(pid, {:pulse, :up})

    # The Motor should notify the Sensor (the test process): {:motor_pulse, :up}
    assert_receive {:motor_pulse, :up}
  end
end
