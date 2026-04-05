# Elevator System Architecture

This document describes the architecture of the elevator system, focusing on its distributed supervision and state persistence.

## 1. The FICS Pattern (Brain vs. Shell)

The system follows the **Functional Core, Imperative Shell (FICS)** pattern. This separates the risky, real-world interactions from the pure, safe logic.

* **The Functional Core (The Brain)**: `Elevator.Core` is a "pure" module. It does not perform any hardware I/O, network requests, or side effects. It takes a state, an event, and returns a new state.
* **The Imperative Shell (The Servo/Interface)**: This is where all the "messy" real-world interaction happens. This includes:
  * **`Elevator.Controller`**: Manages physical hardware (Motor, Doors).
  * **The Web Layer (Phoenix/LiveView)**: Handles user interaction and shows the elevator's status to the world in real-time.

### 1.1 Autonomous Core Pipeline (Decision Logic)

All decision-making logic resides in the `Elevator.Core` module's `apply_constraints/1` pipeline, which is idempotent and side-effect free.

```mermaid
stateDiagram-v2
    [*] --> Init
    Init --> rehoming: Boot Mismatch
    Init --> normal: Boot Match
    
    state "Autonomous Core (Brain)" as Core {
        direction LR
        apply_constraints --> start_moving
        start_moving --> apply_constraints
        apply_constraints --> enforce_safety
    }

    rehoming --> normal: [S-HOME-ANCHOR] (Floor confirmation)
    normal --> Core: Event / Request
    Core --> normal: Valid Intent
```

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

The system performs a "Smart Homing" check during the recovery of the Hardware Stack.

```mermaid
sequenceDiagram
    participant V as Elevator.Vault
    participant S as Elevator.Sensor
    participant C as Elevator.Controller
    participant M as Elevator.Motor

    Note over C,M: Hardware Reboot Sequence
    S->>V: get_floor() (Sync on init)
    V-->>S: Last Known Floor (e.g., F1)
    
    C->>V: get_floor()
    V-->>C: Last Known Floor (e.g., F1)
    C->>S: get_floor()
    S-->>C: Current Sensor Status (e.g., F1)
    
    alt Floors Match (Zero-Move)
        C->>C: Transition to :normal
    else Mismatch or Between Floors
        C->>C: Transition to :rehoming
        C->>M: move(:down, speed: :slow)
    end
```

## 4. Component Responsibilities

| Component | Responsibility | Failure Impact |
| :--- | :--- | :--- |
| **Vault** | Persistent storage of floor arrival | If wiped, system results in full homing from F0. |
| **Core** | **The Brain**: Autonomous logic & safety interlocks | If logic fails. |
| **Controller**| **The Servo**: Hardware mirror & change detection | If crashes, Hardware Stack reboots (Firewall). |
| **Motor** | Physical motion execution | Supports `:normal` and `:slow` speed for REHOMING. |
| **Door** | Cabin access safety | Source of `obstruction` events for the Core. |

## 5. Safety Interlocks (Structural Safety)

Following the refactoring to an Autonomous Core, safety is no longer "checked" by the Controller; it is **structurally guaranteed** by the Core's state transition pipeline.

### 5.1 The Golden Rule

The Core enforces a hard constraint: **The motor MUST be in the `:stopped` status unless the `door_status` is confirmed to be `:closed`.**

If any event (like a manual door opening or an obstruction) violates this, the `apply_constraints/1` pipeline automatically corrects the intent by stopping the motor before the Controller can even dispatch the command to hardware.
