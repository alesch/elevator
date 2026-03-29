defmodule Elevator.ControllerTest do
  use ExUnit.Case
  alias Elevator.Controller

  describe "Elevator Actor Lifecycle" do
    test "Starting a passenger elevator" do
      {:ok, pid} = Controller.start_link(type: :passenger)

      state = Controller.get_state(pid)
      assert state.weight_limit == 1000
      assert state.current_floor == 1
    end

    test "Requesting a floor via cast (Asynchronous)" do
      {:ok, pid} = Controller.start_link()

      # Cast is "fire and forget"
      Controller.request_floor(pid, :car, 4)
      state = Controller.get_state(pid)
      assert state.heading == :up
      assert {:car, 4} in state.requests
    end

    test "Handling concurrent requests (Race Condition Proof)" do
      {:ok, pid} = Controller.start_link()

      # Simulate parallel button presses
      tasks =
        for i <- 1..5 do
          Task.async(fn -> Controller.request_floor(pid, :hall, i) end)
        end

      # Wait for all "fingers" to finish
      Enum.each(tasks, &Task.await/1)

      state = Controller.get_state(pid)

      unique_targets = Enum.map(state.requests, fn {_, f} -> f end) |> Enum.sort()
      assert unique_targets == [1, 2, 3, 4, 5]
    end

    test "Rule 1.4: Inactivity Window (Deterministic Verification)" do
      {:ok, pid} = Controller.start_link()

      # 1. Verify Scheduling (Intent)
      # We inspect the internal timer to prove the actor INTENDS to return to base
      timer_ref = Controller.get_timer_ref(pid)
      assert is_reference(timer_ref)
      assert Process.read_timer(timer_ref) > 0

      # 2. Verify Logic (Action)
      # Instead of waiting for the clock, we manually trigger the message
      send(pid, :return_to_base)

      # 'get_state' is synchronous, so it acts as a barrier until 'send' is processed
      state = Controller.get_state(pid)
      assert {:hall, 1} in state.requests
    end
  end
end
