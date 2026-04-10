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
        state =
          case heading do
            :idle -> Core.idle_at(current)
            :up when current < 5 -> Core.idle_at(current) |> Core.request_floor(:car, 5) |> elem(0)
            :down when current > 0 -> Core.idle_at(current) |> Core.request_floor(:car, 0) |> elem(0)
            _ -> nil
          end

        if state do
          # ACT: Receive request
          {new_state, _actions} = Core.request_floor(state, source, target)

          # ASSERT 1: Immediate Arrival Logic
          # Exception: Asymmetry Rule ([R-MOVE-LOOK]) defers Hall requests          # Rule: Target Arrival Logic
          # (Formerly handled immediate arrival checks here; now delegated to movement.feature)


          # ASSERT 3: Never Idle with Work
          if target != current do
            assert Core.heading(new_state) != :idle,
                   "Elevator went idle with target:#{target} at floor:#{current}"
          end
        end
      end)
    end
  end
end
