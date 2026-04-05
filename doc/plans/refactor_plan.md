# Refactor Plan: Explicit Phase State Machine

## Context

`Elevator.Core` currently encodes its state machine implicitly across four fields:
`status`, `motor_status`, `door_status`, and `heading`. The `apply_logic/2` pipeline
infers the current phase from combinations of these fields, leading to stages that
fight each other, order-dependent correctness, and real deadlocks.

The fix: replace the implicit phase inference with an explicit `phase` field.
Each event handler becomes phase-gated via pattern matching — no conditionals needed.
Overload support is also removed entirely.

The docs ([`doc/core_rules.md`](doc/core_rules.md) and the [**`features/`**](../features/) directory) have already been updated to
reflect the new model. Read them before starting.

---

## New State Model

```
phase: :rehoming | :moving | :arriving | :docked | :leaving | :idle
```

| Phase      | Meaning                                      | Motor       | Door                  |
|:-----------|:---------------------------------------------|:------------|:----------------------|
| `:rehoming`| Boot/crash recovery, moving down             | `:crawling` | `:closed`             |
| `:moving`  | Traveling to a target floor                  | `:running`  | `:closed`             |
| `:arriving`| Motor stopping → stopped → door opening      | transitioning | `:opening`          |
| `:docked`  | At floor, doors open, serving passengers     | `:stopped`  | `:open`               |
| `:leaving` | Service complete: door closing               | `:stopped`  | `:closing` → `:closed`|
| `:idle`    | At floor, doors closed, no active work       | `:stopped`  | `:closed`             |

### Phase Transitions

```
:rehoming  --[motor_stopped]--------------------------> :idle
:idle      --[request + heading set]------------------> :moving
:moving    --[floor_arrival at target]----------------> :arriving
:arriving  --[door_opened]----------------------------> :docked
:docked    --[timeout or close_button]----------------> :leaving
:leaving   --[door_closed + requests remain]----------> :moving
:leaving   --[door_closed + no requests]--------------> :idle
:leaving   --[obstruction during close]--------------->  :docked
```

---

## Implementation Chunks

Work through these chunks in order. Each chunk ends with a commit.
**Never move to the next chunk until all tests pass.**

---

### Chunk 1 — Add `phase` field alongside `status`

**Goal**: Introduce `phase` without breaking anything.

- In `lib/elevator/core.ex`, add `phase: :idle` to the `defstruct`
- Add `:rehoming | :moving | :arriving | :docked | :leaving | :idle` to the `@type t`
- No logic changes whatsoever
- Run `mix test` — all tests must pass
- Commit: `Add phase field to Elevator.Core struct`

---

### Chunk 2 — Migrate struct construction in tests

**Goal**: All test files use `phase:` instead of `status:` in state construction,
while both fields still coexist.

- Search all test files for `status:` in `%Core{}` struct literals and replace with `phase:`
- Mapping:
  - `status: :normal` → `phase: :idle` (or `:moving` if motor is running in that test)
  - `status: :rehoming` → `phase: :rehoming`
  - `status: :overload` → remove (will be handled in Chunk 3)
- Run `mix test` — all tests must pass (overload tests may still pass since `status` still exists)
- Commit: `Migrate test struct construction from status: to phase:`

---

### Chunk 3 — Remove overload

**Goal**: Delete all overload/weight logic and tests.

In `lib/elevator/core.ex`:
- Remove `weight` and `weight_limit` from `defstruct`
- Remove from `@type t`
- Delete functions: `update_weight/2`, `update_overload_status/1`, `remaining_capacity/1`, `set_weight/1`
- Delete `new_freight/0`
- Remove the overload branch from `enforce_safety_overrides/1`
- Simplify `should_stop_at?/2` — remove the `remaining_capacity` check, always stop for both `:car` and `:hall` requests

In test files:
- Delete any test case that references `weight`, `weight_limit`, or `status: :overload`
- These map to old scenarios (full load bypass, weight variant) — delete those tests

In `lib/elevator/controller.ex`:
- Remove any `update_weight` calls

Run `mix test` — all remaining tests must pass.
Commit: `Remove overload and weight logic from Elevator.Core`

---

### Chunk 4 — Remove `status`

**Goal**: Delete the `status` field entirely.

In `lib/elevator/core.ex`:
- Remove `status` from `defstruct`
- Remove from `@type t`
- Replace all remaining references to `state.status` with `state.phase`
  - `status: :rehoming` → `phase: :rehoming`
  - `status: :normal` → `phase: :idle` (or appropriate phase)
- The `update_overload_status/1` function is already gone from Chunk 3

In `lib/elevator/controller.ex`:
- Replace all `state.status` references with `state.phase`

In `lib/elevator_web/live/dashboard_live.ex` and `dashboard_components.ex`:
- Replace display of `status` with `phase`

Run `mix test` — **many tests will now fail**. This is expected and intentional.
The failing tests become the work queue for Chunks 5–N.
Commit: `Remove status field, system now uses phase`

---

### Chunks 5–N — One scenario at a time (RED → GREEN → commit)

Work through the scenarios in the **[`features/`](../features/)** directory in order.
When a scenario is complete, mark it `[x]` in your task list as part of the commit.

**For each scenario:**
1. Read the scenario
2. Find or write the test that covers it — if no test exists, write it first (RED)
3. Implement the phase-gated handler in `Elevator.Core` (GREEN)
4. Run `mix test` — the target test passes, no regressions
5. Mark scenario `[x]` in `doc/scenarios.md`
6. Commit: `Scenario X.Y: <scenario name>`

**If a test fails and has no matching scenario**: flag it — either write the missing
scenario in the `features/` directory first, or delete the test if the behavior is obsolete.

#### Priority order for Chunk 5–N

Start with the phase transition scenarios in the [**`features/`**](../features/) directory as they
directly drive the new handler rewrites. Then work backwards to fix any older
scenarios that depend on the new phase logic.

Suggested order:
1. Homing — these are already well-specified and cover `:rehoming` phase
2. Phase Transitions — new scenarios, drive the core rewrite
3. Happy Path — standard movement
4. Safety Interlocks
5. Manual Overrides
6. LOOK Algorithm
7. Door Management & Timers
8. UI / End-to-End

---

## Key Implementation Notes for Core Rewrite

### Replace `apply_logic` pipeline

The 7-stage pipeline is the root of the problem. Replace it with a single safety net:

```elixir
defp apply_logic(state) do
  state
  |> enforce_the_golden_rule()
end
```

The golden rule should almost never fire. If it does during tests, it indicates
a bug in a phase handler — investigate rather than relying on it.

### Phase-gated handlers (no conditionals)

Each `handle_event` clause should pattern match on `phase` as its primary guard:

```elixir
# Arriving at floor normally — open doors
defp do_handle_event(%Core{phase: :arriving} = state, :motor_stopped, _now) do
  state
  |> fulfill_current_floor_requests()
  |> Map.merge(%{motor_status: :stopped, door_status: :opening})
end

# Rehoming complete — anchor, NO door cycle
defp do_handle_event(%Core{phase: :rehoming} = state, :motor_stopped, _now) do
  %{state | motor_status: :stopped, phase: :idle, heading: :idle}
end

# Doors fully open → :docked
defp do_handle_event(%Core{phase: :arriving} = state, :door_opened, now) do
  %{state | door_status: :open, phase: :docked, last_activity_at: now}
end

# Door closed after leaving — go to :moving or :idle
defp do_handle_event(%Core{phase: :leaving} = state, :door_closed, _now) do
  state = %{state | door_status: :closed}
  if state.heading != :idle do
    %{state | phase: :moving, motor_status: :running}
  else
    %{state | phase: :idle}
  end
end

# Obstruction while leaving — revert to docked
defp do_handle_event(%Core{phase: :leaving} = state, :door_obstructed, _now) do
  %{state | door_sensor: :blocked, door_status: :open, phase: :docked}
end

# Door timeout while docked → start leaving
defp do_handle_event(%Core{phase: :docked, door_sensor: :clear} = state, :door_timeout, _now) do
  %{state | door_status: :closing, phase: :leaving}
end
```

### `request_floor` phase guard

```elixir
# Ignore requests during rehoming
def request_floor(%Core{phase: :rehoming} = state, _source, _floor), do: {state, []}

# Same-floor request while idle — open door immediately
def request_floor(%Core{phase: :idle} = state, source, floor) do
  state = add_request(state, source, floor)
  new_state =
    if floor == state.current_floor do
      state
      |> fulfill_current_floor_requests()
      |> Map.merge(%{door_status: :opening, phase: :arriving})
    else
      state
      |> update_heading()
      |> Map.merge(%{phase: :moving, motor_status: :running})
    end
  {new_state, derive_actions(state, new_state)}
end
```

### `process_arrival` phase guards

```elixir
# Rehoming: physical arrival → start braking, phase stays :rehoming until :motor_stopped
def process_arrival(%Core{phase: :rehoming} = state, floor) do
  new_state = %{state | current_floor: floor, motor_status: :stopping}
  {new_state, derive_actions(state, new_state)}
end

# Normal movement: check if this is a target floor
def process_arrival(%Core{phase: :moving} = state, floor) do
  new_state = %{state | current_floor: floor}
  new_state =
    if should_stop_at?(new_state, floor) or overshooting?(new_state) do
      %{new_state | motor_status: :stopping, phase: :arriving}
    else
      new_state
    end
  {new_state, derive_actions(state, new_state)}
end
```

---

## Verification (after all chunks complete)

1. `mix test` — all tests pass, all scenarios marked `[x]`
2. `mix phx.server` — start the app, open dashboard
3. Manual journey: F0 → F3 via dashboard ([S-UI-JOURNEY])
4. Reset via dashboard → verify rehoming completes without door cycle
5. Confirm no `enforce_the_golden_rule` warnings appear in logs during normal operation
