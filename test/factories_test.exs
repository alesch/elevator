defmodule Elevator.FactoriesTest do
  use ExUnit.Case
  alias Elevator.Core

  describe "Core Factories" do
    test "booting/0 returns a fresh state in :booting phase" do
      # This test should fail first because booting/0 doesn't exist yet
      state = Core.booting()
      assert Core.phase(state) == :booting
      assert Core.current_floor(state) == :unknown
    end

    test "rehoming/0 drives to :rehoming phase with floor 0 request" do
      state = Core.rehoming()
      assert Core.phase(state) == :rehoming
      assert Core.requests(state) == [{:car, 0}]
      assert Core.heading(state) == :down
    end

    test "homing completion settles heading to :idle" do
      state = Core.rehoming()
      # Arrive at floor 0
      {state, _} = Core.handle_event(state, :floor_arrival, 0)
      # Confirm stop
      {state, _} = Core.handle_event(state, :motor_stopped)
      
      assert Core.phase(state) == :idle
      # This should fail: it will likely stay :down because update_sweep_heading is missing in rehoming settlement
      assert Core.heading(state) == :idle
    end

    test "idle_at/1 drives to :idle phase at specific floor" do
      # This will fail on sweep.heading because update_sweep_heading is not implemented yet
      state = Core.idle_at(3)
      assert Core.phase(state) == :idle
      assert Core.current_floor(state) == 3
      assert Core.heading(state) == :idle
    end

    test "docked_at/1 drives to :docked phase with door open" do
      state = Core.docked_at(2)
      assert Core.phase(state) == :docked
      assert Core.current_floor(state) == 2
      assert Core.door_status(state) == :open
    end

    test "moving_to/2 drives to :moving phase with correct heading" do
      state = Core.moving_to(1, 4)
      assert Core.phase(state) == :moving
      assert Core.current_floor(state) == 1
      assert Core.heading(state) == :up
    end
  end
end
