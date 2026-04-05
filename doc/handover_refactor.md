# Handover: Explicit Phase State Machine Refactor

## Status at handover

- **Branch**: `main`
- **Last commit**: `dadfe27 Scenario 8.7: :leaving → :docked on obstruction during close`
- **Tests**: 63 passing, 0 failing
- **Sections complete**: Section 5 (Homing), Section 8 (Phase Transitions)

---

## What was done

The refactor described in `doc/refactor_plan.md` is partially complete.

### Chunks completed (all committed)

| Chunk | Description | Commit |
|:------|:------------|:-------|
| 1 | Add `phase` field to `Core` struct | `d11fb1f` |
| 2 | (No-op — no `status:` struct literals in tests) | — |
| 3 | Remove overload/weight logic entirely | `38e4ac9` |
| 4 | Remove `status` field, uncheck all scenarios | `dd96b17` |
| 5/Section 5 | Homing scenarios 5.1–5.6 | `5dd7599`, `ef14073` |
| 5/Section 8 | Phase transition scenarios 8.1–8.7 | `0989481`–`dadfe27` |

### Key structural changes made to `lib/elevator/core.ex`

- `phase` field added to `defstruct` and `@type t`
- `status` and `weight`/`weight_limit` fields removed
- `new_freight/0`, `update_weight/2`, `update_overload_status/1`, `remaining_capacity/1`, `set_weight/1` deleted
- Phase-gated clauses added (specific before general, pattern matches on `phase`):
  - `request_floor/3` — `:idle` + `door_status: :closed` clause (Scenarios 8.1, 4.6)
  - `process_arrival/2` — `:rehoming` clause (5.4), `:moving` clause (8.2)
  - `do_handle_event/3` — `:rehoming` + `:motor_stopped` (5.6), `:arriving` + `:door_opened` (8.3), `:docked` + `:door_timeout` (8.4), `:leaving` + `:door_closed` (8.5/8.6), `:leaving` + `:door_obstructed` (8.7)
- `controller.ex`: `status: :rehoming` → `phase: :rehoming`, `status: :normal` → `phase: :idle`, removed `new_status` override hack in `floor_arrival` handler
- `dashboard_live.ex` + `dashboard_components.ex`: `state.status` → `state.phase`
- **The 7-stage `apply_logic` pipeline is still in place** — it has NOT been replaced yet. The new phase-gated handlers short-circuit before the pipeline where needed.

---

## What remains

The `apply_logic` pipeline replacement and verification of all remaining scenarios.

### Next priority: Section 1 (Happy Path)

All 9 scenarios unchecked. Most already have passing tests — verify, then check them off.

**Important**: Before checking any scenario as `[x]`, confirm the test actually asserts the `phase` field where relevant (not just `motor_status` / `door_status`). Some older tests predate the `phase` field and may pass without asserting phase transitions.

Suggested check for each scenario:
1. Read the scenario in `doc/scenarios.md`
2. Find the existing test (or write one if missing)
3. Add a `phase` assertion if the scenario implies a phase transition
4. Run `mix test` — green
5. Mark `[x]`, commit: `Scenario X.Y: <name>`

### Remaining sections (in priority order per `refactor_plan.md`)

1. **Section 1** — Happy Path (1.1–1.11, minus 1.5 which was deleted with overload)
2. **Section 2** — Safety Interlocks (2.1, 2.4, 2.5)
3. **Section 3** — Manual Overrides (3.0, 3.1, 3.2)
4. **Section 4** — LOOK Algorithm (4.1, 4.2, 4.3, 4.4, 4.6, 4.8, 4.9)
5. **Section 6** — Hardware Protocols (6.1, 6.2, 6.3)
6. **Section 7** — Door Management & Timers (7.1–7.4)
7. **Section 9** — UI / End-to-End (9.1)

### Final step (after all scenarios green): replace `apply_logic` pipeline

Per `doc/refactor_plan.md`, once all scenarios pass, collapse the 7-stage pipeline:

```elixir
defp apply_logic(state) do
  state |> enforce_the_golden_rule()
end
```

The golden rule should almost never fire during normal operation. If it fires during tests, it indicates a bug in a phase handler. Add a warning when fired.   
At that point, delete all the now-unreachable pipeline stages (`start_rehoming_logic`, `start_servicing_request_logic`, `start_moving_logic`, `stop_moving_logic`, `complete_servicing_request_logic`, `enforce_safety_overrides`).

---

## Important notes for the next agent

### Workflow rules (from `doc/README_FOR_AGENTS.md`)
1. **Plan first** — present an implementation plan, wait for Alex's explicit approval before writing code.
2. **Scenarios → Tests → Code** — every test must cite a Scenario ID.
3. **One scenario at a time** — RED → GREEN → mark `[x]` → commit.
4. **Never move to the next scenario until all tests pass.**

### Key file locations
- `doc/scenarios.md` — source of truth for what scenarios need tests
- `doc/core_rules.md` — rules the Brain must follow
- `doc/refactor_phase_plan.md` — the full refactor plan with code examples
- `test/phase_transitions_test.exs` — new test file for Section 8, created this session
- `lib/elevator/core.ex` — the Brain (pure functional)
- `lib/elevator/controller.ex` — the Servo (imperative shell)

### Known subtlety: motor feedback loop in tests

The homing tests start motor and controller with `name: nil` — neither registers in the global Registry, so the motor cannot find the controller to send `:motor_stopped`. This means integration tests for motor completion must explicitly `send(ctrl, :motor_stopped)` rather than relying on hardware feedback. See `test/homing_test.exs:105–122` for the pattern used.

### Clause ordering matters

Phase-gated `do_handle_event` and `process_arrival` clauses MUST be placed **before** the general (unguarded) clauses in `core.ex`. Elixir matches top-to-bottom. A general clause placed first will always win.
