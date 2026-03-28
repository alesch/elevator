# Elevator Controller: Logic Rules

## Key Rules (Executive Summary)

* **The Elevator Algorithm**: The elevator satisfies all requests in its current direction before reversing.
* **Safety Interlock**: The motor cannot and will not move unless the door confirms it is fully closed.
* **Obstruction Recovery**: If the door sensor is blocked during closing, it immediately halts and re-opens.
* **Internal Priority**: Passenger requests from inside the box are prioritized for the current travel direction.
* **Return to Base**: The elevator returns to Floor 1 if it has been idle for 5 minutes.

## 1. Movement & Direction Rules

* **Rule 1.1: Idle State**
    If the elevator is `:idle` and a request is received (from a floor or the box), change state to `{:moving, direction}` where the direction is calculated based on the current floor and the target floor.
* **Rule 1.2: Stopping at Floors**
    If the elevator is `:moving_up` or `:moving_down` and there is a request for the current floor (either a `:call_up`/`:call_down` from the floor or a `:go_to` from the box), the elevator must stop.
* **Rule 1.3: Directional Bias (The "Elevator Algorithm")**
  * If `:moving_up`, it continues as long as there are requests above it.
  * If `:moving_down`, it continues as long as there are requests below it.
  * It only changes direction once all requests in the current direction are satisfied.
* **Rule 1.4: Return to Base**
    If the state is `:idle_closed` for more than 5 minutes (300 seconds), add a `:go_to, floor: 1` request to the queue.

## 2. Safety & Door Rules

* **Rule 2.1: Door Precedence**
    The Motor/Box cannot move (state cannot be `:moving`) unless the Door state is `:closed`.
* **Rule 2.2: Arrival Sequence**
    When the elevator arrives at a floor:
    1. Stop the motor.
    2. Command the Door to `:open`.
    3. Wait for the `:door_open` status.
    4. Start a "Door Hold" timer (e.g., 5 seconds).
* **Rule 2.3: Door Obstruction**
    If the Door is `:closing` and a `:door_sensor_blocked` message is received:
    1. Immediately stop closing.
    2. Command the Door to `:open`.
    3. Reset the "Door Hold" timer.

## 3. Floor Panel (External) vs. Box Panel (Internal)

* **Rule 3.1: External Calls**
    A `:call_up` or `:call_down` from a Floor Panel is added to the "Global Request Queue".
* **Rule 3.2: Internal Selection**
    An internal `:go_to` request is added to the "Global Request Queue" with the highest priority for stopping (if it's in the current direction).

## 4. Edge Cases & Failures (Early Simulation)

* **Rule 4.1: Emergency Stop**
    If an `:emergency_stop` is received from the Box Panel:
    1. Immediately stop the Motor.
    2. Transition to `:emergency_mode`.
    3. Ignore all other requests until `:reset`.
* **Rule 4.2: Illegal Requests**
    A request for Floor 6 in a 5-floor system must be ignored or return an error.

---

## State Transition Table (Draft)

| Current State | Event | New State | Commands Sent |
| :--- | :--- | :--- | :--- |
| `:idle_closed` | `{:call, floor: 5}` | `:moving_up` | Motor: `move_up` |
| `:moving_up` | `:floor_arrival(3)` | `:door_opening` | Motor: `stop`, Door: `open` |
| `:door_opening` | `:door_open_done` | `:door_open_idle` | Start Timer (5s) |
| `:door_closing` | `:sensor_blocked` | `:door_opening` | Door: `stop`, Door: `open` |
