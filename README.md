# Modelling and elevator with Elixir 

This is an elevator simulation built with **Elixir** and **Phoenix LiveView**. I've built this to learn Elixir, and got to exercise the following:
- the **Actor Model**
- a **pure functional architecture**
- Augmented AI developmen with Zed, and Sonnet 4.6 
- Multiagent orchestration with Antigravity and Gemini 3 Flash
- **BDD** with gherkin features and scenarios
- **TDD** with regular Exunit 
- End-to-end (**e2e**) testing with Playwright and ExUnit
- Continuos integration (**CI/CD**) with **Github actions**.
- Quality gates with static and security analysis (**OWASP**) 
- Deployment with **Docker** on fly.io.

---

## Specifications

All specs are inside [`doc/specs/`](doc/spec/)
- **Rules**: Business logic in [`rules.md`](doc/spec/core_rules.md).
- **Behaviors**: Observable behavior is defined in formal Gherkin feature files within the [`features/`](features/) directory.
- **Traceability**: Every test is explicitly linked to a Scenario ID (e.g., `[S-MOVE-WAKEUP]`). No code is written until a failing test proves the need for it. See [`traceability.md`](doc/specs/traceability.md)

---

## Architecture overview

The system is built around a brain containing all the logic and simple and quite dumb components collaborating through a message bus. See [`architecture.md`](doc/architecture.md)

---

## The Tech Stack

- **Elixir (OTP)**: Using lightweight processes and immutable state for concurrent fault-tolerant logic.
- **Phoenix LiveView**: A real-time, "No-Build" frontend architecture. With vanilla CSS and standard JavaScript.
- **Mise**: Automated toolchain management to ensure all developers (and agents) use the exact same versions of Elixir, Erlang, and Node.js.

---

## CI/CD & Deployment

See [`doc/ci_cd_pipeline.md`](doc/ci_cd_pipeline.md)

---

## Multi-Agent Collaboration: "The Sandbox"

- **Git Worktrees**: Each agent works in their own isolated sandbox (e.g., `agents/ui_agent/`) with their own branch.
- **Parallel Servers**: Agents run their local GUI on dedicated ports (4000, 4001, etc.) via dynamic environment variables.
- **Live Mission Log**: A shared "Whiteboard" in **[`doc/agent_comms.md`](doc/agent_comms.md)** tracks missions in real-time across all sandboxes.

---

## Quality Assurance

- **ExUnit**: High-reliability logic proofs for the Brain and parts of the Servo.
- **Playwright**: End-to-End GUI testing to verify the "Happy Path" in a real browser environment.

## Repository Atlas

### Core Directories

- **[`lib/elevator/`](lib/elevator/)**: The **Functional Core** (The Brain). Pure logic and state transitions.
- **[`lib/elevator_web/`](lib/elevator_web/)**: The **Imperative Shell** (Human Interface). LiveView, GUI, and hardware-mapped controllers.
- **[`test/`](test/)**: High-reliability logic proofs and controller integration tests using `ExUnit`.
- **[`tests/`](tests/)**: End-to-End browser validation using `Playwright`.
- **[`agents/`](agents/)**: Private agent sandboxes.

---

## Table of contents ([`doc/`](doc/))

```
doc/
├── architecture.md                    # System architecture overview
├── ci_cd_pipeline.md                  # CI/CD and deployment configuration
├── pending.md                         # Outstanding tasks and future work
├── simulation.md                      # Simulation mechanics and design
│
├── agents/                            # Multi-agent collaboration guide
│   ├── README.md                      # Sandbox and orchestration overview
│   ├── Dev_agents.md                  # Development agent roles
│   ├── GUI_agents.md                  # UI/Frontend agent roles
│   ├── Bug_Reporting.md               # Bug reporting procedures
│   └── gherkin-refactoring.md         # Gherkin refactoring work
│
├── components/                        # Detailed component specifications
│   ├── core.md                        # Core (Brain) module design
│   ├── controller.md                  # Controller component design
│   ├── pulse.md                       # Pulse (timing) mechanism
│   │
│   └── hardware/                      # Hardware component specifications
│       ├── door.md                    # Door component
│       ├── motor.md                   # Motor component
│       └── sensor.md                  # Sensor component
│
└── specs/                             # Formal specifications
    ├── rules.md                       # Business logic and rules
    ├── states.md                      # State machine transitions (source of truth)
    ├── scenarios.md                   # Test scenarios catalog
    ├── traceability.md                # Test-to-scenario traceability matrix
    └── gherkin_library.md             # Gherkin syntax and patterns
```

---

*Created by **Alex Schenkman**, on April 2026*
