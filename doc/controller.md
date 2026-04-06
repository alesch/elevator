# Technical Specification: Elevator Controller (The Imperative Shell)

The `Elevator.Controller` is the **Imperative Shell** of the system. It handles concurrency, integrates with physical hardware (via drivers), manages state persistence, and executes the actions determined by the **Core (Brain)**.

## Role & Responsibilities

1. **Hardware Orchestrator**: Manages the lifecycle and communication with the Motor, Door, and Sensor.
2. **State Manager**: Maintains the running `%Elevator.Core{}` state and coordinates its updates.
3. **Action Dispatcher**: Translates declarative actions from the Core (`{:move, direction}`) into physical hardware calls.
4. **Observer & Router**: Listens for hardware events (interrupts, confirmations) and routes them into the Core.
5. **Persistence Proxy**: Updates the **`Elevator.Vault`** with the last known position on every floor arrival.

## Component Integration (FICS)

The Controller acts as the glue between the **Pure Logic** and **Side Effects**:

```mermaid
sequenceDiagram
    participant H as Hardware / Timer
    participant C as Elevator.Controller
    participant B as Elevator.Core (Brain)
    participant V as Elevator.Vault

    H ->> C: Event (e.g., :motor_stopped)
    C ->> B: handle_event(state, event, now)
    B -->> C: {new_state, actions}
    C ->> C: Update local state
    loop For each Action
        C ->> H: Side Effect (e.g., :open_door)
    end
    C ->> V: Persistence (if floor arrival)
```

## Public API

### Commands (Async casts)

- `request_floor(source, floor)`: Submits a new trip request. Includes source tagging (`:car` or `:hall`).
- `open_door()`: Manual override to open the doors.
- `close_door()`: Manual override to close the doors.

### Diagnostics (Sync calls)

- `get_state()`: Returns a snapshot of the current `%Elevator.Core{}` state.
- `get_timer_ref()`: Returns the Erlang timer reference for the "Return to Base" sequence.

### System Control

- `reset()`: Destructive recovery. Clears the Vault and kills the **`Elevator.HardwareSupervisor`**. Because of the `:one_for_all` strategy, this forces a full reboot of the hardware stack and the Controller, triggering a new rehoming sequence.

## Hardware Discovery & Architecture

The Controller uses an discovery strategy managed by the **`Elevator.HardwareSupervisor`**:

1. **Registry Lookup**: Actors (Motor, Door, Sensor) register themselves with the **`Elevator.Registry`**. The Controller performs a lookup to obtain their PIDs during command execution.
2. **Dependency Injection**: For testing, specific PIDs can still be provided during `init/1` (via the `:motor`, `:door`, etc. keys in `opts`) to bypass registry lookup.
3. **Fatal Failures**: The Hardware Supervisor uses a `:one_for_all` strategy. If any hardware actor crashes, the entire stack (including the Controller) is rebooted to ensure logical consistency.

## Homing & Recovery Logic

Upon startup (`handle_continue`), the Controller executes a "Smart Homing" check. This process is the bridge between hardware discovery and the Brain's logic:

1. **State Gating**: The system starts with the Brain in the `:booting` phase, where all external movement requests are ignored.
2. **Hardware Sync**: The Controller queries both the **`Elevator.Vault`** (persisted position) and the **`Hardware.Sensor`** (current physical position).
3. **Case 1 (Zero-Move Recovery)**: If `Vault` and `Sensor` agree on a floor, the Controller notifies the Brain with `:recovery_complete`. The Brain transitions to `:idle` immediately.
4. **Case 2 (Physical Rehoming)**: If they disagree or position is `:unknown`, the Controller notifies the Brain with `:rehoming_started`. The Brain transitions to `:rehoming` and triggers a `:down` movement at `:crawling` speed.

## Action Materialization

| Action Variable | Execution |
| :--- | :--- |
| `{:move, dir}` | Calls `Hardware.Motor.move(pid, dir)`. |
| `{:crawl, dir}` | Calls `Hardware.Motor.crawl(pid, dir)`. |
| `{:stop_motor}` | Calls `Hardware.Motor.stop(pid)`. |
| `{:open_door}` | Calls `Hardware.Door.open(pid)`. |
| `{:close_door}` | Calls `Hardware.Door.close(pid)`. |
| `{:set_timer, id, ms}` | Executes `Process.send_after(self(), {:timeout, id}, ms)`. |
| `{:cancel_timer, id}` | *MVP Note: Currently a NO-OP. Cancellation is handled by idempotency in the Brain.* |

## Observability (Telemetry)

The Controller emits the following standard telemetry events:

- `[:elevator, :controller, :recovery]`: Emitted on successful Zero-Move recovery.
- `[:elevator, :controller, :rehoming]`: Emitted when physical homing begins.
- `[:elevator, :controller, :request]`: Emitted when a new request is successfully submitted.
- `[:elevator, :controller, :arrival]`: Emitted on every floor arrival before persistence.
