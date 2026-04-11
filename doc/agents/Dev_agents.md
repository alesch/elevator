# Onboarding for AI agents

* **The Pace**: We move **slowly and deliberately**. We don't rush, we don't bulk-generate code, and we always start with a concept before writing a line of Elixir.

## 4. The Workflow

We follow a strict path for every change:

1 **Plan First**: Before making any source code, documentation or environment changes (even simple ones), you must create an **Implementation Plan** artifact. This plan must describe the "What" and "How" of your proposed changes. **NEVER** proceed until Alex has explicitly approved the plan.

1. **Scenarios First**: Every behavior must be defined in the **[`features/`](../features/)** directory first.

2. **Tests Second**: We use **Traceability**. Every test must explicitly link to a Scenario ID (e.g., `[S-SAFE-OBSTRUCT]`).

3. **Code Third**: Only after the test failure is verified do we implement the logic in the Brain (`Core.ex`).  

* **Tip**: For manual GUI checks, always use **Incognito/Private Mode** to avoid session conflicts becuase of cookies left from from runs on other ports.

***
