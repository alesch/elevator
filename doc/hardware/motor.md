# Technical Specification: Hardware Motor

The Elevator Motor is a "dumb" actuator responsible for vertical motion. It does not track its own position; instead, it relies on pulse timers and external sensor feedback to coordinate movement.

## State Machine

The motor operates as a 4-state machine:

| Status          | Description                                           | Transitions To          |
| :---            | :---                                                  | :---                    |
| **`:stopped`**  | Initial/Stationary state. No timers active.           | `:running`, `:crawling` |
| **`:running`**  | Normal speed travel (1.5s/floor). Pulse timer active. | `:stopping`             |
| **`:crawling`** | Slow speed travel (4.5s/floor). Pulse timer active.   | `:stopping`             |
| **`:stopping`** | Active braking phase (500ms). Brake timer active.     | **`:stopped`**          |

## Public API

The motor process is managed via a GenServer and supports the following commands:

- `move(pid, direction)`: Transitions from `:stopped` to **`:running`**.
- `crawl(pid, direction)`: Transitions from `:stopped` to **`:crawling`**.
- `stop(pid)`: Transitions from `:running` or `:crawling` to **`:stopping`**.

## Timers & Physics

- **Pulse Timer (`@transit_ms`)**:
  - **`:running`**: 1,500ms (1.5 seconds)
  - **`:crawling`**: 4,500ms (4.5 seconds)
  - Each pulse notifies the sensor system: `{:motor_pulse, direction}`.
- **Brake Timer (`@brake_ms`)**:
  - **500ms** for both `:running` and `:crawling`.
  - Upon completion, notifies the controller: `:motor_stopped`.

## Assumptions & Safety

1. **Self-Termination**: The motor will pull cables indefinitely until an explicit `stop/1` command is received or the process is terminated.
2. **Golden Rule**: If a move/crawl command is received while the motor is already in motion, any existing pulse/brake timers are cancelled, and the new motion begins immediately.
3. **Directional Blindness**: The motor does not know which floor it is on; it only knows its current `direction` (`:up` or `:down`).

## How the pulse interacts with the Sensor

The **Pulse Timer** acts as our digital "physics engine," simulating the travel time between levels in our digital twin.

1. **Pulse Generation**: Every 1.5 seconds (normal speed) or 4.5 seconds (slow speed), the Motor generates a `{:motor_pulse, direction}` signal.
2. **Encoder Logic**: This signal is sent to the **Sensor** process, which acts as a hardware encoder. The Sensor increments or decrements its current floor count based on these pulses.
3. **Decoupled Control**: This architecture mirrors real industrial systems where the motor only manages **effort** (spinning) while the sensor manages **position**. The Brain (Core) remains decoupled from the timing of physical movement, simply telling the motor to move and waiting for the Sensor to report arrivals.
