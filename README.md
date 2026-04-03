# 🚀 The Elixir Elevator Project

An elevator simulation built with **Elixir** and **Phoenix LiveView**. This project is a "Living Lab" for exercising the **Actor Model**, **FICS Architecture**, and engineering best practices.  
Coded with Antigravity using Gemini 3 Flash, and three agents collaborating.

---

## 🧠 Engineering Philosophy

### 1. SDD & TDD (Specification-Driven Development)

- **Ground Truth**: Every behavior is documented in **[`doc/scenarios.md`](doc/scenarios.md)** first.
- **Traceable TDD**: Every test is explicitly linked to a Scenario ID. No code is written until a failing test proves the need for it.

---

### 2. FICS (Functional Core, Imperative Shell)

The system is split into two halves:

- **The Brain (Functional Core)**: Pure, mathematical logic in `lib/elevator/core.ex`. It has no side effects and is 100% testable.
- **The Servo (Imperative Shell)**: The worker in `lib/elevator/controller.ex`. It monitors the Brain's intent and tells the hardware (Motor, Doors) what to do.

## 🛠️ The Tech Stack

- **Elixir (OTP)**: Using lightweight processes and immutable state for fault-tolerant logic.
- **Phoenix LiveView**: A real-time, "No-Build" frontend architecture. We use vanilla CSS and standard JavaScript.
- **Mise**: Automated toolchain management to ensure all developers (and agents) use the exact same versions of Elixir, Erlang, and Node.js.

---

## 🚢 CI/CD & Deployment

- **CI (GitHub Actions)**: Every commit is automatically verified through a comprehensive "Hardening Pipeline":
  - **TDD Compliance**: Running the full Elixir unit test suite (`ExUnit`).
  - **Hygiene**: Strict check for code formatting and code quality lints (`Credo`).
  - **Static Analysis**: Deep type-checking with **Dialyzer**.
  - **Security Hardening**: **Sobelow** for static security analysis and **Dependency Audit** for known vulnerabilities.
- **CD (Fly.io)**: Continuous deployment via an automated **Docker** build process.
  - Images are built and scanned on GitHub Actions, pushed to the GitHub Container Registry (**GHCR**), and deployed directly to the `arn` (Stockholm) region.

---

## 🤖 Multi-Agent Collaboration: "The Sandbox"

- **Git Worktrees**: Each agent works in their own isolated sandbox (e.g., `agents/ui_agent/`) with their own branch.
- **Parallel Servers**: Agents run their local GUI on dedicated ports (4000, 4001, etc.) via dynamic environment variables.
- **Live Mission Log**: A shared "Whiteboard" in **[`doc/agent_comms.md`](doc/agent_comms.md)** tracks missions in real-time across all sandboxes.

---

## 🔬 Quality Assurance

- **ExUnit**: High-reliability logic proofs for the Brain and parts of the Servo.
- **Playwright**: End-to-End GUI testing to verify the "Happy Path" in a real browser environment.

## 📂 Repository Atlas

- **[`lib/elevator/`](lib/elevator/)**: The **Functional Core** (The Brain). Pure logic and state transitions.
- **[`lib/elevator_web/`](lib/elevator_web/)**: The **Imperative Shell** (Human Interface). LiveView, GUI, and hardware-mapped controllers.
- **[`doc/`](doc/)**: Design specifications, scenarios, rules, and the multi-agent orchestration guide.
- **[`test/`](test/)**: High-reliability logic proofs and controller integration tests using `ExUnit`.
- **[`tests/`](tests/)**: End-to-End browser validation using `Playwright`.
- **[`agents/`](agents/)**: Private agent sandboxes.

---

*Created by **Alex Schenkman**, Gemini 3 Flash, and the Antigravity Collaboration Engine.*
