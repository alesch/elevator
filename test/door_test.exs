defmodule Elevator.DoorTest do
  @moduledoc """
  Proves the Safety Machine: Opening, Closing, and Obstruction.
  """
  use ExUnit.Case, async: true
  alias Elevator.Hardware.Door

  setup do
    # Subscribe before starting Door to avoid missing the first broadcast.
    Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:hardware")
    pid = start_supervised!({Door, [name: nil]})
    %{door: pid}
  end

  test "[S-HW-DOOR]: starts in a closed state", %{door: pid} do
    assert Door.get_state(pid).status == :closed
  end

  test "[S-HW-DOOR]: opening the door enters the opening state and announces intent", %{door: pid} do
    Door.open(pid)

    state = Door.get_state(pid)
    assert state.status == :opening
    assert_receive :door_opening
  end

  test "[S-SAFE-OBSTRUCT]: obstructing the door during closing instantly locks it out", %{
    door: pid
  } do
    Door.open(pid)
    _ = Door.get_state(pid)

    Door.close(pid)
    assert Door.get_state(pid).status == :closing

    # Simulate an obstruction
    Door.simulate_obstruction(pid)

    state = Door.get_state(pid)
    assert state.status == :obstructed

    # Verify the obstruction event was broadcast on the bus
    assert_receive :door_obstructed
  end

  test "[S-HW-DOOR]: door broadcasts :door_opened when World delivers :fully_opened", %{door: pid} do
    Door.open(pid)

    # World delivers physical completion (bypassing tick wait in this unit test)
    send(pid, :fully_opened)

    assert Door.get_state(pid).status == :open
    assert_receive :door_opened
  end
end
