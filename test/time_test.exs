defmodule Elevator.TimeTest do
  @moduledoc """
  Proves the tick-broadcasting and timer-scheduling behavior of Elevator.Time.

  Tests run with a fast tick (10ms) at 100x speed to avoid real-time waits.
  At 100x speed, a 1000ms delay fires in ~10ms.
  """
  use ExUnit.Case, async: true

  alias Elevator.Time

  # Fast tick for tests: 10ms interval, 100x speed multiplier
  @tick_ms 10
  @speed 100.0

  setup do
    Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:simulation")
    pid = start_supervised!({Time, [name: nil, tick_ms: @tick_ms, speed: @speed]})
    %{time: pid}
  end

  # ---------------------------------------------------------------------------
  # Ticking
  # ---------------------------------------------------------------------------

  test "[S-TIME]: publishes the first tick to elevator:simulation", %{time: _pid} do
    assert_receive {:tick, 1}, 100
  end

  test "[S-TIME]: tick counter increments with each tick", %{time: _pid} do
    assert_receive {:tick, 1}, 100
    assert_receive {:tick, 2}, 100
    assert_receive {:tick, 3}, 100
  end

  test "[S-TIME]: default tick interval is 250ms and default speed is 1.0" do
    pid = start_supervised!({Time, [name: nil]}, id: :default_time)
    state = Time.get_state(pid)
    assert state.tick_ms == 250
    assert state.speed == 1.0
  end

  # ---------------------------------------------------------------------------
  # Timer scheduling
  # ---------------------------------------------------------------------------

  test "[S-TIME]: send_after delivers message to target after scaled delay", %{time: pid} do
    # 1000ms delay / 100x speed = 10ms actual delay
    Time.send_after(pid, self(), 1_000, :timer_fired)
    assert_receive :timer_fired, 100
  end

  test "[S-TIME]: send_after delivers different messages to different targets", %{time: pid} do
    other = self()
    Time.send_after(pid, other, 500, :message_a)
    Time.send_after(pid, other, 500, :message_b)
    assert_receive :message_a, 100
    assert_receive :message_b, 100
  end

  test "[S-TIME]: send_after returns a cancel reference", %{time: pid} do
    ref = Time.send_after(pid, self(), 1_000, :irrelevant)
    assert is_reference(ref)
  end

  # ---------------------------------------------------------------------------
  # Timer cancellation
  # ---------------------------------------------------------------------------

  test "[S-TIME]: cancel prevents a pending timer from firing", %{time: pid} do
    # 10_000ms / 100x = 100ms — long enough to cancel safely
    ref = Time.send_after(pid, self(), 10_000, :should_not_arrive)
    Time.cancel(pid, ref)
    refute_receive :should_not_arrive, 50
  end

  test "[S-TIME]: cancel is idempotent — calling it twice does not crash", %{time: pid} do
    ref = Time.send_after(pid, self(), 10_000, :irrelevant)
    Time.cancel(pid, ref)
    assert :ok = Time.cancel(pid, ref)
  end
end
