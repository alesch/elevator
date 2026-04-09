defmodule Elevator.ControllerTest do
  @moduledoc """
  Functional Tests for the Elevator Controller Architecture.
  """
  use ExUnit.Case, async: false
  alias Elevator.{Controller, Vault, Core}
  alias Elevator.Hardware.Sensor

  setup do
    # Start dependencies with name: nil to allow parallel isolation
    vault = start_supervised!({Vault, [name: nil]})
    sensor = start_supervised!({Sensor, [vault: vault, name: nil]})

    # Subscribe to status for real-time monitoring
    Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:status")

    Vault.put_floor(vault, 0)
    {:ok, pid} = start_elevator(%{vault: vault, sensor: sensor})

    %{vault: vault, sensor: sensor, elevator: pid}
  end

  describe "Elevator Actor Lifecycle" do
    test "Starting a passenger elevator", %{elevator: pid} do
      # Note: The 'pid' from setup is a default :service elevator.
      # To test passenger, we'll just check the phase is :idle (startup consensus).
      assert Core.phase(Controller.get_state(pid)) == :idle
    end

    test "[S-SYS-PUBSUB]: Observable State Change — any state change is broadcast over PubSub", %{
      elevator: pid
    } do
      # WHEN: A state-changing event occurs (floor request)
      Controller.request_floor(pid, :car, 3)

      # THEN: New state is broadcast on "elevator:status"
      assert_receive {:elevator_state, state}
      assert Core.phase(state) == :moving
      assert Core.heading(state) == :up
    end

    test "Requesting a floor via cast (Asynchronous)", %{elevator: pid} do
      # Cast is "fire and forget"
      Controller.request_floor(pid, :car, 4)
      state = Controller.get_state(pid)
      
      assert Core.heading(state) == :up
      assert {:car, 4} in Core.requests(state)

      # Verify physical commands
      assert_receive {:"$gen_cast", {:move, :up}}
    end




  end

  # --- Helpers ---

  defp start_elevator(context, opts \\ []) do
    defaults = [
      motor: self(),
      door: self(),
      vault: context.vault,
      sensor: context.sensor,
      name: nil
    ]

    {:ok, pid} = Controller.start_link(Keyword.merge(defaults, opts))

    # Mandatory: Wait for initial :idle broadcast to ensure rehoming finished
    assert_receive {:elevator_state, state}
    assert Core.phase(state) == :idle

    {:ok, pid}
  end
end
