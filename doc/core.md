# Elevator Core (The Brain)

The `Elevator.Core` is the **Functional Core** of the system. It contains the pure, side-effect-free decision logic (the "Brain"). It manages the internal state and dictates movement and safety through a set of declarative actions.

## State Machine

The core is governed by a formal Phase State Machine. To ensure consistency across the system, all phases and transitions are defined in a single source of truth:

---
> See [states.md](doc/states.md) for the formal Phase Definitions, Transition Ledger, and State Diagrams.
---

### Phase Gating

All event handling in the Core is primary guarded by the current phase. Illegal events for a given phase are ignored to maintain safety invariants.

## Internal State

The state is managed via the `%Elevator.Core{}` struct:

| Field | Type | Description |
| :--- | :--- | :--- |
| `current_floor` | `integer() \| :unknown` | Current logical floor position. |
| `phase` | `atom()` | Current operational phase (see table above). |
| `heading` | `:up \| :down \| :idle` | Movement intention (independent of motor). |
| `motor_status` | `atom()` | Physical motor status: `:running`, `:crawling`, `:stopping`, `:stopped`. |
| `door_status` | `atom()` | Physical door status: `:open`, `:opening`, `:closing`, `:closed`, `:obstructed`. |
| `door_sensor` | `:clear \| :blocked` | Real-time status of the door safety beam. |
| `requests` | `list({atom(), integer()})` | Active queue of `{:car \| :hall, floor}` requests. |
| `last_activity_at` | `integer()` | Timestamp (ms) of the last significant event. |

## Public API

### Primary Entry Points

- `request_floor(state, source, floor)`: Adds a request and determines if movement should begin.
- `handle_event(state, event, now)`: Processes hardware confirmations and timeouts.
- `handle_button_press(state, button, now)`: Processes manual door overrides.
- `process_arrival(state, floor)`: Handles physical floor sensor triggers.

## Actions (The Output)

Every state transition returns a list of actions for the **Controller** to execute:

| Action | Description |
| :--- | :--- |
| `{:move, direction}` | Move the motor at normal speed. |
| `{:crawl, direction}` | Move the motor at slow speed. |
| `{:stop_motor}` | Begin motor braking. |
| `{:open_door}` | Begin opening the doors. |
| `{:close_door}` | Begin closing the doors. |
| `{:set_timer, id, ms}` | Schedule a future event (e.g., `:door_timeout`). |
| `{:cancel_timer, id}` | Cancel a scheduled timer. |

## Assumptions & Safety

1. **Golden Rule (Structural Safety)**: The Core will force the motor status to `:stopped` if it detects an illegal state (motor running with doors open).
2. **Phase Gating**: All event handling is primary guarded by the current `phase`.
3. **Idempotency**: Adding a request that is already queued or already satisfied is ignored by the controller before reaching the Core.
