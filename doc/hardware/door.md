# Technical Specification: Hardware Door

The Elevator Door is a self-contained state machine that coordinates with the Controller through standardized pulse events and completion notifications.

## State Machine

The door operates as a 5-state machine:

| Status | Description | Transitions To |
| :--- | :--- | :--- |
| **`:closed`** | Resting state. Door is fully shut. | `:opening` |
| **`:opening`** | Active transition state. Transit timer (1s) active. | `:open`, `:obstructed` |
| **`:open`** | Maximum retraction. Safe for passenger ingress/egress. | `:closing` |
| **`:closing`** | Active transition state. Transit timer (1s) active. | `:closed`, `:obstructed` |
| **`:obstructed`** | Safety interrupt state. Stationary and stable. | `:opening` |

## Public API

The door process is managed via a GenServer and supports the following commands:

- `open(pid)`: Transitions from `:closed`, `:closing`, or `:obstructed` to **`:opening`**.
- `close(pid)`: Transitions from `:open` or `:opening` to **`:closing`**.
- `obstruct(pid)`: Force-transitions any active state to **`:obstructed`**.
- `get_state(pid)`: Returns a snapshot of the internal state for diagnostics.

## Timers & Notifications

- **Transit Timer (`@op_ms`)**:
  - **1,000ms** (1 second) for both opening and closing cycles.
  - Upon completion, notifies the controller: `:door_opened` or `:door_closed`.
- **Safety Interrupt**:
  - Any active transit timer is cancelled immediately upon receipt of a `:door_obstructed` message.
  - Notifies the controller: `:door_obstructed`.

## Assumptions & Safety

1. **Idempotency**: Requests that match the current state (e.g., calling `open/1` while already `:open`) are ignored. These are logged and emitted via telemetry as *redundant requests*.
2. **Priority of Obstruction**: The `:door_obstructed` signal overrides any active command, ensuring passenger safety is prioritized over transit efficiency.
3. **Recovery Pattern**: Once in the `:obstructed` state, the door requires an explicit command (typically `open/1`) to resume operation. This ensures the Brain (Core) is aware of the obstruction before clearing it.
4. **Decoupled Timing**: The Controller does not "manage" the door's 1-second timer; it simply sends the command and waits for the hardware-level confirmation (`:door_opened` / `:door_closed`).
