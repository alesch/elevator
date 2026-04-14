# Elevator System Architecture

This document describes the architecture of the elevator system, focusing on its distributed supervision and state persistence.

## 1. The FICS Pattern (Brain vs. Shell)

The system follows the **Functional Core, Imperative Shell (FICS)** pattern. This separates the risky, real-world interactions from the pure, safe logic.

* **The Functional Core (The Brain)**: `Elevator.Core` is a "pure" module. It does not perform any hardware I/O, network requests, or side effects. It takes a state, an event, and returns a new state.
* **The Imperative Shell (The Servo/Interface)**: This is where all the "messy" real-world interaction happens. This includes:
  * **`Elevator.Controller`**: Manages physical hardware (Motor, Doors).
  * **The Web Layer (Phoenix/LiveView)**: Handles user interaction and shows the elevator's status to the world in real-time.

## 2. Supervision Tree (The Firewall Strategy)

We use a nested supervision strategy to isolate hardware-level failures from the system's "memory" (the Vault).

```mermaid
graph TD
    Root["Elevator.Supervisor (one_for_one)"]
    Vault["Elevator.Vault (Persistent Agent)"]
    Stack["HardwareStack (one_for_all sub-supervisor)"]
    
    Root --> Vault
    Root --> Stack
    
    subgraph "Hardware Stack"
        Motor["Elevator.Motor"]
        Sensor["Elevator.Sensor"]
        Door["Elevator.Door"]
        Ctrl["Elevator.Controller"]
    end
    
    Stack --> Motor
    Stack --> Sensor
    Stack --> Door
    Stack --> Ctrl
```

> [!IMPORTANT]
> The top-level `:one_for_one` strategy acts as a firewall. If the `HardwareStack` crashes (e.g., due to a door obstruction), the `Vault` process is **not** restarted, preserving the last known floor arrival.

## 3. Boot & Recovery Sequence

FIXME:
The system performs a "Smart Homing" check during the recovery of the Hardware Stack.


## 4. Component Responsibilities

| Component | Responsibility | Failure Impact |
| :--- | :--- | :--- |
| **Vault** | Persistent storage of floor arrival | If wiped, system results in full homing from F0. |
| **Core** | **The Brain**: Autonomous logic & safety interlocks | If logic fails. |
| **Controller**| **The Servo**: Hardware mirror & change detection | If crashes, Hardware Stack reboots (Firewall). |
| **Motor** | Physical motion execution | Supports `:running` and `:crawling` statuses for REHOMING. |
| **Door** | Cabin access safety | Source of `obstruction` events for the Core. |
| **Sensor | Floor sensors | Signals when the elevator reaches a floor. |

## 5. The Golden Rule

The Core enforces a hard constraint: **The motor MUST be in the `:stopped` status unless the `door_status` is confirmed to be `:closed`.**

## 6. Technical State Transition Matrix

See the table here: [states.md](./states.md)
