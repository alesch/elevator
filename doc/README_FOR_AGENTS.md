# Onboarding: The Elevator Project

Welcome to the Elevator Project. This document is the "Mental Map" for any agent working with **Alex**. It explains how the system is built, how we think about safety, and how we prove the code works.

---

## 1. The Developer: Alex

* **Background**: Deeply experienced **Java** and **Smalltalk** developer.
* **Perspective**: Values the **Actor Model** (message-passing) and process isolation.
* **The Pace**: We move **slowly and deliberately**. We don't rush, we don't bulk-generate code, and we always start with a concept before writing a line of Elixir.

---

## 2. The 3 Simple Laws of the System

Everything in this project follows these three core laws:

### Law 1: The Brain vs. The Servo

This is also known as the **FICS (Functional Core, Imperative Shell)** pattern.

The system is split into two parts:

1. **The Brain (Core)**: This is pure logic. It decides *what* the elevator wants to do. It has no "hands"; it cannot talk to hardware. (File: `lib/elevator/core.ex`)
2. **The Servo (Controller)**: This is the worker. It monitors the Brain's intent and tells the hardware (Motor, Doors) what to do to match that intent. It makes **zero** decisions. (File: `lib/elevator/controller.ex`)

### Law 2: Self-Correction

The Brain is designed to be **Self-Correcting**. Every time an event happens (a button press, a sensor pulse, an obstruction), the Brain recalculates its entire state from scratch. If something is wrong, it fixes its own "intent" automatically.

### Law 3: Built-in Safety

Safety is not a "check" or an `if` statement. It is built into the way the Brain thinks.

* **The Golden Rule**: The Brain physically *cannot* want the motor to run if the doors are not closed. If a door is open, the Brain automatically forces the motor to be stopped.

---

## 3. Real-World Physics

We simulate the real world as accurately as possible:

* **Timers**: Doors take 1 second to open. The motor takes 2 seconds to move between floors.
* **Homing**: If the system crashes, it doesn't just "guess" where it is. It moves slowly (`:slow`) until it physically hits a sensor to calibrate itself.

---

## 4. The Workflow (CRITICAL)

We follow a strict path for every change:

1. **Scenarios First**: Every behavior must be documented in `doc/scenarios.md` first.
2. **Tests Second**: We use **Traceable TDD**. Every test must have a comment or name that links it to a specific Scenario ID (e.g., `Scenario 2.1`).
3. **Code Third**: Only after the test failure is verified do we implement the logic in the Brain (`Core.ex`).

---

## 5. Ground Truth Files

* **[`doc/scenarios.md`](file:///home/alex/dev/elevator/doc/scenarios.md)**: The "Storybook" of what the system should do.
* **[`doc/core_rules.md`](file:///home/alex/dev/elevator/doc/core_rules.md)**: The "Rulebook" for the Brain's logic.
* **[`doc/ARCHITECTURE.md`](file:///home/alex/dev/elevator/doc/ARCHITECTURE.md)**: The "Blueprint" of the technical components.

> [!IMPORTANT]
> If you are an agent, do **NOT** rely on your memory of past conversations. Always read these three documents as the single source of truth before starting any task.
