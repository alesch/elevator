# Handover: Frontend Agent Migration

Welcome to your new isolated workspace! To ensure safe collaboration and prevent conflicts with other agents, you have been moved to a dedicated **Git Worktree**.

## 1. Your Workspace

- **Physical Directory**: `agents/frontend_agent/`
- **Git Branch**: `agent/frontend_agent`
- **Parallel Port**: `4001`

**ACTION**: From now on, please perform all your work **inside** the `agents/frontend_agent/` directory.

---

## 2. Running your Server

To run your local GUI and verify changes without conflicting with the main project, use the assigned port:

```bash
# Inside agents/frontend_agent/
PORT=4001 iex -S mix phx.server
```

---

## 3. Communication Protocol
Before starting any new task, please "Check In" on our **Shared Whiteboard**:

- **File**: `doc/agent_comms.md` (on the `main` branch).
- Update your status to **ACTIVE** and describe what you are currently building.

## 4. Final Submission

When your tasks are completed and tests pass:

1. Commit your changes to the `agent/frontend_agent` branch within your worktree.
2. Notify the human (Alex) that your work is ready for a merge review.
3. **DO NOT** push directly to `main`.
