defmodule Elevator.AuditTest do
  use ExUnit.Case
  alias Elevator.Core

  @floors 1..5
  @headings [:up, :down, :idle]
  # 0kg (Normal), 950kg (Full Load - Above 900kg threshold)
  @weights [0, 950]

  describe "Scenario 4.9: Combinatorial State Audit" do
    test "Scenario 4.9: Total Integrity Sweep (Floors x Headings x Weights x Targets)" do
      # Dimension 1: Every combination of starting state
      # Dimension 2: Every possible incoming request
      combinations =
        for f <- @floors,
            h <- @headings,
            w <- @weights,
            target <- @floors,
            source <- [:hall, :car] do
          {f, h, w, target, source}
        end

      # 600 unique combinations!
      Enum.each(combinations, fn {current, heading, weight, target, source} ->
        state = %Core{current_floor: current, heading: heading, weight: weight}

        # ACT: Receive request
        {new_state, _actions} = Core.request_floor(state, source, target)

        # ASSERT 1: Immediate Arrival Logic
        if current == target do
          # If it's a car request on our own floor, or we have capacity for hall, must halt
          if source == :car or weight <= 900 do
            assert new_state.motor_status == :stopping,
                   "Failed to stop at target #{target} from floor #{current} with weight #{weight}"
          end
        end

        # ASSERT 2: Directional Integrity
        if target > current and new_state.motor_status != :stopping do
          # If request is above and we aren't stopping here, we must go UP
          assert new_state.heading == :up,
                 "At:#{current} Target:#{target} Weight:#{weight} Should head :up but is #{new_state.heading}"
        end

        if target < current and new_state.motor_status != :stopping do
          # If request is below and we aren't stopping here, we must go DOWN
          assert new_state.heading == :down,
                 "At:#{current} Target:#{target} Weight:#{weight} Should head :down but is #{new_state.heading}"
        end

        # ASSERT 3: Never Idle with Work
        if target != current do
          assert new_state.heading != :idle,
                 "Elevator went idle with target:#{target} at floor:#{current}"
        end
      end)
    end
  end
end
