# Agent Reflections: The Motor Specialist

This document captures the architectural insights and design shifts encountered during the initialization of the `Elevator.Motor` actor.

## 🧠 Key Learnings

### 1. The "Dumb Muscle" Principle

Initially, I assumed the Motor needed to track its own position and "know" when it arrived at a floor to send a confirmation. However, the **Lead Architect** clarified a more decoupled, "pure" actor model:

- **Proprioception is externalized**: Motor has no internal map of the shaft.
- **Actuation is pure**: Motor only knows `:running` (Up/Down) or `:stopped`.

### 2. Separation of Nerves and Muscle

The interaction between the Motor and the Sensor is indirect.

- The Motor doesn't tell the Sensor it's moving.
- The Sensor "watches" the Motor's state to determine when to trigger its own "Physical Position" logic.
- This prevents a direct dependency between physical sub-systems.

### 3. Controller-Directed Termination

The Motor's lifecycle for a journey is:

1. **Start**: Triggered by the Controller (`{:move, direction}`).
2. **Run**: Infinite "force application" until interrupted.
3. **Stop**: Explicitly commanded by the Controller (`:stop_now`) based on the Sensor's "Logical Arrival."

---

## ❓ Architectural Clarifications (Resolved)

| Question to Architect | Resolution |
| :--- | :--- |
| **Does Motor notify Sensor?** | **No**. They are decoupled. The Sensor observes the Motor. |
| **Does Motor know its position?** | **No**. Only the Sensor/Controller track location. |
| **Should Motor send `motor_arrival`?** | **Deprecated**. This message was removed from the contract. |
| **How does Motor know direction?** | **Dumb Vector (Option B)**. The Motor follows a simple `{:move, :up}` or `{:move, :down}` command. It is agnostic to "Floors" entirely. |

---

## 🎯 Updated Strategy

The command structure is now fully decoupled from building geography:

- `{:move, :up}` / `{:move, :down}` ➔ Apply force indefinitely.
- `:stop_now` ➔ Full brake.

This ensures the "Muscular System" remains 100% blind and reusable for any shaft height.

*Authenticated by: Motor Agent (Antigravity-Flash)* 🏹🏾
