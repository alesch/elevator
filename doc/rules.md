# Elevator Core: Logic Rules

These are the rules governing this elevator implementation.  
From these rules we derive the test scenarios.

## 1. Architecture: FICS (Functional, Immutable, Core, Side-effects)

* **Rule: Pure Logic Core [R-CORE-PURE]**
  * The `Elevator.Core` is a functional core. It MUST NEVER perform side effects (timer scheduling, hardware calls, or I/O).
  * All state transitions return a `{new_state, actions}` tuple, where `actions` is a list of declarative tokens representing intended side effects, executed by the Controller.

* **Rule: Imperative Shell [R-CORE-SHELL]**
  * The `Elevator.Controller` is the imperative shell. Its ONLY responsibility is to execute the `actions` returned by the Core and route incoming hardware events back into the Core as events.

* **Rule: Explicit Phase State Machine [R-CORE-STATE]**
  * The Core state includes a `phase` field that identifies the elevator's current operational phase unambiguously. Phase is the primary guard for all event handlers.

## 2. Safety & Door Rules

* **Rule: The Golden Rule (Structural Safety) [R-SAFE-GOLDEN]**
  * The motor **CANNOT** be running unless the doors are confirmed closed.

* **Rule: Boot/Rehoming Blocking [R-BOOT-GUARD] [R-HOME-BLOCK]**
  * While the elevator is starting up (booting) or rehoming it ignores all external floor requests and manual door commands.

* **Rule: Asynchronous Arrival Protocol [R-SAFE-ARRIVAL]**
  * When reaching a target floor:
    1. Command the motor to stop.
    2. Wait for the motor to confirm it has stopped.
    3. Command the door to open.
    4. Wait for the door to confirm it has opened.

* **Rule: Automatic Door Closing (Timer) [R-SAFE-TIMEOUT]**
  * After servicing a floor, if no requests are pending, the doors will close after 5 seconds.

* **Rule: Manual Door Override [R-SAFE-MANUAL]**
  * A `:door_close` button press bypasses any remaining time on the auto-close timer.
  * A `:door_open` button press while doors are already open resets the 5-second timer.

* **Rule: Door Obstruction [R-SAFE-OBSTRUCT]**
  * If the door is closing and a the sensor is blocked, the doors should immediately open.

## 3. Movement & Direction Rules (The LOOK Algorithm)

* **Rule: LOOK algorithm [R-MOVE-LOOK]**  
  The `Elevator.Sweep` module implements the **LOOK algorithm** which governs movement and stop priority:
  1. **Directional Bias**: The elevator travels in its current `heading` as long as there are requests further along that path. Once moving, it satisfies all **Car Requests** in the current direction.
  2. **Stopping on the Way (Directional Asymmetry)**:
      * This results in an ascending sweep optimized for internal passengers and a descending sweep for external arrivals.
      * **UP Journeys**: Priority is given to **Car Requests**. **Hall Requests** are picked up on the way ONLY if they are at the "peak" (the furthest request).
      * **DOWN Journeys**: Pick up ALL requests (Car and Hall) on the way to maximize efficiency for returning cars.
  3. **The "Look Ahead"**: Before reversing, the system verifies if there are any requests ahead of the current position in the current heading.
  4. **Reverse on Empty (Idle State)**: If no work remains in the current heading, the elevator reverses to satisfy requests in the opposite direction.

* **Rule: Return to Base [R-MOVE-BASE]**
  * If the elevator remains idle for more than 5 minutes (300 seconds), the elevator moves to the base floor.

## 4. State Persistence & Homing

* **Rule: State Persistence (Vault Backup) [R-HOME-VAULT]**
  * The elevator keeps track of the last floor it visited, to ensure that in the event of a process crash or restart, the system knows where the elevator was last seen.

* **Rule: Homing Procedure (Power-On Safety) [R-HOME-STRATEGY]**
  * Upon startup (boot or crash recovery), the elevator enters the `rehoming` phase.
  * **Homing Strategy**:
    * **Step 1: Detection**: Compare the stored floor information with the current sensor's reading.
    * **Step 2: Decision**:
      * If they match and indicate a valid floor -> Transition directly to idle (Zero-move recovery).
      * If they mismatch -> Crawl down until a floor sensor is triggered.
  * **Homing Completion**: Once position is verified, the system transitions to idle. No door cycle is triggered.

## 6. Hardware Layer Protocols

* **Rule: Motor Movement Protocol [R-HW-MOTOR]**
  * The physical motor driver must maintain internal state for `direction` and `speed`.
  * It must notify the Sensor of movement progress via `:pulse` events.

* **Rule: Door Operation Protocol [R-HW-DOOR]**
  * The door driver must explicitly track `:opening`, `:open`, `:closing` and `:closed` transit states.

* **Rule: Sensor Floor Tracking [R-HW-SENSOR]**
  * The sensor driver must increment/decrement the current floor based on motor pulses.
  * It must notify the Controller with a `{:floor_arrival, floor}` event only once a position is physically locked.
