# Onboarding for AI agents

* **The Pace**: We move **slowly and deliberately**. We don't rush, we don't bulk-generate code, and we always start with a concept before writing a line of code.

## 4. The Workflow

We follow a strict path for every change:

1 **Plan First**: Before making any source code, documentation or environment changes (even simple ones), you must create an **Implementation Plan** artifact. This plan must describe the "What" and "How" of your proposed changes. **NEVER** proceed until Alex has explicitly approved the plan.

2 **Only one thing at the time**: Focus on one task at the time. If you find a bug while you are working, you must stop and report it to Alex.

3 **Split complex tasks**: If a task is complex, split it into smaller plan artifacts and get approval for each artifact.

4 **No rabbit holes**: If things are not going your way after two iterations, STOP and ask Alex for guidance.

## 5. Ground Truth Files

* **[`doc/rules.md`](file:///home/alex/dev/elevator/doc/rules.md)**: The "Rulebook" for the Brain's logic.

* **[`states.md`](file:///home/alex/dev/elevator/doc/states.md)**: All the valid states and transitions for the Core and the Controller.

* **[`features/`](file:///home/alex/dev/elevator/features/)**: The "Storybook" of what the system should do, defined in formal Gherkin scenarios.

* **[`doc/ARCHITECTURE.md`](file:///home/alex/dev/elevator/doc/ARCHITECTURE.md)**: The "Blueprint" of the technical components.

* **[`doc/pulse.md`](file:///home/alex/dev/elevator/doc/pulse.md)**: Describes the Pulse implementation in the Core.
