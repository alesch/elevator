# Elevator Core: Logic Rules

This document captures the "Executive Summary" of our current Elevator implementation. It describes the high-level logic and safety constraints enforced by the **Functional Core**.

## 0. Architecture: Effects as Data

* **Rule 0.1: Pure Logic Core**
  * The `Elevator.Core` is a functional core. It MUST NEVER perform side effects (timer scheduling, hardware calls, or I/O).
  * All state transitions return a `{new_state, actions}` tuple, where `actions` is a list of declarative tokens representing intended side effects.
* **Rule 0.2: Imperative Shell**
  * The `Elevator.Controller` is the imperative shell. Its ONLY responsibility is to execute the `actions` returned by the Core and route incoming hardware events back into the Core as events.

* **Rule 0.3: Explicit Phase State Machine**
  * The Core state includes a `phase` field that identifies the elevator's current operational phase unambiguously. Phase is the primary guard for all event handlers — no phase should need to inspect `motor_status` or `door_status` to determine what to do next.

  | Phase | Meaning | Motor | Door |
  | :--- | :--- | :--- | :--- |
  | `:rehoming` | Boot/crash recovery, moving down at `:crawling` speed | `:crawling` | `:closed` |
  | `:moving` | Traveling to a target floor | `:running` | `:closed` |
  | `:arriving` | At target: motor stopping → stopped → door opening | transitioning | `:opening` |
  | `:docked` | At floor, doors open, serving passengers | `:stopped` | `:open` |
  | `:leaving` | Service complete: door closing | `:stopped` | `:closing` → `:closed` |
  | `:idle` | At floor, doors closed, no active work | `:stopped` | `:closed` |

  **Phase Transitions:**
  ```
  :rehoming  --[motor_stopped]--------------------------> :idle
  :idle      --[request + heading set]------------------> :moving
  :moving    --[floor_arrival at target]----------------> :arriving
  :arriving  --[door_opened]----------------------------> :docked
  :docked    --[timeout or close_button]----------------> :leaving
  :leaving   --[door_closed + requests remain]----------> :moving
  :leaving   --[door_closed + no requests]--------------> :idle
  :leaving   --[obstruction during close]--------------->  :docked
  ```

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
  * If the state remains `:idle` for more than 5 minutes (300 seconds), an automatic `{:car, 0}` request is added to the queue.

* **Rule 1.5: Context-Aware Wake Up**
  * When an `:idle` elevator receives a request, it must choose its initial heading based on the relative position of the work:
    * If any request exists **above** the current floor -> Set heading to `:up`.
    * If any request exists **below** the current floor -> Set heading to `:down`.

## 2. Safety & Door Rules

* **Rule 2.1: The Golden Rule (Structural Safety)**
  * The motor **CANNOT** be in the `:running` status unless the `door_status` is confirmed to be `:closed`.

* **Rule 2.2: Asynchronous Arrival Protocol (`:arriving` phase)**
  * When reaching a target floor (phase transitions `:moving` → `:arriving`):
    1. Set `motor_status: :stopping`.
    2. Wait for `:motor_stopped` confirmation.
    3. Transition to `motor_status: :stopped` and `door_status: :opening`.
    4. Only once the door confirms `:door_opened`, transition to `door_status: :open` and phase to `:docked`.
    5. **Wait Phase**: Upon entering `:docked`, the elevator waits for a 5-second inactivity window (Scenario 7.1) before transitioning to `:leaving`.

* **Rule 2.4: Automatic Door Closing (Timer)**
  * Upon entering `:docked`, a `{:set_timer, :door_timeout, 5000}` action is requested.
  * When the timer expires (or a `:door_timeout` event is received), the phase transitions `:docked` → `:leaving`.

* **Rule 2.5: Manual Door Override**
  * A `:door_close` button press triggers an immediate `door_status: :closing` transition, bypassing any remaining time on the auto-close timer.
  * A `:door_open` button press while doors are already open resets the "last activity" timestamp, effectively restarting the 5-second timer.

* **Rule 2.3: Door Obstruction**
  * If the door is `:closing` (phase `:leaving`) and a `:door_sensor_blocked` message is received, phase immediately reverts to `:docked` (door back to `:open`).

## 3. Request Tracking

* **Rule 3.1: Tagged Requests**
  * **`{:hall, floor}`**: External call from a floor panel.
  * **`{:car, floor}`**: Internal selection from the box panel. High priority (Passenger is already inside).

---

## 5. State Persistence & Re-homing

* **Rule 5.1: State Persistence (Continuous Backup)**
  * Every time a `{:floor_arrival, floor}` event is confirmed by the Sensor, the Controller must asynchronously update the `Elevator.Vault` with the current floor.
  * This ensures that in the event of a process crash and `:one_for_all` restart, the system knows where the elevator was last seen.

* **Rule 5.2: The Homing Procedure (Power-On Safety)**
  * Upon startup (boot or crash recovery), the elevator enters `phase: :rehoming`.
  * **Homing Strategy**:
    * **Step 1: Detection**: Compare `Vault.get_floor()` with `Sensor.get_floor()`.
    * **Step 2: Decision**:
      * If they match and indicate a valid floor -> Transition directly to `phase: :idle` (Zero-move recovery).
      * If they mismatch or indicate `:unknown` -> Move `:down` at `:crawling` speed until a floor sensor is triggered.
  * **Request Blocking**: While in `phase: :rehoming`, the Core MUST ignore all `{:hall, floor}` and `{:car, floor}` requests.
  * **Homing Completion**: Once position is verified (either via Step 1 or via a physical arrival + `motor_stopped`), the system transitions to `phase: :idle` and updates the `Vault`. No door cycle is triggered.

---

## Technical State (Phase Transition Mapping)

| Phase | Event | New Phase | Motor | Door |
| :--- | :--- | :--- | :--- | :--- |
| `:idle` | `{:hall, 5}` or `{:car, 5}` | `:moving` | `:running` | `:closed` |
| `:moving` | `Arrival(F5)` (target) | `:arriving` | `:stopping` | `:closed` |
| `:arriving` | `:motor_stopped` | `:arriving` | `:stopped` | `:opening` |
| `:arriving` | `:door_opened` | `:docked` | `:stopped` | `:open` |
| `:docked` | `:door_timeout` or `:door_close` | `:leaving` | `:stopped` | `:closing` |
| `:leaving` | `:door_closed` (requests remain) | `:moving` | `:running` | `:closed` |
| `:leaving` | `:door_closed` (no requests) | `:idle` | `:stopped` | `:closed` |
| `:leaving` | `:door_obstructed` | `:docked` | `:stopped` | `:open` |
| **`:idle`** | **`Init / Reboot` (match)** | **`:idle`** | **`:stopped`** | **`:closed`** |
| **`:rehoming`** | **`Init / Reboot` (mismatch)** | **`:rehoming`** | **`:crawling`** | **`:closed`** |
| `:rehoming` | `Arrival(ANY)` | `:rehoming` | `:stopping` | `:closed` |
| `:rehoming` | `:motor_stopped` | `:idle` | `:stopped` | **`:closed`** (no door cycle) |
