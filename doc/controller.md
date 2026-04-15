# Elevator Controller (The Imperative Shell)

The `Elevator.Controller` is the **Imperative Shell** of the system. It handles concurrency, integrates with physical hardware (via drivers), manages state persistence, and executes the actions determined by the **Core (Brain)**.

## Role & Responsibilities

1. **Hardware Orchestrator**: Manages the lifecycle and communication with the Motor, Door, and Sensor.
2. **State Manager**: Maintains the running `%Elevator.Core{}` state and coordinates its updates.
3. **Action Dispatcher**: Translates declarative actions from the Core (`{:move, direction}`) into physical hardware calls.
4. **Observer & Router**: Listens for hardware events (interrupts, confirmations) and routes them into the Core.
5. **Persistence Proxy**: Updates the **`Elevator.Vault`** with the last known position on every floor arrival.

## Component Integration (FICS)

The Controller acts as the glue between the **Pure Logic** and **Side Effects**. See the sequence diagram in the source for a visual overview.

## Public API

### Commands (Async casts)

- `request_floor(source, floor)`: Submits a new trip request. Includes source tagging (`:car` or `:hall`).
- `open_door()`: Manual override to open the doors.
- `close_door()`: Manual override to close the doors.

### Diagnostics (Sync calls)

- `get_state()`: Returns a snapshot of the current `%Elevator.Core{}` state.
- `get_timer_ref()`: Returns a map of `%{timer_id => reference()}` for all active timers. Intended for diagnostics only.

### System Control

- `reset()`: Destructive recovery. Clears the Vault and kills the **`Elevator.HardwareSupervisor`**. Because of the `:one_for_all` strategy, this forces a full reboot of the hardware stack and the Controller, triggering a new rehoming sequence.

## Hardware Discovery & Architecture

The Controller uses a discovery strategy managed by the **`Elevator.HardwareSupervisor`**:

1. **Registry Lookup**: Actors (Motor, Door, Sensor) register themselves with the **`Elevator.Registry`**. The Controller performs a lookup to obtain their PIDs during command execution.
2. **Dependency Injection**: For testing, specific PIDs can still be provided during `init/1` (via the `:motor`, `:door`, etc. keys in `opts`) to bypass registry lookup.
3. **Fatal Failures**: The Hardware Supervisor uses a `:one_for_all` strategy. If any hardware actor crashes, the entire stack (including the Controller) is rebooted to ensure logical consistency.

## Homing & Recovery Logic

Upon startup (`handle_continue`), the Controller executes a "Smart Homing" check. This process is the bridge between hardware discovery and the Brain's logic:

1. **State Gating**: The system starts with the Brain in the `:booting` phase, where all external movement requests are ignored.
2. **Hardware Sync**: The Controller queries both the **`Elevator.Vault`** (persisted position) and the **`Hardware.Sensor`** (current physical position).
3. **Brain Consultation**: The hardware data is sent to the Core via the `:startup_check` event. The Core then determines whether a **Zero-Move Recovery** or **Physical Rehoming** is required.

---
> See [states.md](doc/states.md) for the detailed transition logic during the recovery sequence.
---

## Events Sent to Core

The Controller translates hardware signals and timer expirations into discrete events for the Core to process.

| Event | Condition / Source |
| :--- | :--- |
| **`:startup_check`** | Sent during `handle_continue` to verify position recovery. |
| **`:floor_arrival`** | Triggered by the physical floor sensors via `process_arrival/2`. |
| **`:motor_stopped`** | Feedback from the motor driver confirming zero velocity. |
| **`:motor_running`** | Feedback from the motor driver confirming the motor is now moving. |
| **`:motor_crawling`** | Feedback from the motor driver confirming low-speed crawl mode. |
| **`:door_opened`** | Feedback from the door driver confirming full open status. |
| **`:door_closed`** | Feedback from the door driver confirming full closed status. |
| **`:door_opening`** | Feedback from the door driver confirming the door has begun opening. |
| **`:door_closing`** | Feedback from the door driver confirming the door has begun closing. |
| **`:door_obstructed`** | Signal from the door safety beam (IR sensor). |
| **`:door_cleared`** | Signal from the door safety beam confirming the obstruction has been removed. |
| **`:door_timeout`** | The logic-controlled timer for how long doors remain open. |
| **`:door_open`** | Manual override button from the car panel. |
| **`:door_close`** | Manual override button from the car panel. |

---

## Action Materialization

| Action Variable | Execution |
| :--- | :--- |
| `{:move, dir}` | Calls `Hardware.Motor.move(pid, dir)`. |
| `{:crawl, dir}` | Calls `Hardware.Motor.crawl(pid, dir)`. |
| `{:stop_motor}` | Calls `Hardware.Motor.stop(pid)`. |
| `{:open_door}` | Calls `Hardware.Door.open(pid)`. |
| `{:close_door}` | Calls `Hardware.Door.close(pid)`. |
| `{:set_timer, id, ms}` | Calls `Process.send_after(self(), {:timeout, id}, ms)` and stores the ref in `data.timers[id]`. |
| `{:persist_arrival, floor}` | Calls `Elevator.Vault.put_floor(pid, floor)`. |

## Observability (Telemetry)

The Controller emits the following telemetry events:

- `[:elevator, :controller, :event]`: Emitted in `pulse_and_commit` on every processed event. Metadata includes `:type` and event-specific fields.
- `[:elevator, :controller, :timer_expired]`: Emitted when a `{:timeout, id}` message is received. Metadata: `%{id: id}`.
- `[:elevator, :controller, :hardware_failure]`: Emitted when a required hardware dependency cannot be found in the registry. Metadata: `%{key: key}`.
- `[:elevator, :controller, :unexpected_message]`: Emitted in the catch-all `handle_info` clause for unrecognised messages. Metadata: `%{message: msg}`.
- `[:elevator, :controller, :unhandled_action]`: Emitted in the catch-all `do_execute` clause for unrecognised actions. Metadata: `%{action: action}`.
