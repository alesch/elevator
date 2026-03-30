# Elevator System: Complete Scenarios Specification

This document defines the testable reality of our simulation. We use these scenarios to drive our TDD (Red-Green-Refactor) process.

## 1. The "Happy Path" (Standard Movement)

- [x] **Scenario 1.1: Request from IDLE**
  - **Given**: Elevator is at F0, state is `:idle`, doors are `:closed`.
  - **When**: Request for F3 is received from the Hall.
  - **Then**: `heading` becomes `:up`, `requests` includes `{:hall, 3}`.

- [x] **Scenario 1.2: Arrival at Floor (Braking)**
  - **Given**: Elevator is at F3, `heading` is `:up`, `requests` includes `{:hall, 3}`.
  - **When**: Sensor confirms arrival at F3.
  - **Then**: `motor_status` becomes `:stopping`.

- [x] **Scenario 1.3: Braking Complete (Door Opening)**
  - **Given**: Elevator is at F3, `motor_status` is `:stopping`.
  - **When**: Receive `:motor_stopped` confirmation.
  - **Then**: `motor_status` becomes `:stopped`, `door_status` becomes `:opening`.

- [x] **Scenario 1.4: Door Transition Cycle**
  - **When**: Doors are `:opening` -> Receive `:door_open_done`.
  - **Then**: `door_status` becomes `:open`, start auto-close timer.

## 2. Safety Interlocks & Sensors

- [x] **Scenario 2.1: Door Obstruction**
  - **Given**: Doors are `:closing`.
  - **When**: Receive `:door_sensor_blocked`.
  - **Then**: Immediately transition `door_status` back to `:opening`.

- [x] **Scenario 2.2: Weight Sensor (Overload)**
  - **Given**: Doors are `:open`.
  - **When**: `weight` exceeds `weight_limit` (e.g., 1000kg).
  - **Then**: `status` becomes `:overload`, all `command_close_door` events are ignored.

- [x] **Scenario 2.3: Return to Normal from Overload**
  - **Given**: Status is `:overload`.
  - **When**: `weight` falls below `weight_limit`.
  - **Then**: `status` becomes `:normal`.

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

- [x] **Scenario 4.3: Full Load Bypass (Hall)**
  - **Given**: Moving `:up` from 0 to 5, `weight` is 900kg (Near limit).
  - **When**: Receive `{:hall, 3}`.
  - **Then**: **BYPASS** Floor 3 (do not stop) because there is no room.

- [x] **Scenario 4.4: Honor Car Request (Priority)**
  - **Given**: Moving `:up` from 0 to 5, `weight` is 900kg.
  - **When**: Receive `{:car, 3}`.
  - **Then**: **STOP** at Floor 3 anyway, because an internal passenger needs to exit.

- [x] **Scenario 4.5: Context-Aware Wake Up**
  - **Given**: Elevator is at F5, state is `:idle`.
  - **When**: Request for F1 is received.
  - **Then**: `heading` becomes `:down` (correctly identifying the request is below).

- [x] **Scenario 4.6: Same-Floor Interaction**
  - **Given**: Elevator at F3, state is `:idle`.
  - **When**: Receive `{:car, 3}` (or hall).
  - **Then**: `motor_status` becomes `:stopping` to immediately open doors.

- [x] **Scenario 4.7: Weight Thresholds**
  - **Given**: Elevators stop normally up to 900kg.
  - **When**: Weight is 901kg+ (or remaining capacity < 100kg).
  - **Then**: Bypass hall calls, but ALWAYS honor car calls.

- [x] **Scenario 4.8: Boundary Reversals**
  - **Given**: Elevator at F5 (Top) heading UP.
  - **When**: Queued requests above are empty.
  - **Then**: `heading` MUST transition to `:idle` or `:down` (never higher).

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

- [x] **Scenario 5.4: Homing Completion**
  - **Given**: `status` is `:rehoming`.
  - **When**: Controller receives `{:floor_arrival, 2}`.
  - **Then**:
    - `status` becomes `:normal`.
    - `motor_status` becomes `:stopping`.
    - `Vault` is updated with `Floor 2`.
    - Accept new requests.

---

## Technical State (The State Machine)

- **Door States**: `:open`, `:closing`, `:closed`, `:opening`, `:blocked`.
- **Motor Status**: `:running`, `:stopping`, `:stopped`.
- **Elevator Status**: `:normal`, `:overload`, `:emergency`, `:rehoming`.
- **Request Format**: `{:hall, floor}` (External), `{:car, floor}` (Internal).
