# Technical Specification: Hardware Sensor

The Elevator Sensor is a passive floor memory. It tracks the elevator's vertical position by listening for `{:floor_arrival, floor}` events from `Elevator.World`. It does not calculate, predict, or notify — it only remembers.

## State Management

Its internal state is formalized in a struct:

| Field | Type | Description |
| :--- | :--- | :--- |
| **`current_floor`** | `integer()` | The last confirmed floor, as reported by World. |

## Public API

- `get_floor(pid \\ __MODULE__)`: Returns the current `integer()` floor.

## Initialization & Recovery

To ensure the elevator doesn't "lose its place" during a power cycle or system restart, the Sensor implements a bootstrap sequence:

1. **Vault Recovery**: Upon startup, it queries the **`Elevator.Vault`** (the persistent storage layer) for the last known physical floor.
2. **Fallback**: If the Vault is unavailable or empty, it defaults to the `current_floor` provided in the start options (typically floor `0`).
3. **Observability**: Emits a `[:elevator, :hardware, :sensor, :init]` telemetry event detailing the starting floor and whether it was successfully recovered.

## Floor Tracking

Sensor receives `{:floor_arrival, floor}` directly from World via registry and updates its internal floor. It does not re-notify the Controller — World notifies the Controller directly on the same event.

```
World → {:floor_arrival, 3} → Sensor   (updates current_floor to 3)
World → {:floor_arrival, 3} → Controller (via registry notify)
```

The two deliveries are independent. Sensor is purely a readable floor counter.

## Assumptions & Safety

1. **World is the source of truth**: Sensor does not interpret motor pulses or calculate floor positions. It trusts whatever floor World reports.
2. **No controller coupling**: Sensor does not hold a reference to the Controller and never sends messages to it.
3. **Unknown Messages**: Messages that the sensor doesn't recognize are logged via telemetry and do not affect the floor count.
