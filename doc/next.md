# Handover: Phase Refactor Complete

### Clause ordering is critical

Phase-gated `do_handle_event` and `process_arrival` clauses MUST appear **before** general (unguarded) clauses. Elixir matches top-to-bottom.

### Golden rule is a post-condition, not a pipeline stage

If it fires (logs a warning), a phase handler has a bug — investigate rather than relying on it to mask the problem.

### `process_current_floor` is dead

Always use `Core.process_arrival(state, floor)` for floor arrivals. `process_current_floor` is an old API that bypasses the phase model.

### `:tick` is test-only

Production uses `{:timeout, :door_timeout}` (sent by the Controller after a `{:set_timer, :door_timeout, 5000}` action). Do not write new tests using `:tick`.

### Getting to `:docked` in controller integration tests

```elixir
Controller.request_floor(pid, :car, current_floor)  # same-floor → :arriving, door :opening
assert_receive {:"$gen_cast", :open}
send(pid, :door_opened)                              # → :docked, door :open
assert_receive {:elevator_state, %{phase: :docked}}
```

Do NOT manually send `:motor_stopped` + `:door_opened` from `phase: :idle` — leaves the elevator in a phase-inconsistent state.

### Playwright E2E test

`tests/ui/happy_path.spec.ts` — run via `mix test-gui` (separate from `mix test`).
- Requires `MIX_ENV=e2e mix phx.server` (started automatically by `playwright.config.ts`)
- The `/test/reset` endpoint only exists in `:e2e` mix env

---

## What remains

- Manual door open from `:idle` (`handle_button_press(:door_open)`) does not set `phase: :docked` — the phase stays `:idle` with door `:opening`.
