defmodule Elevator.Features.SystemTest do
  use Cabbage.Feature,
    file: "system.feature",
    async: false

  import Elevator.SystemCase

  alias Elevator.Controller

  # ---------------------------------------------------------------------------
  # Given
  # ---------------------------------------------------------------------------

  # Start all components with production-identical registry topology.
  # vault_floor: 0 and sensor_floor: 0 match → warm start → opens door → docked.
  # We wait for :idle (boot sequence fully settled: docked → door timeout → idle).
  defgiven ~r/^the system is docked at floor 0$/, _vars, context do
    Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:status")
    start_system(vault_floor: 0, sensor_floor: 0)

    assert_receive {:elevator_state, %{logic: %{phase: :idle}, hardware: %{current_floor: 0}}},
                   2000

    {:ok, context}
  end

  # ---------------------------------------------------------------------------
  # When
  # ---------------------------------------------------------------------------

  defwhen ~r/^a car request for floor (?<floor>\d+) is received$/, %{floor: floor_str}, context do
    Controller.request_floor(Controller, :car, String.to_integer(floor_str))
    {:ok, context}
  end

  # ---------------------------------------------------------------------------
  # Then / And
  # ---------------------------------------------------------------------------

  defthen ~r/^the elevator docks at floor (?<floor>\d+)$/, %{floor: floor_str}, context do
    floor = String.to_integer(floor_str)

    assert_receive {:elevator_state,
                    %{logic: %{phase: :docked}, hardware: %{current_floor: ^floor}}},
                   5000

    {:ok, context}
  end

  defthen ~r/^the elevator becomes idle at floor (?<floor>\d+)$/, %{floor: floor_str}, context do
    floor = String.to_integer(floor_str)

    assert_receive {:elevator_state,
                    %{logic: %{phase: :idle}, hardware: %{current_floor: ^floor}}},
                   5000

    {:ok, context}
  end
end
