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
* **Documentation Sync**: Always keep `doc/controller_rules.md` and `doc/scenarios.md` updated and in 1:1 sync with the logic code. They are the "Ground Truth."
* **Note to Agent**: The brain artifacts are periodically cleaned up to reduce noise. Use the docs in `/doc/` as the single source of truth.

---

## 4. "Clean Code" Preferences (Alex's Style)

* **Code as a Story**: Code must be readable from top to bottom. Use the pipe operator `|>` to make state transformations a narrative.
* **No Redundant Comments**: Descriptive naming is superior to repetition. Delete any comment that doesn't add a unique semantic insight.
* **Mission-Critical Spec**: Include `@spec` for ALL functions (including private ones) for total internal transparency.
* **Visual Grouping**: Use clear section headers in modules to separate "Public API" from "Internal Logic."
* **Observable Catch-alls**: Always use `Logger.warning` in catch-all function clauses to surface unexpected events immediately.
