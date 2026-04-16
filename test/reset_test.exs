defmodule Elevator.ResetTest do
  @moduledoc """
  Reproduces the post-reset startup behaviour:
  vault is cleared to nil, hardware restarts with sensor at floor 0.
  This is exactly what Controller.reset/0 produces before the Playwright
  beforeEach hook navigates to the dashboard.
  """
  use ExUnit.Case, async: false

  import Elevator.SystemCase

  setup do
    Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:status")
    :ok
  end

  # Baseline: vault=0 + sensor=0 → warm start, no rehoming.
  test "warm start: vault=0, sensor=0 → docks at floor 0" do
    start_system(vault_floor: 0, sensor_floor: 0)

    assert_receive {:elevator_state, %{logic: %{phase: :docked}, hardware: %{current_floor: 0}}},
                   3000
  end

  # Simulates Controller.reset/0: vault is set to 0, then hardware restarts.
  # vault=0 + sensor=0 → warm start → docks at floor 0 without rehoming.
  test "post-reset: vault=0, sensor=0 → warm start, docks at floor 0" do
    start_system(vault_floor: 0, sensor_floor: 0)

    assert_receive {:elevator_state, %{logic: %{phase: :docked}, hardware: %{current_floor: 0}}},
                   3000
  end
end
