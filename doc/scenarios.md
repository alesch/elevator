# Elevator System: Complete Scenarios Specification

This document defines the testable reality of our simulation. We use these scenarios to drive our TDD (Red-Green-Refactor) process.

## 1. The "Happy Path" (Standard Movement)

- [x] **Scenario 1.1: Request from IDLE**
  - **Given**: Elevator is at F0, state is `:idle`, doors are `:closed`.
  - **When**: Request for F3 is received from the Hall.
  - **Then**: `heading` becomes `:up`, `requests` includes `{:hall, 3}`.

- [x] **Scenario 1.2: Arrival at Target Floor (Braking & Idle)**
  - **Given**: Elevator is at F3, `heading` is `:up`, `requests` includes `{:car, 3}`.
  - **When**: Sensor confirms arrival at F3.
  - **Then**:
    - `heading` stays `:idle` (Stop intent).
    - `motor_status` becomes `:stopping` (Immediate intent).
    - Motor receives `:stop_now`.

- [x] **Scenario 1.3: Braking Complete (Door Opening)**
  - **Given**: Elevator is at F3, `motor_status` is `:stopping`.
  - **When**: Receive `:motor_stopped` confirmation.
  - **Then**:
    - `motor_status` becomes `:stopped` (Physical confirmation).
    - `door_status` becomes `:opening` (Immediate intent).
    - Door receives `:open`.

- [x] **Scenario 1.4: Door Open Confirmation**
  - **Given**: `door_status` is `:opening`.
  - **When**: Receive `:door_opened` confirmation.
  - **Then**:
    - `door_status` becomes `:open`.
    - Auto-close timer is reset (`last_activity_at` updated).

- [x] **Scenario 1.6: Sequence Verification (Intent & Confirmation)**
  - **When**: Triggered transition `door_status` -> `:closed`.
  - **Then**: `door_status` first becomes `:closing` (Intent), then `:closed` (Physical).

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

## 2. Safety Interlocks & Sensors

- [x] **Scenario 2.1: Door Obstruction**
  - **Given**: Doors are `:closing`.
  - **When**: Receive `:door_sensor_blocked`.
  - **Then**: Immediately transition `door_status` back to `:opening`.

- [x] **Scenario 2.4: Hardware Safety Interlock (The Golden Rule)**
  - **Given**: Elevator is at F0, state is `:idle`, doors are `:open`.
  - **When**: Request for F3 is received.
  - **Then**: 
    - Door is commanded to `:close`.
    - **Motor MUST stay `:stopped`** while doors are `:opening`, `:open`, or `:closing`.
    - Motor is ONLY commanded to `:move` AFTER the `:motor_stopped` and `:door_closed` signals are confirmed.

- [x] **Scenario 2.5: Door Sensor Cleared**
  - **Given**: `door_sensor` is `:blocked`.
  - **When**: Receive `:door_sensor_cleared`.
  - **Then**: `door_sensor` becomes `:clear`.

## 3. Manual Overrides (Door Control)

- [x] **Scenario 3.1: "Door Open Button Wins"**
  - **Given**: Doors are `:closing`.
  - **When**: Receive `:button_pressed, :door_open`.
  - **Then**: Discard the closing attempt, transition back to `:opening`.

- [x] **Scenario 3.2: Reset Auto-Close Timer**
  - **Given**: Doors are `:open`.
  - **When**: Receive `:button_pressed, :door_open`.
  - **Then**: The "Auto-Close" timer is reset (simulated by resetting the `last_activity_at` timestamp).

## 4. Directional Bias & Priority (The LOOK Algorithm)

- [x] **Scenario 4.1: Pick-up on the Way (Sweep)**
  - **Given**: Moving `:up` from 0 to 5.
  - **When**: Receive `{:hall, 3}`.
  - **Then**: The elevator must stop at 3 because it is in the current heading.

- [x] **Scenario 4.2: Reverse or Retire**
  - **Given**: Moving `:up` from 0 to 3, with no more requests above.
  - **When**: All requests at 3 are satisfied.
  - **Then**:
    - If requests exist below -> Change `heading` to `:down`.
    - If NO requests exist anywhere -> Change `heading` to `:idle`.

- [x] **Scenario 4.4: Honor Car Request (Priority)**
  - **Given**: Moving `:up`, a `{:car, floor}` request exists on the path.
  - **When**: Elevator arrives at that floor.
  - **Then**: **STOP** at that floor — car requests (passengers already inside) are always honored.

- [x] **Scenario 4.5: Context-Aware Wake Up**
  - **Given**: Elevator is at F5, state is `:idle`.
  - **When**: Request for F1 is received.
  - **Then**: `heading` becomes `:down` (correctly identifying the request is below).

- [x] **Scenario 4.6: Same-Floor Interaction**
  - **Given**: Elevator at F3, state is `:idle`.
  - **When**: Receive `{:car, 3}` (or hall).
  - **Then**: `motor_status` becomes `:stopping` to immediately open doors.

- [x] **Scenario 4.8: Boundary Reversals**
  - **Given**: Elevator at F5 (Top) heading UP.
  - **When**: Queued requests above are empty.
  - **Then**: `heading` MUST transition to `:idle` or `:down` (never higher).

- [x] **Scenario 4.9: Request Fulfillment (Internal Core Sync)**
  - **Given**: Elevator at Floor 1, having arrived from Floor 3, with `requests` containing `{:car, 3}` and `{:car, 0}`.
  - **When**: A new request for Floor 0 is received while stopped.
  - **Then**:
    - The `requests` list MUST be cleared of Floor 3 (fulfillment).
    - The `heading` MUST become `:down` to reach Floor 0.

---

## 5. Homing & Crash Recovery

- [x] **Scenario 5.1: Cold Start (No Persistence)**
  - **Given**: `Elevator.Vault` is empty.
  - **When**: System starts.
  - **Then**:
    - `status` is `:rehoming`.
    - `head` is `:down`, `speed` is `:slow`.
    - `current_floor` is `:unknown`.

- [x] **Scenario 5.2: Mid-Floor Recovery (Zero-Move)**
  - **Given**: `Elevator.Vault` stores `Floor 3` AND `Elevator.Sensor` is currently at `Floor 3`.
  - **When**: System reboots (e.g., after a crash).
  - **Then**:
    - `status` transitions `:rehoming` -> `:normal` immediately.
    - No motor movement is triggered.

- [x] **Scenario 5.3: Recovery between floors (Move-to-Physical)**
  - **Given**: `Elevator.Vault` says `Floor 3` but `Elevator.Sensor` is `:unknown` (or mismatches).
  - **When**: System reboots.
  - **Then**:
    - `status` is `:rehoming`.
    - `head` is `:down`, `speed` is `:slow`.
    - Move until physical sensor confirms arrival.

- [x] **Scenario 5.4: Homing Completion (Anchoring)**
  - **Given**: `status` is `:rehoming`.
  - **When**: Core receives its very first `{:floor_arrival, floor}` event.
  - **Then**:
    - `status` transitions to `:normal` (Calibration complete).
    - `heading` MUST immediately transition to `:idle` (Anchoring).
    - `motor_status` becomes `:stopping` (Drop the anchor).
    - `Vault` is updated with `Floor X`.
    - Accept new requests normally.

- [x] **Scenario 5.5: Request Blocking during Rehoming**
  - **Given**: Elevator is in `status: :rehoming`.
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
  - **Given**: Elevator is at a floor, `door_status` is `:open`.
  - **When**: 5 seconds (5000ms) pass without activity.
  - **Then**: 
    - Controller sends `{:timeout, :door_timeout}`.
    - Brain returns `{:close_door}`.
    - Door transition begins (`:closing`).
  - **Sub-case 7.1a (Idle Heading)**: The door MUST close even when `heading` is `:idle` (e.g., after rehoming with no pending requests). The timeout closes the door unconditionally as long as `status` is `:normal` and `door_sensor` is `:clear`.

- [x] **Scenario 7.2: Manual Close Button Override**
  - **Given**: Elevator is at a floor, `door_status` is `:open`, pending requests exist.
  - **When**: Pressing the `>|<` (door close) button.
  - **Then**: 
    - Brain immediately returns `{:close_door}` and `{:cancel_timer, :door_timeout}`.
    - Door starts closing without waiting for the 5s timer.

- [x] **Scenario 7.3: Activity Extension (Open Button)**
  - **Given**: `door_status` is `:open`.
  - **When**: Pressing the `<|>` (door open) button at T=1000.
  - **Then**: 
    - `last_activity_at` is updated to T=1000.
    - A new `{:set_timer, :door_timeout, 5000}` is requested.
    - Timer effectively restarts.

- [x] **Scenario 7.4: Service Delay (Auto-Close Integration)**
  - **Given**: At F1, doors open, new request for F5 received.
  - **When**: Request is added.
  - **Then**: 
    - Heading becomes `:up`.
    - Door stays open for 5s (Scenario 7.1) before starting the movement sequence.
