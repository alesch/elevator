defmodule Elevator.MotorTest do
  @moduledoc """
  Proves the 2-second transit physics of the Motor actor.
  """
  use ExUnit.Case, async: true
  alias Elevator.Motor

  setup do
    # Inject self() as the sensor to catch pulses locally
    # Use name: nil to prevent global registration and avoid collisions in parallel tests
    pid = start_supervised!({Motor, [sensor: self(), name: nil]})
    %{motor: pid}
  end

  test "starts in a stopped state", %{motor: pid} do
    assert %{status: :stopped, direction: nil, timer: nil} = Motor.get_state(pid)
  end

  test "scheduling a move starts the transit timer", %{motor: pid} do
    Motor.move(pid, :up)

    state = Motor.get_state(pid)
    assert state.status == :moving
    assert state.direction == :up
    assert is_reference(state.timer)

    # Deterministic Proof: Audit the timer remaining time (~2000ms)
    # This proves the 2s physics without actually waiting 2s.
    remaining = Process.read_timer(state.timer)
    assert remaining > 0 and remaining <= 2000
  end

  test "stopping motion cancels the timer", %{motor: pid} do
    # Start moving
    Motor.move(pid, :up)
    
    # Wait for cast to process (Sync peek)
    _ = Motor.get_state(pid)
    
    # Stop moving
    Motor.stop(pid)

    state = Motor.get_state(pid)
    assert state.status == :stopped
    assert state.timer == nil
  end

  test "consecutive moves reset the timer", %{motor: pid} do
    Motor.move(pid, :up)
    %{} = state1 = Motor.get_state(pid)
    ref1 = state1.timer

    Motor.move(pid, :down)
    %{} = state2 = Motor.get_state(pid)
    ref2 = state2.timer

    assert ref1 != ref2
    # Verify the first timer was cancelled
    assert Process.read_timer(ref1) == false 
    # Verify the new timer is active
    assert is_integer(Process.read_timer(ref2))
  end

  test "motor notifies the sensor upon pulse", %{motor: pid} do
    # Start moving to trigger pulses
    Motor.move(pid, :up)
    
    # Manually trigger the pulse info to bypass waiting 2s
    send(pid, {:pulse, :up})
    
    # The Motor should notify the Sensor (the test process): {:motor_pulse, :up}
    assert_receive {:motor_pulse, :up}
  end
end
