# Scenario Catalog

A flat index of every named scenario across all feature files.
One row per scenario: tag(s), phase transition, plain-English description.

Keep in sync when scenarios are added or renamed.

---

## core.feature — Elevator Core State Machine

| Tag | Transition | Description |
|-----|-----------|-------------|
| — | `:booting → :opening` | Warm start: vault matches sensor, door opens immediately |
| — | `:booting → :rehoming` | Cold start: vault unknown, motor crawls down to find position |
| — | `:rehoming → :arriving` | Floor sensor triggered while crawling, motor begins stopping |
| `@S-PHASE-IDLE-MOVE` | `:idle → :leaving` | Car request for a different floor starts movement |
| `@S-PHASE-IDLE-ARRIVE` | `:idle → :opening` | Hall request for the current floor opens door immediately |
| `@S-PHASE-IDLE-INACTIVITY` | `:idle → :leaving` | Inactivity timeout returns elevator to base floor |
| `@S-PHASE-MOVE-ARRIVE` | `:moving → :arriving` | Target floor reached, motor begins stopping |
| `@S-PHASE-MOVE-ARRIVE` | `:arriving → :opening` | Motor confirms stopped, door begins opening |
| `@S-PHASE-ARRIVE-DOCK` | `:opening → :docked` | Door confirms open, door timeout timer started |
| — | `:docked → :closing` | Door timeout expires, door begins closing |
| — | `:docked → :closing` | Door-close button pressed, door begins closing |
| `@S-PHASE-DOCK-LEAVE` | `:closing → :leaving` | Door closed with pending requests, motor starts |
| `@S-PHASE-LEAVE-ARRIVE` | `:closing → :opening` | Door obstructed while closing, door reopens |
| `@S-PHASE-LEAVE-IDLE` | `:closing → :idle` | Door closed with no pending requests, elevator idles |
| `@S-PHASE-LEAVE-MOVE` | `:leaving → :moving` | Motor confirms running, elevator is moving |
| `@S-BOOT-BLOCK-REQ` | — | Floor requests are silently dropped during booting and rehoming |
| `@S-BOOT-BLOCK-BUTTON` | — | Button presses produce no action during booting and rehoming |

---

## core-factories.feature — Factory State Assertions

| Tag | Transition | Description |
|-----|-----------|-------------|
| — | — | `idle_at(3)`: motor stopped, door closed, heading idle, queue empty |
| — | — | `docked_at(3)`: motor stopped, door open, heading idle, queue empty |
| — | — | `moving_to(2, 3)`: motor running, door closed, heading up, queue has floor 3 |
| — | — | `booting()`: motor stopped, door closed, floor unknown |
| — | — | `rehoming()`: motor crawling, door closed, floor unknown |

---

## manual_control.feature — Manual Door Control

| Tag | Transition | Description |
|-----|-----------|-------------|
| `@S-MANUAL-OPEN-WIN` | `:closing → :opening` | Door-open button overrides an in-progress close |
| `@S-MANUAL-CLOSE` | `:docked → :closing` | Door-close button closes door immediately, cancelling timer |
| `@S-MANUAL-EXTEND` | — | Door-open button while docked resets the door timeout timer |

---

## sweep.feature — LOOK Algorithm

| Tag | Transition | Description |
|-----|-----------|-------------|
| — | — | New sweep starts empty with idle heading |
| — | — | `next_stop` is idempotent: calling it multiple times returns the same value |
| — | — | Adding then servicing a request returns sweep to empty/idle |
| — | — | Heading becomes `:up` when request is above current floor |
| — | — | Heading becomes `:down` when request is below current floor |
| — | — | Duplicate requests for the same floor are ignored |
| — | — | Request for the current floor does not change heading |
| — | — | `next_stop` advances as floors are serviced |
| — | — | Requests persist until explicitly serviced |
| `@S-MOVE-LOOK-SERVICE` | — | Servicing a floor removes both car and hall requests for that floor |
| `@S-MOVE-LOOK-UP` | — | Upward sweep orders ahead-of-car requests first |
| `@S-MOVE-LOOK-DOWN` | — | Downward sweep orders behind-car requests after current sweep completes |
| `@S-MOVE-LOOK-IDLE` | — | First request while idle sets initial heading; restores idle when queue empties |
| `@S-MOVE-LOOK-PRIORITY` | — | Sweep direction is not interrupted once established |
| `@S-MOVE-LOOK-CAR` | — | Car requests on the path of travel are inserted ahead of further stops |
| `@S-MOVE-LOOK-HALL-DEFER` | — | Hall requests in the direction of travel are deferred to the next sweep |
| — | — | Sweep direction is not interrupted by new requests added mid-sweep |
| `@S-MOVE-LOOK-UNKNOWN` | — | Unknown position defaults to downward heading when requests exist |

---

## safety.feature — Elevator Safety

| Tag | Transition | Description |
|-----|-----------|-------------|
| — | — | *(All scenarios currently commented out — pending implementation)* |

---

## system.feature — System Behavior

| Tag | Transition | Description |
|-----|-----------|-------------|
| `@S-SYS-REDUNDANT` | — | Redundant motor commands log a warning and do not re-trigger timers |
| `@S-REQ-SPAM` | — | Duplicate floor requests are silently ignored, no warning logged |
| `@S-SYS-PUBSUB` | — | Any core state change is broadcast over PubSub on `elevator:status` |
| `@S-REQ-CONCURRENCY` | — | Concurrent hall requests are all recorded exactly once, none dropped |

---

## ui.feature — Dashboard UI

| Tag | Transition | Description |
|-----|-----------|-------------|
| `@S-UI-JOURNEY` | `:idle → :moving → :docked` | Full passenger journey: click floor button, elevator travels, door opens on arrival |
