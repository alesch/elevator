defmodule Elevator.Gherkin.Steps do
  @moduledoc """
  Standardized Gherkin step definitions for Elevator features.
  Provides reusable property checks for phase, motor, door, heading, and floor.
  """
  use Cabbage.Feature
  alias Elevator.Core
  alias Elevator.Gherkin.Arguments, as: Args
  import ExUnit.Assertions

  # 1) the phase is xyz
  defthen ~r/^(the )?phase is (?<val>.+)$/, %{val: val}, context do
    expected = Args.parse_phase(val)
    actual = Core.phase(context.state)
    assert actual == expected, "Expected phase #{expected}, got #{actual}"
    {:ok, context}
  end

  # 2) the motor is xyz
  defthen ~r/^(the )?motor( status| speed)? is (?<val>.+)$/, %{val: val}, context do
    expected = Args.parse_motor_status(val)

    case {expected, context.actions} do
      {:running, actions} when actions != [] ->
        assert Enum.any?(actions, fn
                 {:move, _} -> true
                 {:crawl, _} -> true
                 _ -> false
               end),
               "Expected motor to start running (move/crawl action), but none found in #{inspect(actions)}"

      {:stopping, actions} when actions != [] ->
        assert {:stop_motor} in actions,
               "Expected motor to be stopping (:stop_motor action), but not found in #{inspect(actions)}"

      _ ->
        actual = Core.motor_status(context.state)
        assert actual == expected, "Expected motor status #{expected}, got #{actual}"
    end

    {:ok, context}
  end

  # 3) the door is xyz
  defthen ~r/^(the )?door( status)? is (?<val>.+)$/, %{val: val}, context do
    expected = Args.parse_door_status(val)

    case {expected, context.actions} do
      {:opening, actions} when actions != [] ->
        assert {:open_door} in actions,
               "Expected door to be opening (:open_door action), but not found in #{inspect(actions)}"

      {:closing, actions} when actions != [] ->
        assert {:close_door} in actions,
               "Expected door to be closing (:close_door action), but not found in #{inspect(actions)}"

      _ ->
        actual = Core.door_status(context.state)
        assert actual == expected, "Expected door status #{expected}, got #{actual}"
    end

    {:ok, context}
  end

  # 4) the heading is xyz
  defthen ~r/^(the )?heading is (?<val>.+)$/, %{val: val}, context do
    expected = Args.parse_heading(val)
    actual = Core.heading(context.state)
    assert actual == expected, "Expected heading #{expected}, got #{actual}"
    {:ok, context}
  end

  # 5) the current floor is xyz
  defthen ~r/^(the )?current floor is (?<val>.+)$/, %{val: val}, context do
    expected = Args.parse_floor(val)
    actual = Core.current_floor(context.state)
    assert actual == expected, "Expected current floor #{expected}, got #{actual}"
    {:ok, context}
  end
end
