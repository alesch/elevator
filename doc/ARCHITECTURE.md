# Elevator System Architecture

This document describes the "Memory and Recovery" architecture of the elevator system, focusing on its distributed supervision and state persistence.

## 1. Supervision Tree (The Firewall Strategy)

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

## 2. Boot & Recovery Sequence

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

## 3. Controller State Machine

The Controller manages the functional state based on physical inputs.

```mermaid
stateDiagram-v2
    [*] --> Init
    Init --> rehoming: Boot Mismatch
    Init --> normal: Boot Match
    
    rehoming --> normal: floor_arrival (Physical confirmation)
    
    normal --> normal: request_floor / movement
    normal --> overload: weight_threshold (Planned)
    normal --> emergency: emergency_trigger (Planned)
    
    overload --> normal: weight_within_limit
    emergency --> rehoming: reset_system
```

## 4. Component Responsibilities

| Component | Responsibility | Failure Impact |
| :--- | :--- | :--- |
| **Vault** | Persistent storage of floor arrival | If wiped, system results in full homing from F0. |
| **Sensor** | Maps motor pulses to floors | If fails, entire Hardware Stack reboots. |
| **Controller** | Primary logic & state transitions | Manages timers and command coordination. |
| **Motor** | Physical motion execution | Supports `:normal` and `:slow` speeds. |
| **Door** | Cabin access safety | Most common source of process crashes (obstructions). |
