# 🚀 The Elevator Project

A professional industrial simulation built with **Elixir** and **Phoenix LiveView**. This project is a "Living Lab" for mastering the **Actor Model**, **FICS Architecture**, and professional-grade engineering discipline.

---

## 🧠 Engineering Philosophy: "Slow and Deliberate"

We don't just "guess" at code. Every line of logic in this system is born from a formal specification and proven with a test.

### 1. FICS (Functional Core, Imperative Shell)
The system is split into two halves:
- **The Brain (Functional Core)**: Pure, mathematical logic in `lib/elevator/core.ex`. It has no side effects and is 100% testable.
- **The Servo (Imperative Shell)**: The worker in `lib/elevator/controller.ex`. It monitors the Brain's intent and tells the hardware (Motor, Doors) what to do.

### 2. SDD & TDD (Specification-Driven Development)
- **Ground Truth**: Every behavior must be documented in **[`doc/scenarios.md`](doc/scenarios.md)** first.
- **Traceable TDD**: Every test is explicitly linked to a Scenario ID (e.g., `Scenario 1.2`). No code is written until a failing test proves the need for it.

---

## 🛠️ The Tech Stack

- **Elixir (OTP)**: Using lightweight processes and immutable state for fault-tolerant logic.
- **Phoenix LiveView**: A real-time, "No-Build" frontend architecture. We use vanilla CSS and standard JavaScript for a premium, lightweight experience.
- **Mise**: Automated toolchain management to ensure all developers (and agents) use the exact same versions of Elixir, Erlang, and Node.js.

---

## 🚢 CI/CD & Deployment

- **CI (GitHub Actions)**: Every commit is automatically verified for:
    - **TDD Compliance**: Running the full Elixir unit test suite.
    - **Hygiene**: Checking for code formatting and lints.
- **CD (Fly.io)**: Continuous deployment to the `arn` (Stockholm) region. The system is production-ready and updates automatically when `main` moves forward.

---

## 🤖 Multi-Agent Collaboration: "The Sandbox"

Built for scale, this project supports simultaneous AI agent collaboration through a professional isolation system:
- **Git Worktrees**: Each agent works in their own isolated sandbox (e.g., `agents/ui_agent/`) with their own branch.
- **Parallel Servers**: Agents run their local GUI on dedicated ports (4000, 4001, etc.) via dynamic environment variables.
- **Live Mission Log**: A shared "Whiteboard" in **[`doc/agent_comms.md`](doc/agent_comms.md)** tracks missions in real-time across all sandboxes.

---

## 🔬 Quality Assurance

- **ExUnit**: High-reliability logic proofs for the Brain.
- **Playwright**: End-to-End GUI testing to verify the "Happy Path" in a real browser environment.

---

## 🚀 Getting Started

To join the project as an agent:
1. Read the **[`doc/README_FOR_AGENTS.md`](doc/README_FOR_AGENTS.md)**.
2. Setup your private sandbox: `mix agent.setup <your_name>`.
3. Start your parallel server: `PORT=4000 iex -S mix phx.server`.

---
*Created by **Alex Schenkman** as a professional Elixir learning experience.*
