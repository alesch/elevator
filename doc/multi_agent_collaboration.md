# Multi-Agent Collaboration Guide

This project is built for multiple AI agents to work together without conflicts. We achieve this through **Git Worktrees** and **Isolated Development Sandboxes**.

## 1. How to Setup a New Agent

If you are a new agent (or a human setting up an agent), run the following command from the repository root:

```bash
mix agent.setup <agent_name>
```

**This command automatically:**

- Creates a dedicated branch: `agent/<agent_name>`.
- Creates a separate folder for the agent: `agents/<agent_name>/`.
- Assigns a **Unique Parallel Port** (e.g., 4001, 4002) for their server.
- Symlinks heavy dependencies (`node_modules`, `mise.toml`, etc.) to save disk space and ensure matching tool versions.

---

## 2. Working in the Sandbox

Once the agent's sandbox is created, they should **stay inside their folder** and follow these rules:

1. **Check-In**: Before starting work, enter your details in `doc/agent_comms.md` on the **`main`** branch.
2. **Environment**: Use the generated `.env` file for your port settings.
3. **Starting the Server**:

   ```bash
   # Inside the agent folder
   PORT=4001 iex -S mix phx.server
   ```

4. **Committing**: Always commit to your local agent branch. **NEVER** push directly to `main` or `origin` from a worktree.

---

## 3. Merging Work (For Humans)

As the human editor-in-chief (Alex), you merge agent work into the `main` branch when it’s ready:

1. Review the agent's branch (`agent/<agent_name>`).
2. Merge it into `main`.
3. Delete the worktree when finished:

   ```bash
   git worktree remove agents/<agent_name>
   git branch -d agent/<agent_name>
   ```

---

## 4. Communication Rules

Agents **must** use the `doc/agent_comms.md` file as their "Shared Mission Log."

1. **Append-Only**: Never edit or delete previous lines. Always add your entry to the **bottom** of the file.
2. **Real-Time Sync**: Because this file is a **Symlink**, your status update is instantly visible across all other sandboxes and the project root.
3. **Draft Mode**: While your code is in a branch, your mission log entries provide a live "Checkpoint" for other agents to see what you are currently building.
