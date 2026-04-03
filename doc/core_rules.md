# Elevator Core: Logic Rules

This document captures the "Executive Summary" of our current Elevator implementation. It describes the high-level logic and safety constraints enforced by the **Autonomous Functional Core**.

## 0. Architecture: Effects as Data

* **Rule 0.1: Pure Logic Core**
  * The `Elevator.Core` is a functional core. It MUST NEVER perform side effects (timer scheduling, hardware calls, or I/O).
  * All state transitions return a `{new_state, actions}` tuple, where `actions` is a list of declarative tokens representing intended side effects.
* **Rule 0.2: Imperative Shell**
  * The `Elevator.Controller` is the imperative shell. Its ONLY responsibility is to execute the `actions` returned by the Core and route incoming hardware events back into the Core as events.

## 1. Movement & Direction Rules (The LOOK Algorithm)

* **Rule 1.1: Intent vs. Action**
  * **`heading`**: Represents **INTENTION** (`:up`, `:down`, `:idle`). This determines where the elevator *wants* to go.
  * **`motor_status`**: Represents **PHYSICAL MOVEMENT** (`:running`, `:stopping`, `:stopped`).

* **Rule 1.2: Directional Bias (The Sweep)**
  * Once moving in a direction, the elevator continues to satisfy all requests in that direction until none remain.
  * It only reverses heading once all requests in the current direction are satisfied and there is work in the opposite direction.

* **Rule 1.3: Retiring (Idle State)**
  * If no requests remain in any direction, the `heading` becomes `:idle`.

* **Rule 1.4: Return to Base**
  * If the state remains `:idle` for more than 5 minutes (300 seconds), an automatic `{:car, 1}` request is added to the queue.

* **Rule 1.5: Full Load Bypass**
  * If `remaining_capacity < 100kg` (current weight > 900kg), the elevator will bypass all Hall Requests (`{:hall, floor}`) on its path.
  * It will **ALWAYS** stop for Car Requests (`{:car, floor}`), as passengers need to exit.
  * **Note**: At exactly 900kg (100kg capacity), the elevator still stops for hall calls to pick up its final load.

* **Rule 1.6: Context-Aware Wake Up**
  * When an `:idle` elevator receives a request, it must choose its initial heading based on the relative position of the work:
    * If any request exists **above** the current floor -> Set heading to `:up`.
    * If any request exists **below** the current floor -> Set heading to `:down`.

## 2. Safety & Door Rules

* **Rule 2.1: The Golden Rule (Structural Safety)**
  * The motor **CANNOT** be in the `:running` status unless the `door_status` is confirmed to be `:closed`.
  * This is structurally enforced by the `apply_constraints/1` pipeline in `Elevator.Core`.

* **Rule 2.2: Asynchronous Arrival Protocol**
  * When reaching a target floor:
    1. Set `motor_status: :stopping`. (Braking Phase)
    2. Wait for `:motor_stopped` confirmation.
    3. Transition to `motor_status: :stopped` and `door_status: :opening`.
    4. Only once the door confirms `:door_open_done`, transition to `door_status: :open`.
    5. **Wait Phase**: Upon entering `:open`, the elevator waits for a 5-second inactivity window (Scenario 7.1) before attempting to close.

* **Rule 2.4: Automatic Door Closing (Timer)**
  * If the elevator has pending requests and the doors are `:open`, it will request a `{:set_timer, :door_timeout, 5000}` action.
  * When the timer expires (or a `:door_timeout` event is received), the Brain transitions to `door_status: :closing`.

* **Rule 2.5: Manual Door Override**
  * A `:door_close` button press triggers an immediate `door_status: :closing` transition, bypassing any remaining time on the auto-close timer.
  * A `:door_open` button press while doors are already open resets the "last activity" timestamp, effectively restarting the 5-second timer.

* **Rule 2.3: Door Obstruction**
  * If the door is `:closing` and a `:door_sensor_blocked` message is received, it must immediately return to `:opening`.

## 3. Request Tracking

* **Rule 3.1: Tagged Requests**
  * **`{:hall, floor}`**: External call from a floor panel. Subject to "Full Load Bypass".
  * **`{:car, floor}`**: Internal selection from the box panel. High priority (Passenger is already inside).

## 4. Emergency & Edge Cases

* **Rule 4.1: Overload State**
  * If `weight > 1000kg`, set status to `:overload`.
  * All door closing attempts are blocked while in `:overload`.

---

---

## 5. State Persistence & Re-homing

* **Rule 5.1: State Persistence (Continuous Backup)**
  * Every time a `{:floor_arrival, floor}` event is confirmed by the Sensor, the Controller must asynchronously update the `Elevator.Vault` with the current floor.
  * This ensures that in the event of a process crash and `:one_for_all` restart, the system knows where the elevator was last seen.

* **Rule 5.2: The Homing Procedure (Power-On Safety)**
  * Upon startup (boot or crash recovery), the elevator enters `status: :rehoming`.
  * **Homing Strategy (Smart Homing)**:
    * **Step 1: Detection**: Compare `Vault.get_floor()` with `Sensor.get_floor()`.
    * **Step 2: Decision**:
      * If they match and indicate a valid floor -> Transition directly to `status: :normal` (Zero-move recovery).
      * If they mismatch or indicate `:unknown` -> Move `:down` at **SLOW** speed until a floor sensor is triggered.
  * **Request Blocking**: While in `:rehoming` status, the Core MUST ignore all `{:hall, floor}` and `{:car, floor}` requests.
  * **Homing Completion**: Once position is verified (either via Step 1 or via a physical arrival), the system transitions to `:normal` and updates the `Vault`.

---

## Technical State (State Machine Mapping)

| Current Motor | Event | New Motor | Door | Status |
| :--- | :--- | :--- | :--- | :--- |
| `:stopped` | `{:hall, 5}` | `:running` | `:closed` | `:normal` |
| `:running` | `Arrival(F5)` | `:stopping` | `:closed` | `:normal` |
| `:stopping` | `:motor_stopped` | `:stopped` | `:opening` | `:normal` |
| `:stopped` | `:door_open_done` | `:stopped` | `:open` | `:normal` |
| **`N/A`** | **`Init / Reboot`** | **`:running`** | **`:closed`** | **`:rehoming`** |
| `:running` | `Arrival(ANY)` | `:stopping` | `:closed` | `:rehoming` |
