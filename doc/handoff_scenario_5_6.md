# Handoff: Scenario 5.6 — No Door Cycle on Homing Arrival

**Status**: Scenarios updated, docs updated. Tests reverted. Implementation NOT started.

---

## What Was Done

- `doc/scenarios.md`: Scenario 5.4 updated to explicitly state `door_status` stays `:closed` after homing completion. Scenario 5.6 added (unchecked `[ ]`).
- `doc/core_rules.md`: State machine table extended with the missing rehoming `:motor_stopped` row — door stays `:closed`, status transitions to `:normal`.

---

## The Bug

After rehoming, when the elevator physically arrives at F0, the system correctly stops the motor. But when the `:motor_stopped` hardware event is then processed, `Core.do_handle_event(state, :motor_stopped)` calls `confirm_stopped_at_floor/1`, which **unconditionally** sets `door_status: :opening` regardless of whether anyone requested that floor:

```elixir
# lib/elevator/core.ex ~line 296
defp confirm_stopped_at_floor(state) do
  %{state | motor_status: :stopped, door_status: :opening}  # ← always opens
end
```

Since the homing move is a calibration move (no one requested F0), the doors should stay closed. The observable symptom is a ~5s pause in the E2E test and in the GUI: after rehoming, doors open, wait 5s, close, and only then service the first real request.

---

## Why the Existing Test Is a False Green

The Scenario 5.4 test (`test/homing_test.exs`, "Scenario 5.1 & 5.4") does not catch this bug because:

- `Motor` is started with `name: nil` and no `controller:` key.
- When Motor calls `notify_controller(state, :motor_stopped)`, `state.controller` is `nil`.
- It falls back to `lookup_controller()` via Registry, but the Controller was also started with `name: nil`, so it never registered.
- Therefore `:motor_stopped` is **never delivered** to the Controller in this test.
- The door assertions that were added during this session were also a false green for the same reason.

---

## The Fix (Approved by Alex)

The fix is in `lib/elevator/core.ex`. Change `do_handle_event` for `:motor_stopped` to check whether there was a service request **before** fulfilling it, and pass that flag to `confirm_stopped_at_floor`:

```elixir
# BEFORE
defp do_handle_event(state, :motor_stopped, _now) do
  state
  |> fulfill_current_floor_requests()
  |> confirm_stopped_at_floor()
  |> apply_logic()
end

defp confirm_stopped_at_floor(state) do
  %{state | motor_status: :stopped, door_status: :opening}
end

# AFTER
defp do_handle_event(state, :motor_stopped, _now) do
  had_request = should_stop_at?(state, state.current_floor)
  state
  |> fulfill_current_floor_requests()
  |> confirm_stopped_at_floor(had_request)
  |> apply_logic()
end

defp confirm_stopped_at_floor(state, _open_door? = true) do
  %{state | motor_status: :stopped, door_status: :opening}
end

defp confirm_stopped_at_floor(state, _open_door? = false) do
  %{state | motor_status: :stopped}
end
```

Also update the call in `do_process_current_floor/1`, which already guards with `should_stop_at?`, so pass `true`:

```elixir
# lib/elevator/core.ex, inside do_process_current_floor
|> confirm_stopped_at_floor(true)
```

---

## The Test Fix

The Scenario 5.4 test needs to be updated to:

1. Manually send `:motor_stopped` to the controller (since hardware notification is not wired in unit tests).
2. Add proper flush calls around it.
3. Assert `state.door_status == :closed` and `Door.get_state(door).status == :closed`.

**Correct test addition (after `assert Motor.get_state(motor).status == :stopped`):**

```elixir
# Manually deliver :motor_stopped since Motor→Controller notification
# is not wired in this unit test (Motor started without controller: ctrl).
send(ctrl, :motor_stopped)

# Two get_state calls: first flushes :motor_stopped, second reads settled state.
_ = Controller.get_state(ctrl)
state = Controller.get_state(ctrl)

# Scenario 5.6: Homing is a calibration move — doors must NOT open
assert state.door_status == :closed
assert Door.get_state(door).status == :closed
```

**Expected**: test is RED before the Core fix, GREEN after.

---

## Order of Operations

1. Update `test/homing_test.exs` (Scenario 5.4 test) as above → confirm RED.
2. Fix `lib/elevator/core.ex` as above → confirm GREEN.
3. Run full suite: `mix test` → 64 tests, 0 failures.
4. Run GUI tests: `mix test-gui` → confirm the ~5s door-open delay after rehoming is gone.
5. Mark Scenario 5.6 as `[x]` in `doc/scenarios.md`.
6. Commit.
