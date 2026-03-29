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
      tasks = for i <- 1..5 do
        Task.async(fn -> Controller.request_floor(pid, :hall, i) end)
      end

      # Wait for all "fingers" to finish
      Enum.each(tasks, &Task.await/1)

      state = Controller.get_state(pid)
      
      unique_targets = Enum.map(state.requests, fn {_, f} -> f end) |> Enum.sort()
      assert unique_targets == [1, 2, 3, 4, 5]
    end

    test "Rule 1.4: Sliding Inactivity Window (Return to Base)" do
      # Start with a very fast timer (10ms)
      {:ok, pid} = Controller.start_link(timer_ms: 10)
      
      # Wait for 50ms (well past the 10ms timeout)
      Process.sleep(50)

      # Assert: It should have automatically added a request for Floor 1
      state = Controller.get_state(pid)
      assert {:hall, 1} in state.requests
    end
  end
end
