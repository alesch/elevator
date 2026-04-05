# Technical Specification: Hardware Sensor

The Elevator Sensor signals when the elevator has arrived at each floor.
This is achieved by counting **Motor Pulses** into logical **Floor Arrivals**, maintaining the system's awareness of its vertical position.

## State Management

Its internal state is formalized in a struct:

| Field | Type | Description |
| :--- | :--- | :--- |
| **`current_floor`** | `integer()` | The logical floor number (0-indexed). |
| **`controller`** | `pid() \| atom()` | The "Brain" (Controller) to notify of arrivals. |

## Public API

- `get_floor(pid \\ __MODULE__)`: Returns the current `integer()` floor or `:unknown` if the sensor is in an inconsistent state.

## Initialization & Recovery

To ensure the elevator doesn't "lose its place" during a power cycle or system restart, the Sensor implements a robust bootstrap sequence:

1. **Vault Recovery**: Upon startup, it queries the **`Elevator.Vault`** (the persistent storage layer) for the last known physical floor.
2. **Fallback**: If the Vault is unavailable or empty, it defaults to the `current_floor` provided in the start options (typically floor `0`).
3. **Observability**: Emits a `[:elevator, :hardware, :sensor, :init]` telemetry event detailing the starting floor and whether it was successfully recovered.

## Physics & Pulse Handling

The Sensor is technically passive; it does not "seek" floors. Instead, it reacts to signals from the **Motor**:

1. **Pulse Receipt**: Receives a `{:motor_pulse, direction}` message from the Motor.
2. **Calculation**: Increments (`:up`) or decrements (`:down`) the `current_floor`.
3. **Arrival Logic**: Immediately notifies the **Controller** with a `{:floor_arrival, next_floor}` message.
4. **Telemetery**: Executes `[:elevator, :hardware, :sensor, :arrival]` for tracking transit progress.

## Assumptions & Safety

1. **Pulse Reliance**: The sensor relies entirely on pulses from the motor to update its position. It does not have independent knowledge of the elevator's actual location.
2. **Notification Failure**: If the controller cannot be located when a floor arrival is detected, a `[:elevator, :hardware, :sensor, :notification_failure]` event is logged.
3. **Unknown Messages**: Messages that the sensor doesn't recognize are logged via telemetry and do not affect the floor count.
