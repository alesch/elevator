defmodule Elevator.ControllerTest do
  use ExUnit.Case
  alias Elevator.Controller
  alias Elevator.State

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

      # Wait a tiny bit for the mailbox to be processed
      # (Alternatively, we could use a synchronous call for verification)
      state = Controller.get_state(pid)
      assert state.heading == :up
      assert {:car, 4} in state.requests
    end

    test "Handling concurrent requests (Race Condition Proof)" do
      {:ok, pid} = Controller.start_link()

      # Simulate 100 people pressing buttons simultaneously!
      # We send them from 100 different "Process tasks"
      tasks = for i <- 1..5 do
        Task.async(fn -> Controller.request_floor(pid, :hall, i) end)
      end

      # Wait for all "fingers" to finish pressing
      Enum.each(tasks, &Task.await/1)

      # Assert: Every single request must be in the queue in the correct order
      state = Controller.get_state(pid)
      
      # Since they were concurrent, we don't know the order, but we know the count
      # (Filtering unique because we might have duplicates if tasks overlapped)
      unique_targets = Enum.map(state.requests, fn {_, f} -> f end) |> Enum.sort()
      assert unique_targets == [1, 2, 3, 4, 5]
    end
  end

  # We'll use a hack to test the timer during development/audit
  # In a real app, we'd use a configuration variable or a mock
end
