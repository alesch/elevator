# Elevator Core: Logic Rules

This document captures the "Executive Summary" of our current Elevator implementation. It describes the high-level logic and safety constraints enforced by the **Functional Core**.

## 1. Architecture: Effects as Data

* **Rule: Pure Logic Core [R-CORE-PURE]**
  * The `Elevator.Core` is a functional core. It MUST NEVER perform side effects (timer scheduling, hardware calls, or I/O).
  * All state transitions return a `{new_state, actions}` tuple, where `actions` is a list of declarative tokens representing intended side effects.

* **Rule: Imperative Shell [R-CORE-SHELL]**
  * The `Elevator.Controller` is the imperative shell. Its ONLY responsibility is to execute the `actions` returned by the Core and route incoming hardware events back into the Core as events.

* **Rule: Explicit Phase State Machine [R-CORE-STATE]**
  * The Core state includes a `phase` field that identifies the elevator's current operational phase unambiguously. Phase is the primary guard for all event handlers — no phase should need to inspect `motor_status` or `door_status` to determine what to do next.

  | Phase | Meaning | Motor | Door |
  | :--- | :--- | :--- | :--- |
  | `:rehoming` | Boot/crash recovery, moving down at `:crawling` speed | `:crawling` | `:closed` |
  | `:moving` | Traveling to a target floor | `:running` | `:closed` |
  | `:arriving` | At target: motor stopping → stopped → door opening | transitioning | `:opening` |
  | `:docked` | At floor, doors open, serving passengers | `:stopped` | `:open` |
  | `:leaving` | Service complete: door closing | `:stopped` | `:closing` → `:closed` |
  | `:idle` | At floor, doors closed, no active work | `:stopped` | `:closed` |

  **Phase Transitions Chart:**

  ```text
  :rehoming  --[motor_stopped]--------------------------> :idle
  :idle      --[request + heading set]------------------> :moving
  :moving    --[floor_arrival at target]----------------> :arriving
  :arriving  --[door_opened]----------------------------> :docked
  :docked    --[timeout or close_button]----------------> :leaving
  :leaving   --[door_closed + requests remain]----------> :moving
  :leaving   --[door_closed + no requests]--------------> :idle
  :leaving   --[obstruction during close]---------------> :docked
  ```

## 2. Movement & Direction Rules (The LOOK Algorithm)

* **Rule: Intent vs. Action [R-MOVE-INTENT]**
  * **`heading`**: Represents **INTENTION** (`:up`, `:down`, `:idle`). This determines where the elevator *wants* to go.
  * **`motor_status`**: Represents **PHYSICAL MOVEMENT** (`:running`, `:stopping`, `:stopped`).

* **Rule: Directional Bias (The Sweep) [R-MOVE-SWEEP]**
  * Once moving in a direction, the elevator satisfies all **Car Requests** in the current direction.
  * **Hall Requests** are deferred to the return journey to minimize interruptions for passengers already inside the car.
  * For multi-stop journeys, this results in an ascending sweep for internal passengers and a descending sweep for external arrivals.

* **Rule: Retiring (Idle State) [R-MOVE-IDLE]**
  * If no requests remain in any direction, the `heading` becomes `:idle`.

* **Rule: Return to Base [R-MOVE-BASE]**
  * If the state remains `:idle` for more than 5 minutes (300 seconds), an automatic `{:hall, 0}` request is added to the queue.

* **Rule: Context-Aware Wake Up [R-MOVE-WAKEUP]**
  * When an `:idle` elevator receives a request, it must choose its initial heading based on the relative position of the work:
    * If any request exists **above** the current floor -> Set heading to `:up`.
    * If any request exists **below** the current floor -> Set heading to `:down`.

## 3. Safety & Door Rules

* **Rule: The Golden Rule (Structural Safety) [R-SAFE-GOLDEN]**
  * The motor **CANNOT** be in the `:running` status unless the `door_status` is confirmed to be `:closed`.

* **Rule: Asynchronous Arrival Protocol [R-SAFE-ARRIVAL]**
  * When reaching a target floor (phase transitions `:moving` → `:arriving`):
    1. Set `motor_status: :stopping`.
    2. Wait for `:motor_stopped` confirmation.
    3. Transition to `motor_status: :stopped` and `door_status: :opening`.
    4. Only once the door confirms `:door_opened`, transition to `door_status: :open` and phase to `:docked`.
    5. **Wait Phase**: Upon entering `:docked`, the elevator waits for a 5-second inactivity window before transitioning to `:leaving`.

* **Rule: Automatic Door Closing (Timer) [R-SAFE-TIMEOUT]**
  * Upon entering `:docked`, a `{:set_timer, :door_timeout, 5000}` action is requested.
  * When the timer expires (or a `:door_timeout` event is received), the phase transitions `:docked` → `:leaving`.

* **Rule: Manual Door Override [R-SAFE-MANUAL]**
  * A `:door_close` button press triggers an immediate `door_status: :closing` transition, bypassing any remaining time on the auto-close timer.
  * A `:door_open` button press while doors are already open resets the "last activity" timestamp, effectively restarting the 5-second timer.

* **Rule: Door Obstruction [R-SAFE-OBSTRUCT]**
  * If the door is `:closing` (phase `:leaving`) and a `:door_sensor_blocked` message is received:
    1. Status transitions to `door_status: :obstructed`.
    2. Sensor transitions to `door_sensor: :blocked`.
    3. Phase transitions back to `phase: :docked`.
    4. An immediate `{:open_door}` action is triggered to begin recovery.

## 4. Request Tracking

* **Rule: Tagged Requests [R-REQ-TAGS]**
  * **`{:hall, floor}`**: External call from a floor panel.
  * **`{:car, floor}`**: Internal selection from the box panel. High priority (Passenger is already inside).

## 5. State Persistence & Homing

* **Rule: State Persistence (Vault Backup) [R-HOME-VAULT]**
  * Every time a `{:floor_arrival, floor}` event is confirmed by the Sensor, the Controller must asynchronously update the `Vault` with the current floor.
  * This ensures that in the event of a process crash or restart, the system knows where the elevator was last seen.

* **Rule: Homing Procedure (Power-On Safety) [R-HOME-STRATEGY]**
  * Upon startup (boot or crash recovery), the elevator enters `phase: :rehoming`.
  * **Homing Strategy**:
    * **Step 1: Detection**: Compare `Vault.get_floor()` with `Sensor.get_floor()`.
    * **Step 2: Decision**:
      * If they match and indicate a valid floor -> Transition directly to `phase: :idle` (Zero-move recovery).
      * If they mismatch or indicate `:unknown` -> Move `:down` at `:crawling` speed until a floor sensor is triggered.
  * **Request Blocking**: While in `phase: :rehoming`, the Core MUST ignore all floor requests.
  * **Homing Completion**: Once position is verified, the system transitions to `phase: :idle` and updates the `Vault`. No door cycle is triggered.

## 6. Hardware Layer Protocols

* **Rule: Motor Movement Protocol [R-HW-MOTOR]**
  * The physical motor driver must maintain internal state for `direction` and `speed`.
  * It must notify the Sensor of movement progress via `:pulse` events.

* **Rule: Door Operation Protocol [R-HW-DOOR]**
  * The door driver must explicitly track `:opening`, `:open`, `:closing` and `:closed` transit states.

* **Rule: Sensor Floor Tracking [R-HW-SENSOR]**
  * The sensor driver must increment/decrement the current floor based on motor pulses.
  * It must notify the Controller with a `{:floor_arrival, floor}` event only once a position is physically locked.

---

## Technical State Transition Matrix

This table maps events to rules and state changes.

| Phase | Event | Rule | New Phase | Motor | Door |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `:idle` | `{:hall, F}` or `{:car, F}` | **[R-MOVE-WAKEUP]** | `:moving` | `:running` | `:closed` |
| `:moving` | `Arrival(Target)` | **[R-SAFE-ARRIVAL]** | `:arriving` | `:stopping` | `:closed` |
| `:arriving` | `:motor_stopped` | **[R-SAFE-ARRIVAL]** | `:arriving` | `:stopped` | `:opening` |
| `:arriving` | `:door_opened` | **[R-CORE-STATE]** | `:docked` | `:stopped` | `:open` |
| `:docked` | `:door_timeout` | **[R-SAFE-TIMEOUT]** | `:leaving` | `:stopped` | `:closing` |
| `:docked` | `:door_close` | **[R-SAFE-MANUAL]** | `:leaving` | `:stopped` | `:closing` |
| `:leaving` | `:door_closed` (work) | **[R-MOVE-SWEEP]** | `:moving` | `:running` | `:closed` |
| `:leaving` | `:door_closed` (idle) | **[R-MOVE-IDLE]** | `:idle` | `:stopped` | `:closed` |
| `:leaving` | `:door_obstructed` | **[R-SAFE-OBSTRUCT]** | `:docked` | `:stopped` | `:obstructed` |
| `:rehoming` | `Init (valid floor)` | **[R-HOME-STRATEGY]** | `:idle` | `:stopped` | `:closed` |
| `:rehoming` | `Init (unknown)` | **[R-HOME-STRATEGY]** | `:rehoming` | `:crawling` | `:closed` |
| `:rehoming` | `Arrival(Any)` | **[R-HOME-STRATEGY]** | `:rehoming` | `:stopping` | `:closed` |
| `:rehoming` | `:motor_stopped` | **[R-HOME-STRATEGY]** | `:idle` | `:stopped` | `:closed` |
