# Elevator System: Complete Scenarios Specification

This document defines the testable reality of our simulation. We use these scenarios to drive our TDD (Red-Green-Refactor) process.

## 1. The "Happy Path" (Standard Movement)

- [x] **Scenario 1.1: Context-Aware Wake Up (Request from IDLE)**
  - **Given**: Elevator is `:idle`, doors are `:closed`.
  - **When**: A request is received.
  - **Then**: `requests` includes the new request, and heading is chosen based on position:
    - **Sub-case 1.1a (Request above)**: Elevator at F0, request for F3 → `heading: :up`.
    - **Sub-case 1.1b (Request below)**: Elevator at F5, request for F1 → `heading: :down`.

- [x] **Scenario 1.2: Arrival at Target Floor (Braking)**
  - **Given**: `phase: :moving`, `heading: :up`, `requests` includes `{:car, 3}`, elevator approaching F3.
  - **When**: Sensor confirms arrival at F3 (`process_arrival/2`).
  - **Then**:
    - `phase` becomes `:arriving`.
    - `motor_status` becomes `:stopping` (Immediate intent).
    - Motor receives `:stop_now`.
    - Request stays in queue until motor physically stops.

- [x] **Scenario 1.3: Braking Complete (Door Opening)**
  - **Given**: `phase: :arriving`, `motor_status: :stopping`, request for current floor in queue.
  - **When**: Receive `:motor_stopped` confirmation.
  - **Then**:
    - `phase` stays `:arriving` (transitions to `:docked` only after `:door_opened` — see 1.4).
    - `motor_status` becomes `:stopped`.
    - `door_status` becomes `:opening`.
    - Door receives `:open`.
    - Request is fulfilled (removed from queue).

- [x] **Scenario 1.4: Door Open Confirmation**
  - **Given**: `phase: :arriving`, `door_status: :opening`.
  - **When**: Receive `:door_opened` confirmation.
  - **Then**:
    - `phase` becomes `:docked`.
    - `door_status` becomes `:open`.
    - Auto-close timer is armed (`last_activity_at` updated, `{:set_timer, :door_timeout, 5000}`).

- [x] **Scenario 1.6: Sequence Verification (Intent & Confirmation)**
  - **Given**: `phase: :docked`, `door_status: :open`, `door_sensor: :clear`.
  - **When**: Timeout fires, then hardware confirms close.
  - **Then**:
    - Step 1 (Intent): `door_status` becomes `:closing`, `{:close_door}` action emitted.
    - Step 2 (Confirmation): `door_status` becomes `:closed` on `:door_closed` event.

- [x] **Scenario 1.7: Actor Redundancy (Loud Warnings)**
  - **Given**: System actor (Motor/Door) is already in state X.
  - **When**: Receive redundant internal command to transition to state X.
  - **Then**: Log a `Logger.warning` (Audit Trail) and do NOT re-trigger hardware timers.

- [x] **Scenario 1.8: Button Spamming (Silent Idempotency)**
  - **Given**: The `requests` list already contains a request for Floor X.
  - **When**: Any additional external request for Floor X is received.
  - **Then**: The system ignores it SILENTLY. No warnings are logged.

- [x] **Scenario 1.9: Observable State Change (Broadcasting)**
  - **Given**: Any change occurs in the `Elevator.Core` state.
  - **When**: The `Controller` processes the change.
  - **Then**: The new state is broadcasted over PubSub to the `"elevator:status"` topic.

- [x] **Scenario 1.10: Return to Base (Inactivity Timeout)**
  - **Given**: Elevator is `phase: :idle` with no pending requests.
  - **When**: 5 minutes (300s) pass without any activity.
  - **Then**: A `{:car, 0}` request is automatically added, sending the elevator back to Floor 0 (ground floor).

- [x] **Scenario 1.11: Concurrent Requests (Race Condition Safety)**
  - **Given**: Elevator is idle.
  - **When**: Multiple hall requests for different floors arrive simultaneously (e.g. from parallel processes).
  - **Then**: All requests are recorded exactly once in the `requests` queue — no drops, no duplicates.

## 2. Safety Interlocks & Sensors

- [x] **Scenario 2.1: Door Obstruction**
  - **Given**: `phase: :leaving`, `door_status: :closing`.
  - **When**: Receive `:door_obstructed`.
  - **Then**: `door_status` transitions back to `:opening`, `door_sensor` becomes `:blocked`, `phase` reverts to `:docked`.

- [x] **Scenario 2.4: Hardware Safety Interlock (The Golden Rule)**
  - **Given**: Elevator is at F0, state is `:idle`, doors are `:open`.
  - **When**: Request for F3 is received.
  - **Then**: 
    - **Motor MUST stay `:stopped`** while doors are `:opening`, `:open`, or `:closing`.
    - Motor is ONLY commanded to `:move` AFTER the `:motor_stopped` and `:door_closed` signals are confirmed.
    - *(Door closing is governed by the 5s timer — see Scenario 7.4)*

- [x] **Scenario 2.5: Door Sensor Cleared**
  - **Given**: `door_sensor` is `:blocked`.
  - **When**: Receive `:door_cleared`.
  - **Then**: `door_sensor` becomes `:clear`.

## 3. Manual Overrides (Door Control)

- [x] **Scenario 3.0: Manual Door Open from Closed**
  - **Given**: `phase: :idle`, `door_status: :closed`.
  - **When**: Passenger presses the `<|>` (door open) button.
  - **Then**: `door_status` transitions to `:opening` and door receives `:open` command.

- [x] **Scenario 3.1: "Door Open Button Wins"**
  - **Given**: `phase: :leaving`, `door_status: :closing`.
  - **When**: Passenger presses the `<|>` (door open) button.
  - **Then**: Discard the closing attempt, `door_status` transitions back to `:opening`.

- [x] **Scenario 3.2: Reset Auto-Close Timer**
  - **Given**: `phase: :docked`, `door_status: :open`.
  - **When**: Passenger presses the `<|>` (door open) button.
  - **Then**: `last_activity_at` is updated, auto-close timer restarted (`{:set_timer, :door_timeout, 5000}`).

## 4. Directional Bias & Priority (The LOOK Algorithm)

- [x] **Scenario 4.1: Pick-up on the Way (Sweep)**
  - **Given**: `phase: :moving`, heading `:up`, request for F5 in queue.
  - **When**: Hall request for F3 added, sensor confirms arrival at F3.
  - **Then**: `phase` becomes `:arriving`, `motor_status` becomes `:stopping`.

- [x] **Scenario 4.2: Reverse or Retire**
  - **Given**: `phase: :arriving` at F3, only request is `{:car, 3}`.
  - **When**: `motor_stopped` received (request fulfilled).
  - **Then**:
    - `heading` stays `:up` (updated only when next direction is chosen).
    - If a new request arrives below → `heading` becomes `:down`.

- [x] **Scenario 4.4: Honor All Requests**
  - **Given**: `phase: :moving`, a `{:car, floor}` or `{:hall, floor}` request exists on the path.
  - **When**: `process_arrival` at that floor.
  - **Then**: `phase` becomes `:arriving`, `motor_status` becomes `:stopping` — all request types honored.

- [x] **Scenario 4.6: Same-Floor Interaction**
  - **Given**: `phase: :idle`, `door_status: :closed`, elevator at F3.
  - **When**: Receive `{:car, 3}` or `{:hall, 3}`.
  - **Then**:
    - `phase` becomes `:arriving`.
    - Request is immediately fulfilled (removed from queue).
    - `motor_status` stays `:stopped` (no braking cycle needed).
    - `door_status` becomes `:opening`, door receives `:open` command.
  - **Note**: The `:stopping` protocol only applies when the motor is actually `:running`. Sending a redundant stop to hardware that is already stopped causes a deadlock — no `:motor_stopped` confirmation is ever returned.

- [x] **Scenario 4.3: Multi-Stop Sweep Ordering**
  - **Given**: `phase: :idle` at F0, car requests for F2, F4, and F6.
  - **When**: Elevator moves upward through each floor (`process_arrival`).
  - **Then**: Stops are made in ascending order — F2 first, then F4, then F6. Each arrival sets `phase: :arriving`, `motor_status: :stopping`. No floor is skipped.

- [x] **Scenario 4.8: Boundary Reversals**
  - **Given**: `phase: :idle`, elevator at F5 (top), heading `:up`, no requests above.
  - **When**: Same-floor request triggers heading update.
  - **Then**: `heading` becomes `:idle` — never goes higher than the top floor.

- [x] **Scenario 4.9: Request Fulfillment (Internal Core Sync)**
  - **Given**: `phase: :arriving` at F3, requests `[{:car, 3}, {:car, 0}]`.
  - **When**: `motor_stopped` received (fulfills F3), then a new request for F0 triggers heading recalculation.
  - **Then**:
    - `{:car, 3}` is cleared from the queue.
    - `heading` becomes `:down` to reach F0.

---

## 5. Homing & Crash Recovery

- [x] **Scenario 5.1: Cold Start (No Persistence)**
  - **Given**: `Elevator.Vault` is empty.
  - **When**: System starts.
  - **Then**:
    - `phase` is `:rehoming`.
    - `heading` is `:down`, `motor_speed` is `:crawling`.
    - `current_floor` is `:unknown`.

- [x] **Scenario 5.2: Mid-Floor Recovery (Zero-Move)**
  - **Given**: `Elevator.Vault` stores `Floor 3` AND `Elevator.Sensor` is currently at `Floor 3`.
  - **When**: System reboots (e.g., after a crash).
  - **Then**:
    - `phase` transitions `:rehoming` -> `:idle` immediately.
    - No motor movement is triggered.

- [x] **Scenario 5.3: Recovery between floors (Move-to-Physical)**
  - **Given**: `Elevator.Vault` says `Floor 3` but `Elevator.Sensor` is `:unknown` (or mismatches).
  - **When**: System reboots.
  - **Then**:
    - `phase` is `:rehoming`.
    - `heading` is `:down`, `motor_speed` is `:crawling`.
    - Move until physical sensor confirms arrival.

- [x] **Scenario 5.4: Homing Completion (Anchoring)**
  - **Given**: `phase` is `:rehoming`.
  - **When**: Core receives its very first `{:floor_arrival, floor}` event.
  - **Then**:
    - `heading` MUST immediately transition to `:idle` (Anchoring).
    - `motor_status` becomes `:stopping` (Drop the anchor).
    - `door_status` stays `:closed`. No door cycle is triggered.
    - `phase` stays `:rehoming` until `:motor_stopped` is confirmed.
    - `Vault` is updated with `Floor X`.

- [x] **Scenario 5.6: No Door Cycle on Homing Arrival**
  - **Given**: `phase` is `:rehoming`, `door_status` is `:closed`.
  - **When**: `:motor_stopped` is received after homing arrival.
  - **Then**:
    - `phase` transitions to `:idle`.
    - `door_status` remains `:closed`. No `:open_door` command is issued to hardware.
  - **Rationale**: The homing move is a calibration move. No passenger requested this floor; opening the doors would be incorrect and would add an unnecessary 5s delay before the system can service real requests.

- [x] **Scenario 5.5: Request Blocking during Rehoming**
  - **Given**: Elevator is in `phase: :rehoming`.
  - **When**: Receive any external/internal floor request.
  - **Then**: The request is ignored and NOT added to the queue.

---

## 6. Hardware Protocols (Shims & Drivers)

- [x] **Scenario 6.1: Motor Movement Protocol**
  - **Given**: Motor receives a `:move` command.
  - **When**: Command includes `direction` and `speed`.
  - **Then**: Internal hardware state accurately reflects these parameters.

- [x] **Scenario 6.2: Door Operation Protocol**
  - **Given**: Door receives an `:open` or `:close` command.
  - **When**: Operation begins.
  - **Then**: Door state transitions to `:opening` or `:closing`.

- [x] **Scenario 6.3: Sensor Floor Tracking**
  - **Given**: Sensor receives a physical floor pulse.
  - **When**: Pulse is received at Floor X.
  - **Then**: Internal hardware state correctly identifies Floor X as the current position.

---

## 7. Door Management & Timers (Refactor)

- [x] **Scenario 7.1: Door Auto-Close Timeout (5s)**
  - **Given**: `phase: :docked`, `door_status: :open`.
  - **When**: 5 seconds (5000ms) pass without activity (`:door_timeout` event).
  - **Then**: 
    - `door_status` becomes `:closing`, `phase` becomes `:leaving`.
    - `{:close_door}` action emitted.
  - **Sub-case 7.1a (Idle Heading)**: Door closes unconditionally when `door_sensor: :clear`, even when `heading: :idle`.
  - **Sub-case 7.1b (Sensor Blocked)**: If `door_sensor: :blocked`, timeout is ignored — door stays open.

- [x] **Scenario 7.2: Manual Close Button Override**
  - **Given**: `phase: :docked`, `door_status: :open`, pending requests exist.
  - **When**: Passenger presses the `>|<` (door close) button.
  - **Then**: 
    - `door_status` becomes `:closing` immediately.
    - `{:close_door}` and `{:cancel_timer, :door_timeout}` actions emitted.

- [x] **Scenario 7.3: Activity Extension (Open Button)**
  - **Given**: `phase: :docked`, `door_status: :open`.
  - **When**: Passenger presses the `<|>` (door open) button at T=1000.
  - **Then**: 
    - `last_activity_at` is updated to T=1000.
    - `{:set_timer, :door_timeout, 5000}` emitted — timer restarts.
  - **Note**: Covered by Scenario 3.2 test.

- [x] **Scenario 7.4: Service Delay (Auto-Close Integration)**
  - **Given**: `phase: :docked` at F1, doors open, new request for F5 received.
  - **When**: Request is added.
  - **Then**: 
    - Heading becomes `:up`.
    - Door stays open until 5s timer fires — only then does `:closing` begin.

---

## 8. Phase Transitions

- [x] **Scenario 8.1: :idle → :moving (Request with closed doors)**
  - **Given**: `phase: :idle`, `door_status: :closed`, elevator at F0.
  - **When**: Request for F3 received.
  - **Then**: `phase` becomes `:moving`, `motor_status` becomes `:running`, `heading` becomes `:up`.

- [x] **Scenario 8.2: :moving → :arriving (Target floor reached)**
  - **Given**: `phase: :moving`, `heading: :up`, request for F3.
  - **When**: `floor_arrival` at F3.
  - **Then**: `phase` becomes `:arriving`, `motor_status` becomes `:stopping`.

- [x] **Scenario 8.3: :arriving → :docked (Doors confirm open)**
  - **Given**: `phase: :arriving`, `motor_status: :stopped`, `door_status: :opening`.
  - **When**: `:door_opened` received.
  - **Then**: `phase` becomes `:docked`, `door_status` becomes `:open`, door timeout timer is set.

- [x] **Scenario 8.4: :docked → :leaving (Timeout fires)**
  - **Given**: `phase: :docked`, `door_status: :open`, `door_sensor: :clear`.
  - **When**: `:door_timeout` received.
  - **Then**: `phase` becomes `:leaving`, `door_status` becomes `:closing`.

- [x] **Scenario 8.5: :leaving → :moving (Door closed, requests remain)**
  - **Given**: `phase: :leaving`, pending requests exist.
  - **When**: `:door_closed` received.
  - **Then**: `phase` becomes `:moving`, `motor_status` becomes `:running`.

- [x] **Scenario 8.6: :leaving → :idle (Door closed, no requests)**
  - **Given**: `phase: :leaving`, no pending requests.
  - **When**: `:door_closed` received.
  - **Then**: `phase` becomes `:idle`, `motor_status` stays `:stopped`.

- [x] **Scenario 8.7: :leaving → :docked (Obstruction during close)**
  - **Given**: `phase: :leaving`, `door_status: :closing`.
  - **When**: `:door_obstructed` received.
  - **Then**: `phase` reverts to `:docked`, `door_status` becomes `:open`.

## 9. UI / End-to-End (Dashboard)

- [x] **Scenario 9.1: Full Journey from F0 to F3 via Dashboard**
  - **Given**:
    - Dashboard is loaded and LiveView is connected.
    - `phase` is `:idle` (rehoming is complete, displayed as `"IDLE"` in the footer).
    - `motor_status` is `:stopped`.
    - `current_floor` is **F0** (elevator is confirmed at ground floor).
  - **When**: User clicks the Floor 3 button on the car panel (`#label-3`).
  - **Then**:
    1. `#label-3` receives class `pending` or `targeting`.
    2. Activity log contains `"Controller: Floor 3"`.
    3. Digital indicator transitions to `"3"` (within 20s — 3 floors × ~2s/floor + buffer).
    4. `door_status` becomes `OPEN` (before the 5s auto-close fires).
    5. `#elevator-car` receives class `doors-open`.
    6. Visual center of `#elevator-car` aligns with visual center of `#label-3` within 15px.
  - **Test**: Playwright (`tests/ui/happy_path.spec.ts`), run via `mix test-gui`.
  - **Precondition note**: The test uses `/test/reset` to rehome the elevator and asserts `IDLE` + floor `0` before interacting.
