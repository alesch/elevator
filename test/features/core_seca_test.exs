defmodule Elevator.Features.CoreSECATest do
  @moduledoc """
  One test per row in the SECA transition ledger (doc/states.md).
  These are the contract tests for the architecture refactor.

  Tests marked with @tag :failing are known failures before the refactor.
  All others must remain green throughout the refactor.
  """
  use ExUnit.Case, async: true

  alias Elevator.Core

  # ---------------------------------------------------------------------------
  # Phase: :booting
  # ---------------------------------------------------------------------------

  # SECA row: :booting + :startup_check + vault == sensor -> :opening
  # @tag :failing  (current code transitions to :idle instead)
  test "(:booting -> :opening) warm start: vault matches sensor" do
    {state, actions} = Core.booting() |> Core.handle_event(:startup_check, %{vault: 3, sensor: 3})

    assert Core.phase(state) == :opening
    assert {:open_door} in actions
  end

  # SECA row: :booting + :startup_check + vault != sensor -> :rehoming
  test "(:booting -> :rehoming) cold start: vault does not match sensor" do
    {state, actions} = Core.booting() |> Core.handle_event(:startup_check, %{vault: nil, sensor: nil})

    assert Core.phase(state) == :rehoming
    assert {:crawl, :down} in actions
  end

  # ---------------------------------------------------------------------------
  # Phase: :rehoming
  # ---------------------------------------------------------------------------

  # SECA row: :rehoming + :floor_arrival + is_integer(floor) -> :arriving
  # persist_arrival assertion is @tag :failing (floor_reached? bug in baseline diff)
  test "(:rehoming -> :arriving) floor sensed while crawling" do
    {state, actions} = Core.rehoming() |> Core.handle_event(:floor_arrival, 2)

    assert Core.phase(state) == :arriving
    assert {:stop_motor} in actions
    assert {:persist_arrival, 2} in actions
  end

  # ---------------------------------------------------------------------------
  # Phase: :idle
  # ---------------------------------------------------------------------------

  # SECA row: :idle + :request_floor + target == current -> :opening
  test "(:idle -> :opening) request for current floor opens door" do
    {state, actions} = Core.idle_at(3) |> Core.request_floor({:car, 3})

    assert Core.phase(state) == :opening
    assert {:open_door} in actions
  end

  # SECA row: :idle + :request_floor + target != current -> :leaving
  test "(:idle -> :leaving) request for a different floor starts movement" do
    {state, actions} = Core.idle_at(0) |> Core.request_floor({:car, 3})

    assert Core.phase(state) == :leaving
    assert {:move, :up} in actions
  end

  # SECA row: :idle + :inactivity_timeout + floor != 0 -> :leaving
  test "(:idle -> :leaving) inactivity timeout returns elevator to base floor" do
    {state, _actions} = Core.idle_at(3) |> Core.handle_event(:inactivity_timeout)

    assert Core.phase(state) == :leaving
    assert Core.next_stop(state) == 0
    assert Core.heading(state) == :down
  end

  # ---------------------------------------------------------------------------
  # Phase: :moving
  # ---------------------------------------------------------------------------

  # SECA row: :moving + :floor_arrival + floor == target -> :arriving
  test "(:moving -> :arriving) target floor reached" do
    {state, actions} = Core.moving_to(0, 3) |> Core.handle_event(:floor_arrival, 3)

    assert Core.phase(state) == :arriving
    assert {:stop_motor} in actions
  end

  # ---------------------------------------------------------------------------
  # Phase: :arriving
  # ---------------------------------------------------------------------------

  # SECA row: :arriving + :motor_stopped -> :opening
  test "(:arriving -> :opening) motor confirms stop" do
    arriving = Core.moving_to(0, 3) |> Core.handle_event(:floor_arrival, 3) |> elem(0)
    {state, actions} = Core.handle_event(arriving, :motor_stopped)

    assert Core.phase(state) == :opening
    assert {:open_door} in actions
  end

  # ---------------------------------------------------------------------------
  # Phase: :opening
  # ---------------------------------------------------------------------------

  # SECA row: :opening + :door_opened -> :docked
  test "(:opening -> :docked) door confirms open" do
    opening = Core.idle_at(3) |> Core.request_floor({:car, 3}) |> elem(0)
    {state, actions} = Core.handle_event(opening, :door_opened)

    assert Core.phase(state) == :docked
    assert Enum.any?(actions, &match?({:set_timer, :door_timeout, _}, &1))
  end

  # ---------------------------------------------------------------------------
  # Phase: :docked
  # ---------------------------------------------------------------------------

  # SECA row: :docked + :door_timeout -> :closing
  test "(:docked -> :closing) door timeout triggers close" do
    {state, actions} = Core.docked_at(3) |> Core.handle_event(:door_timeout)

    assert Core.phase(state) == :closing
    assert {:close_door} in actions
  end

  # SECA row: :docked + :door_close button -> :closing
  test "(:docked -> :closing) door-close button triggers close" do
    {state, actions} = Core.docked_at(3) |> Core.handle_button_press(:door_close, 0)

    assert Core.phase(state) == :closing
    assert {:close_door} in actions
  end

  # ---------------------------------------------------------------------------
  # Phase: :closing
  # ---------------------------------------------------------------------------

  # SECA row: :closing + :door_closed + requests.empty? -> :idle
  test "(:closing -> :idle) door closed with no pending requests" do
    closing = Core.docked_at(3) |> Core.handle_event(:door_timeout) |> elem(0)
    {state, _actions} = Core.handle_event(closing, :door_closed)

    assert Core.phase(state) == :idle
  end

  # SECA row: :closing + :door_closed + not requests.empty? -> :leaving
  test "(:closing -> :leaving) door closed with pending requests" do
    closing =
      Core.docked_at(3)
      |> Core.request_floor({:car, 0})
      |> elem(0)
      |> Core.handle_event(:door_timeout)
      |> elem(0)

    {state, actions} = Core.handle_event(closing, :door_closed)

    assert Core.phase(state) == :leaving
    assert {:move, :down} in actions
  end

  # SECA row: :closing + :door_obstructed -> :opening
  test "(:closing -> :opening) door obstructed reopens door" do
    closing = Core.docked_at(3) |> Core.handle_event(:door_timeout) |> elem(0)
    {state, actions} = Core.handle_event(closing, :door_obstructed)

    assert Core.phase(state) == :opening
    assert {:open_door} in actions
  end

  # ---------------------------------------------------------------------------
  # Phase: :leaving
  # ---------------------------------------------------------------------------

  # SECA row: :leaving + :motor_running -> :moving
  test "(:leaving -> :moving) motor confirms running" do
    leaving = Core.idle_at(0) |> Core.request_floor({:car, 3}) |> elem(0)
    {state, actions} = Core.handle_event(leaving, :motor_running)

    assert Core.phase(state) == :moving
    assert actions == []
  end
end
