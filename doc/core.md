# Technical Specification: Elevator Core (The Brain)

The `Elevator.Core` is the **Functional Core** of the system. It contains the pure, side-effect-free decision logic (the "Brain"). It manages the internal state and dictates movement and safety through a set of declarative actions.

## State Machine

The core operates as an explicit **Phase State Machine**:

| Phase | Description | Expected Motor | Expected Door |
| :--- | :--- | :--- | :--- |
| **`:booting`** | Initial synchronization; waiting for hardware discovery. External requests are ignored in this phase. | `:stopped` | `:closed` |
| **`:idle`** | At floor, stationary, no active work. | `:stopped` | `:closed` |
| **`:rehoming`** | Recovering position by moving down slowly. | `:crawling` | `:closed` |
| **`:moving`** | Traveling Toward a target floor at high speed. | `:running` | `:closed` |
| **`:arriving`** | Target reached: motor braking and/or door opening. | `:stopping` | `:opening` |
| **`:docked`** | At floor, doors open, serving passengers. | `:stopped` | `:open` |
| **`:leaving`** | Service complete: door is closing. | `:stopped` | `:closing` |

### Phase Transitions

```mermaid
stateDiagram-v2
    booting: :booting
    rehoming: :rehoming
    idle: :idle
    moving: :moving
    arriving: :arriving
    docked: :docked
    leaving: :leaving

    booting --> :idle : recovery_complete
    booting --> :rehoming : rehoming_started
    rehoming --> :idle : recovery_complete / motor_stopped
    idle --> :moving : request_floor (different floor)
    idle --> :arriving : request_floor (same floor)
    moving --> :arriving : process_arrival (target floor)
    arriving --> :docked : door_opened
    docked --> :leaving : door_timeout / door_close
    leaving --> :moving : door_closed (if requests remain)
    leaving --> :idle : door_closed (if no requests)
    leaving --> :arriving : door_obstructed
```

### Transition Ledger

| From Phase | Trigger (Input) | To Phase | Action (Side Effect) |
| :--- | :--- | :--- | :--- |
| **`:booting`** | `handle_event(:recovery_complete)` | **`:idle`** | None |
| **`:booting`** | `handle_event(:rehoming_started)` | **`:rehoming`** | `{:crawl, :down}` |
| **`:idle`** | `request_floor` (same) | **`:arriving`** | `{:open_door}` |
| **`:idle`** | `request_floor` (diff) | **`:moving`** | `{:move, dir}` |
| **`:rehoming`** | `process_arrival` (F0) | **`:idle`** | `{:stop_motor}` |
| **`:moving`** | `process_arrival` (target) | **`:arriving`** | `{:stop_motor}` |
| **`:arriving`** | `handle_event(:door_opened)` | **`:docked`** | `{:set_timer, :door_timeout, 5000}` |
| **`:docked`** | `handle_event(:door_timeout)` | **`:leaving`** | `{:close_door}` |
| **`:leaving`** | `handle_event(:door_closed)` | **`:moving`** | `{:move, dir}` (if reqs remain) |
| **`:leaving`** | `handle_event(:door_closed)` | **`:idle`** | None (if no reqs remain) |
| **`:leaving`** | `handle_event(:door_obstructed)` | **`:arriving`** | `{:open_door}` |

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

### Internal Logic

- `update_heading(state)`: Recalculates `heading` based on the current floor and request queue.
- `enforce_the_golden_rule(state)`: A safety invariant that ensures the motor is **stopped** if doors are not confirmed closed.

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
