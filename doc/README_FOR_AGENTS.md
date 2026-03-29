# Agent Onboarding: Elevator Project

This document is for future AI agents working with **Alex** on the Elixir Elevator project. It captures the implicit context and project philosophy gathered so far.

## 1. The User: Alex

* **Background**: Deeply experienced **Java** developer; also an expert in **Smalltalk**.
* **Perspective**: Values the **Actor Model**, message-passing, and process isolation.
* **Communication Style**: Use Java/Smalltalk analogies (BEAM vs. JVM, pure messaging vs. method calls).
* **Pace**: Prefers a **slow, deliberate, and conceptual-first** approach. No rushing or bulk code generation.

## 2. Project Philosophy

* **Learning First**: Focus on Elixir's core concepts: Immutability, Pattern Matching, Concurrency.
* **Architectural Separation**: The system is modeled as independent components:
  * **Elevator Box**: Physical state.
  * **Door**: Independent safety component with its own state machine.
  * **Controller**: The "central brain" that orchestrates everything.
  * **Motor**: Independent component with its own state machine.
  * **Weight Sensor**: Independent component with its own state machine.
  * **Button Panel**: Independent component with its own state machine.
  * **Floor Sensor**: Independent component with its own state machine.
* **TDD Methodology**: Every logic change MUST start with a failing `ExUnit` test. "Red -> Green -> Refactor" is mandatory.
* **Functional Core, Imperative Shell**: Maintain pure logic in `lib/elevator/state.ex` before wrapping in `GenServers`.

## 3. Rules for agents (CRITICAL)

* **Command Restriction**: Do NOT run commands on files outside this project directory.
* **Note to Agent**: The brain artifacts are periodically cleaned up to reduce noise. Use the docs in `/doc/` as the single source of truth.
