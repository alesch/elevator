defmodule Elevator.DoorTest do
  @moduledoc """
  Proves the Safety Machine: Opening, Closing, and Obstruction.
  """
  use ExUnit.Case, async: true
  alias Elevator.Door

  setup do
    # Inject self() as the controller to catch notifications locally
    # Use name: nil to prevent global registration and avoid collisions in parallel tests
    pid = start_supervised!({Door, [controller: self(), name: nil]})
    %{door: pid}
  end

  test "starts in a closed state", %{door: pid} do
    assert Door.get_state(pid).status == :closed
  end

  test "opening the door starts the opening timer", %{door: pid} do
    Door.open(pid)
    
    state = Door.get_state(pid)
    assert state.status == :opening
    assert is_reference(state.timer)

    # Deterministic Proof: Opening takes 1 second (1000ms)
    remaining = Process.read_timer(state.timer)
    assert remaining > 0 and remaining <= 1000
  end

  test "obstructing the door during closing instantly locks it out", %{door: pid} do
    Door.open(pid)
    # Wait for casts to process
    _ = Door.get_state(pid)
    
    Door.close(pid)
    assert Door.get_state(pid).status == :closing
    
    # Simulate an obstruction
    Door.obstruct(pid)

    state = Door.get_state(pid)
    assert state.status == :obstructed
    assert state.timer == nil # Timer should be cancelled
    
    # Verify the Controller (the test process) was notified of the safety alarm
    assert_receive :door_obstructed
  end

  test "door notifies the Controller upon full opening", %{door: pid} do
    Door.open(pid)
    
    # Manually trigger the transition to bypass waiting 1s
    send(pid, :fully_opened)

    assert Door.get_state(pid).status == :open
    assert_receive :door_opened
  end
end
