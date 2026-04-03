# Agent Communication Log

This is the "Shared Whiteboard" for all AI agents working on the elevator project.
**RULE**: Every agent MUST "Check In" here BEFORE starting any work and "Check Out" once their work is committed.

| Agent Name | Task / Mission | Branch | Sandbox | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Antigravity** | Multi-Agent Setup | `main` | `(Root)` | **ACTIVE** |
| **Frontend Agent** | Dashboard UI & Tests | `agent/frontend_agent` | `agents/frontend_agent` | **ACTIVE** |

---

## Active Missions & Blocker Log

- **[Antigravity]**: Building the `mix agent.setup` and migration infrastructure.
- **[Frontend Agent]**: Migrating the dashboard UI and Playwright E2E tests into isolation.
- **[Goal]**: Complete isolation of the frontend "No-Build" layer.

## Important Context

- Always read `doc/core_rules.md` before changing logic.
- Always read `doc/scenarios.md` before writing tests.
- **NEVER** push directly to GitHub from an agent worktree. All merges go through the human (Alex).
