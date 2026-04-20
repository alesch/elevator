# Gherkin Refactoring Methodology: Behavioral Excellence

This document outlines the methodology used to refactor technical, state-machine-focused Gherkin scenarios into high-quality, domain-focused behavioral stories. Future agents should follow these pillars when extending the **Elevator Simulation** test suite.

## 1. Shift to Behavioral Language

**The Rule**: Never leak internal state fields (`phase`, `motor_status`, `heading`) into the storybooks.

- **Technical (Legacy)**: `Then the "phase" should be ":booting"`
- **Behavioral (New)**: `Then the elevator should remain inert`

> [!TIP]
> Describe what a **passenger** observes, not what the **database** stores.

## 2. Scenario Independence

**The Rule**: Every scenario must be a standalone "one-shot" story. Avoid "Scenario chains" where the state of one depends on the success of the previous.

- **Requirement**: Always provide a clear foundation (e.g., `Given the elevator is idle at floor 3`).
- **Constraint**: If a scenario describes a transition (like doors opening), set the context first: `Given the elevator has arrived at floor 3` or `Given the elevator is idle at floor 3 and the doors are opening`.

## 3. The Central Step Dictionary

**The Rule**: All phrasing MUST be synchronized with [gherkin_library.md](file:///home/alex/dev/elevator/doc/gherkin_library.md).

- **Standardization**: Use parameterized placeholders like `{floor}`, `{direction}`, and `{time}`.
- **Floor Naming**: Use **`floor ground`** instead of `floor 0` or `the ground floor` for maximum reusability with numeric floors (e.g., `floor 3`).

## 4. Rule-First Traceability

**The Rule**: Every scenario must be tagged with its corresponding business rule from [core_rules.md](file:///home/alex/dev/elevator/doc/core_rules.md).

- **Mapping**: Use tags like `@S-MOVE-WAKEUP @R-MOVE-WAKEUP`.
- **Synchronization**: If a scenario is updated, the [traceability.md](file:///home/alex/dev/elevator/doc/traceability.md) matrix must be updated accordingly.

## 5. Iterative Refinement Workflow

0. We do one scenario at a time.
1. **Plan First**: Propose a "Story Map" to the user using an implementation plan, showing the current scenario and the proposed changes.
2. **Phrasing Sweep**: Standardize all verbs (e.g., use **"be"** instead of "become", remove **"automatically"**).
3. **Audit**: Compare the feature file against the **Step Library** to ensure 100% synchronization.
4. **Finalize**: Apply the changes only after user approval of the behavioral flow.
