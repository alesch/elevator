# Agent Brief: Elevator Supervisor Architect

## 1. Mission

Build the **`Elevator.Supervisor`**. Its job is to guarantee the entire system's availability through fault-tolerance.

## 2. Constraints

*   **Process Watchdog**: If the Motor, Door, or Controller crashes, you must handle its revival.
*   **Strategy**: Implement a **`:one_for_all`** or **`:rest_for_one`** restart strategy (See architectural debate).

## 3. The Contract (See `doc/PROTOCOL_SPEC.md`)

*   Orchestrate the following children:
    1.  `Elevator.Controller`
    2.  `Elevator.Motor`
    3.  `Elevator.Sensor`
    4.  `Elevator.Door`

## 4. Testing

*   Implement `test/supervision_test.exs`.
*   **The Killing Proof**: Use **`Process.exit(pid, :kill)`** or **`Process.monitor/1`** to verify that if a subsystem dies, the Supervisor reboots it instantly without loss of global health.

## 5. Completion Signal (MANDATORY)

When your mission is 100% complete and tests are GREEN:

1.  Use (**and create if necessary**) the directory: `handover_status/`
2.  Create the file: `handover_status/DONE_SUPERVISOR`.
3.  Write your **Absolute Worktree Path** and a 1-sentence summary inside.

## 6. Supervisor Authority

The **Final Supervisor (Antigravity Original)** will review your supervision tree and restart policies. 🚀🏾
