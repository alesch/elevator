defmodule Elevator.AuditTest do
  use ExUnit.Case
  alias Elevator.Core

  @floors 0..5
  @headings [:up, :down, :idle]

  describe "[S-REQ-SYNC]: Combinatorial State Audit" do
    test "[S-REQ-SYNC]: Total Integrity Sweep (Floors x Headings x Targets)" do
      # Dimension 1: Every combination of starting state
      # Dimension 2: Every possible incoming request
      combinations =
        for f <- @floors,
            h <- @headings,
            target <- @floors,
            source <- [:hall, :car] do
          {f, h, target, source}
        end

      Enum.each(combinations, fn {current, heading, target, source} ->
        state = %Core{current_floor: current, heading: heading}

        # ACT: Receive request
        {new_state, _actions} = Core.request_floor(state, source, target)

        # ASSERT 1: Immediate Arrival Logic
        if current == target do
          assert new_state.door_status == :opening,
                 "Failed to open door at target #{target} from floor #{current}"
        end

        # ASSERT 2: Directional Integrity
        if target > current and new_state.motor_status != :stopping do
          # If request is above and we aren't stopping here, we must go UP
          assert new_state.heading == :up,
                 "At:#{current} Target:#{target} Should head :up but is #{new_state.heading}"
        end

        if target < current and new_state.motor_status != :stopping do
          # If request is below and we aren't stopping here, we must go DOWN
          assert new_state.heading == :down,
                 "At:#{current} Target:#{target} Should head :down but is #{new_state.heading}"
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
