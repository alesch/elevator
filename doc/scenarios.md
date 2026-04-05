# Elevator System: Complete Scenarios Specification

This document defines the testable reality of our simulation. We use these scenarios to drive our TDD (Red-Green-Refactor) process.

## 1. The "Happy Path" (Standard Movement)

- [x] **Scenario: Context-Aware Wake Up (Request from IDLE) [S-MOVE-WAKEUP]**
  - **Rules Covered**: `[R-MOVE-WAKEUP]`, `[R-CORE-STATE]`
  - **Given**: Elevator is `:idle`, doors are `:closed`.
  - **When**: A request is received.
  - **Then**: `requests` includes the new request, and heading is chosen based on position:
    - **Sub-case A (Request above)**: Elevator at F0, request for F3 → `heading: :up`.
    - **Sub-case B (Request below)**: Elevator at F5, request for F1 → `heading: :down`.

- [x] **Scenario: Arrival at Target Floor (Braking) [S-MOVE-BRAKING]**
  - **Rules Covered**: `[R-SAFE-ARRIVAL]`
  - **Given**: `phase: :moving`, `heading: :up`, `requests` includes `{:car, 3}`, elevator approaching F3.
  - **When**: Sensor confirms arrival at F3 (`process_arrival/2`).
  - **Then**:
    - `phase` becomes `:arriving`.
    - `motor_status` becomes `:stopping` (Immediate intent).
    - Motor receives `:stop_now`.
    - Request stays in queue until motor physically stops.

- [x] **Scenario: Braking Complete (Door Opening) [S-MOVE-OPENING]**
  - **Rules Covered**: `[R-SAFE-ARRIVAL]`
  - **Given**: `phase: :arriving`, `motor_status: :stopping`, request for current floor in queue.
  - **When**: Receive `:motor_stopped` confirmation.
  - **Then**:
    - `phase` stays `:arriving` (transitions to `:docked` only after `:door_opened`).
    - `motor_status` becomes `:stopped`.
    - `door_status` becomes `:opening`.
    - Door receives `:open`.
    - Request is fulfilled (removed from queue).

- [x] **Scenario: Door Open Confirmation [S-MOVE-DOCKED]**
  - **Rules Covered**: `[R-CORE-STATE]`, `[R-SAFE-TIMEOUT]`
  - **Given**: `phase: :arriving`, `door_status: :opening`.
  - **When**: Receive `:door_opened` confirmation.
  - **Then**:
    - `phase` becomes `:docked`.
    - `door_status` becomes `:open`.
    - Auto-close timer is armed (`last_activity_at` updated, `{:set_timer, :door_timeout, 5000}`).

- [x] **Scenario: Sequence Verification (Intent & Confirmation) [S-MOVE-CLOSING]**
  - **Rules Covered**: `[R-CORE-STATE]`
  - **Given**: `phase: :docked`, `door_status: :open`, `door_sensor: :clear`.
  - **When**: Timeout fires, then hardware confirms close.
  - **Then**:
    - Step 1 (Intent): `door_status` becomes `:closing`, `{:close_door}` action emitted.
    - Step 2 (Confirmation): `door_status` becomes `:closed` on `:door_closed` event.

- [x] **Scenario: Actor Redundancy (Loud Warnings) [S-SYS-REDUNDANT]**
  - **Rules Covered**: `[R-CORE-PURE]`
  - **Given**: System actor (Motor/Door) is already in state X.
  - **When**: Receive redundant internal command to transition to state X.
  - **Then**: Log a `Logger.warning` (Audit Trail) and do NOT re-trigger hardware timers.

- [x] **Scenario: Button Spamming (Silent Idempotency) [S-REQ-SPAM]**
  - **Rules Covered**: `[R-REQ-TAGS]`
  - **Given**: The `requests` list already contains a request for Floor X.
  - **When**: Any additional external request for Floor X is received.
  - **Then**: The system ignores it SILENTLY. No warnings are logged.

- [x] **Scenario: Observable State Change (Broadcasting) [S-SYS-PUBSUB]**
  - **Rules Covered**: `[R-CORE-SHELL]`
  - **Given**: Any change occurs in the `Elevator.Core` state.
  - **When**: The `Controller` processes the change.
  - **Then**: The new state is broadcasted over PubSub to the `"elevator:status"` topic.

- [x] **Scenario: Return to Base (Inactivity Timeout) [S-MOVE-BASE]**
  - **Rules Covered**: `[R-MOVE-BASE]`
  - **Given**: Elevator is `phase: :idle` with no pending requests.
  - **When**: 5 minutes (300s) pass without any activity.
  - **Then**: A `{:car, 0}` request is automatically added, sending the elevator back to Floor 0.

- [x] **Scenario: Concurrent Requests (Race Condition Safety) [S-REQ-CONCURRENCY]**
  - **Rules Covered**: `[R-REQ-TAGS]`
  - **Given**: Elevator is idle.
  - **When**: Multiple hall requests for different floors arrive simultaneously.
  - **Then**: All requests are recorded exactly once in the `requests` queue — no drops, no duplicates.

## 2. Safety Interlocks & Sensors

- [x] **Scenario: Door Obstruction [S-SAFE-OBSTRUCT]**
  - **Rules Covered**: `[R-SAFE-OBSTRUCT]`
  - **Given**: `phase: :leaving`, `door_status: :closing`.
  - **When**: Receive `:door_obstructed`.
  - **Then**: `door_status` transitions back to `:opening`, `door_sensor` becomes `:blocked`, `phase` reverts to `:docked`.

- [x] **Scenario: Hardware Safety Interlock (The Golden Rule) [S-SAFE-GOLDEN]**
  - **Rules Covered**: `[R-SAFE-GOLDEN]`
  - **Given**: Elevator is at F0, state is `:idle`, doors are `:open`.
  - **When**: Request for F3 is received.
  - **Then**: 
    - **Motor MUST stay `:stopped`** while doors are `:opening`, `:open`, or `:closing`.
    - Motor is ONLY commanded to `:move` AFTER the `:motor_stopped` and `:door_closed` signals are confirmed.

- [x] **Scenario: Door Sensor Cleared [S-SAFE-CLEARED]**
  - **Rules Covered**: `[R-SAFE-OBSTRUCT]`
  - **Given**: `door_sensor` is `:blocked`.
  - **When**: Receive `:door_cleared`.
  - **Then**: `door_sensor` becomes `:clear`.

## 3. Manual Overrides (Door Control)

- [x] **Scenario: Manual Door Open from Closed [S-MANUAL-OPEN-IDLE]**
  - **Rules Covered**: `[R-SAFE-MANUAL]`
  - **Given**: `phase: :idle`, `door_status: :closed`.
  - **When**: Passenger presses the `<|>` (door open) button.
  - **Then**: `door_status` transitions to `:opening` and door receives `:open` command.

- [x] **Scenario: "Door Open Button Wins" [S-MANUAL-OPEN-WIN]**
  - **Rules Covered**: `[R-SAFE-MANUAL]`
  - **Given**: `phase: :leaving`, `door_status: :closing`.
  - **When**: Passenger presses the `<|>` (door open) button.
  - **Then**: Discard the closing attempt, `door_status` transitions back to `:opening`.

- [x] **Scenario: Reset Auto-Close Timer [S-MANUAL-RESET-TIMER]**
  - **Rules Covered**: `[R-SAFE-MANUAL]`
  - **Given**: `phase: :docked`, `door_status: :open`.
  - **When**: Passenger presses the `<|>` (door open) button.
  - **Then**: `last_activity_at` is updated, auto-close timer restarted (`{:set_timer, :door_timeout, 5000}`).

## 4. Directional Bias & Priority (The LOOK Algorithm)

- [x] **Scenario: Pick-up on the Way (Sweep) [S-MOVE-SWEEP-UP]**
  - **Rules Covered**: `[R-MOVE-SWEEP]`
  - **Given**: `phase: :moving`, heading `:up`, request for F5 in queue.
  - **When**: Hall request for F3 added, sensor confirms arrival at F3.
  - **Then**: `phase` becomes `:arriving`, `motor_status` becomes `:stopping`.

- [x] **Scenario: Reverse or Retire [S-MOVE-REVERSE]**
  - **Rules Covered**: `[R-MOVE-SWEEP]`
  - **Given**: `phase: :arriving` at F3, only request is `{:car, 3}`.
  - **When**: `motor_stopped` received (request fulfilled).
  - **Then**:
    - `heading` stays `:up` until a new direction is chosen.
    - If a new request arrives below → `heading` becomes `:down`.

- [x] **Scenario: Honor All Requests [S-REQ-HONOR-ALL]**
  - **Rules Covered**: `[R-REQ-TAGS]`
  - **Given**: `phase: :moving`, a `{:car, floor}` or `{:hall, floor}` request exists on the path.
  - **When**: `process_arrival` at that floor.
  - **Then**: `phase` becomes `:arriving`, `motor_status` becomes `:stopping` — all request types honored.

- [x] **Scenario: Same-Floor Interaction [S-MOVE-SAME-FLOOR]**
  - **Rules Covered**: `[R-MOVE-WAKEUP]`
  - **Given**: `phase: :idle`, `door_status: :closed`, elevator at F3.
  - **When**: Receive `{:car, 3}` or `{:hall, 3}`.
  - **Then**:
    - `phase` becomes `:arriving`.
    - Request is immediately fulfilled.
    - `motor_status` stays `:stopped`.
    - `door_status` becomes `:opening`, door receives `:open` command.

- [x] **Scenario: Multi-Stop Sweep Ordering [S-MOVE-MULTI-STOP]**
  - **Rules Covered**: `[R-MOVE-SWEEP]`
  - **Given**: `phase: :idle` at F0, car requests for F2, F4, and F6.
  - **When**: Elevator moves upward through each floor (`process_arrival`).
  - **Then**: Stops are made in ascending order — F2, then F4, then F6.

- [x] **Scenario: Boundary Reversals [S-MOVE-BOUNDARY]**
  - **Rules Covered**: `[R-MOVE-SWEEP]`
  - **Given**: `phase: :idle`, elevator at F5 (top), heading `:up`, no requests above.
  - **When**: Same-floor request triggers heading update.
  - **Then**: `heading` becomes `:idle` — never goes higher than the top floor.

- [x] **Scenario: Request Fulfillment (Internal Core Sync) [S-REQ-SYNC]**
  - **Rules Covered**: `[R-REQ-TAGS]`
  - **Given**: `phase: :arriving` at F3, requests `[{:car, 3}, {:car, 0}]`.
  - **When**: `motor_stopped` received (fulfills F3).
  - **Then**: `{:car, 3}` is cleared from the queue, `heading` becomes `:down`.

## 5. Homing & Crash Recovery

- [x] **Scenario: Cold Start (No Persistence) [S-HOME-COLD]**
  - **Rules Covered**: `[R-HOME-STRATEGY]`
  - **Given**: `Elevator.Vault` is empty.
  - **When**: System starts.
  - **Then**: `phase` is `:rehoming`, `heading` is `:down`, `current_floor` is `:unknown`.

- [x] **Scenario: Mid-Floor Recovery (Zero-Move) [S-HOME-ZERO]**
  - **Rules Covered**: `[R-HOME-STRATEGY]`
  - **Given**: `Vault` stores `Floor 3` AND `Sensor` is currently at `Floor 3`.
  - **When**: System reboots.
  - **Then**: `phase` transitions `:rehoming` -> `:idle` immediately.

- [x] **Scenario: Recovery between floors (Move-to-Physical) [S-HOME-MOVE]**
  - **Rules Covered**: `[R-HOME-STRATEGY]`
  - **Given**: `Vault` says `Floor 3` but `Sensor` is `:unknown`.
  - **When**: System reboots.
  - **Then**: `phase` is `:rehoming`, `heading` is `:down`, move until arrival.

- [x] **Scenario: Homing Completion (Anchoring) [S-HOME-ANCHOR]**
  - **Rules Covered**: `[R-HOME-STRATEGY]`
  - **Given**: `phase` is `:rehoming`.
  - **When**: Core receives its very first `{:floor_arrival, floor}` event.
  - **Then**: `heading` becomes `:idle`, `motor_status` becomes `:stopping`, `Vault` is updated.

- [x] **Scenario: No Door Cycle on Homing Arrival [S-HOME-NO-DOOR]**
  - **Rules Covered**: `[R-HOME-STRATEGY]`
  - **Given**: `phase` is `:rehoming`, `door_status" is ":closed".
  - **When**: ":motor_stopped" is received after homing arrival.
  - **Then**: `phase` transitions to `:idle`, `door_status` remains `:closed`.

- [x] **Scenario: Request Blocking during Rehoming [S-HOME-BLOCK-REQ]**
  - **Rules Covered**: `[R-HOME-STRATEGY]`
  - **Given**: Elevator is in `phase: :rehoming`.
  - **When**: Receive any floor request.
  - **Then**: The request is ignored.

## 7. Door Management & Timers

- [x] **Scenario: Door Auto-Close Timeout (5s) [S-SAFE-TIMEOUT]**
  - **Rules Covered**: `[R-SAFE-TIMEOUT]`
  - **Given**: `phase: :docked`, `door_status: :open`, `door_sensor: :clear`.
  - **When**: 5s pass without activity (`:door_timeout`).
  - **Then**: `door_status` becomes `:closing`, `phase` becomes `:leaving`, `{:close_door}` action emitted.

- [x] **Scenario: Manual Close Button Override [S-MANUAL-CLOSE]**
  - **Rules Covered**: `[R-SAFE-MANUAL]`
  - **Given**: `phase: :docked`, `door_status: :open`, pending requests exist.
  - **When**: Passenger presses the `>|<` (door close) button.
  - **Then**: `door_status` becomes `:closing` immediately, timer cancelled.

- [x] **Scenario: Activity Extension (Open Button) [S-MANUAL-EXTEND]**
  - **Rules Covered**: `[R-SAFE-MANUAL]`
  - **Given**: `phase: :docked`, `door_status: :open`.
  - **When**: Passenger presses the `<|>` (door open) button.
  - **Then**: `last_activity_at` is updated, auto-close timer restarted.

- [x] **Scenario: Service Delay (Auto-Close Integration) [S-SAFE-SERVICE-DELAY]**
  - **Rules Covered**: `[R-SAFE-ARRIVAL]`
  - **Given**: `phase: :docked` at F1, doors open, new request for F5 received.
  - **When**: Request is added.
  - **Then**: Heading becomes `:up`, door stays open until 5s timer fires.

## 8. Phase Transitions

- [x] **Scenario: :idle → :moving [S-PHASE-IDLE-MOVE]**
  - **Rules Covered**: `[R-CORE-STATE]`
  - **Given**: `phase: :idle`, `door_status: :closed`, elevator at F0.
  - **When**: Request for F3 received.
  - **Then**: `phase` becomes `:moving`, `motor_status" becomes ":running".

- [x] **Scenario: :moving → :arriving [S-PHASE-MOVE-ARRIVE]**
  - **Rules Covered**: `[R-CORE-STATE]`
  - **Given**: `phase: :moving`, `heading: :up`, request for F3.
  - **When**: `floor_arrival` at F3.
  - **Then**: `phase` becomes `:arriving`, `motor_status" becomes ":stopping".

- [x] **Scenario: :arriving → :docked [S-PHASE-ARRIVE-DOCK]**
  - **Rules Covered**: `[R-CORE-STATE]`
  - **Given**: `phase: :arriving`, `motor_status: :stopped`, `door_status: :opening`.
  - **When**: `:door_opened` received.
  - **Then**: `phase` becomes `:docked`, `door_status" becomes ":open", timer is set.

- [x] **Scenario: :docked → :leaving [S-PHASE-DOCK-LEAVE]**
  - **Rules Covered**: `[R-CORE-STATE]`
  - **Given**: `phase: :docked`, `door_status: :open`, `door_sensor: :clear`.
  - **When**: `:door_timeout` received.
  - **Then**: `phase` becomes `:leaving`, `door_status" becomes ":closing".

- [x] **Scenario: :leaving → :moving [S-PHASE-LEAVE-MOVE]**
  - **Rules Covered**: `[R-CORE-STATE]`
  - **Given**: `phase: :leaving`, pending work exists.
  - **When**: `:door_closed` received.
  - **Then**: `phase` becomes `:moving`, `motor_status" becomes ":running".

- [x] **Scenario: :leaving → :idle [S-PHASE-LEAVE-IDLE]**
  - **Rules Covered**: `[R-CORE-STATE]`
  - **Given**: `phase: :leaving`, no pending requests.
  - **When**: `:door_closed` received.
  - **Then**: `phase` becomes `:idle`, `motor_status` stays `:stopped`.

- [x] **Scenario: :leaving → :docked (Obstruction) [S-PHASE-LEAVE-DOCK]**
  - **Rules Covered**: `[R-CORE-STATE]`
  - **Given**: `phase: :leaving`, `door_status: :closing`.
  - **When**: `:door_obstructed` received.
  - **Then**: `phase reverts to :docked`, `door_status" becomes ":open".

## 9. UI / End-to-End (Dashboard)

- [x] **Scenario: Full Journey F0 to F3 via Dashboard [S-UI-JOURNEY]**
  - **Rules Covered**: `[R-CORE-SHELL]`
  - **Given**: Dashboard is loaded, `phase` is `:idle`, elevator at F0.
  - **When**: User clicks Floor 3 button.
  - **Then**: Indicator transitions to "3", door opens, car aligns with F3.
