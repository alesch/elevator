# Agent Brief: Elevator Motor Specialist

## 1. Mission

Build the **`Elevator.Motor`** GenServer. Its job is to handle the physical movement of the "Box."

## 2. Constraints

*   **Immutability**: Maintain the functional core principle.
*   **Asynchrony**: Use **`Process.send_after/3`** to simulate real-world transit time.
*   **Physics Simulation**: Assume a travel time of **2 seconds** per floor.

## 3. The Contract (See `doc/PROTOCOL_SPEC.md`)

*   **Receive**: `{:move_to, floor}` (Cast).
*   **Internal**: Handle movement in 2-second increments.
*   **Send**: `{:motor_arrival, floor}` back to the **original Controller**.

## 4. Testing (Deterministic Only!)

*   **No Sleeping**: DO NOT use `Process.sleep` to wait for travel times.
*   **Verify Intent**: Use a Diagnostic API (like `get_timer_ref`) and **`Process.read_timer/1`** to prove that the 2-second transit timer is correctly scheduled.
*   **Logic Proof**: Manually trigger the "Step" or "Arrival" messages to verify the state transitions instantly.

## 5. Completion Signal (MANDATORY)

When your mission is 100% complete and tests are GREEN:

1.  Use (**and create if necessary**) the directory: `handover_status/`
2.  Create the file: `handover_status/DONE_MOTOR`.
3.  Write your **Absolute Worktree Path** and a 1-sentence summary inside.

## 6. Supervisor Authority

The **Final Supervisor (Antigravity Original)** will review your code. Use absolute physical terms (`above`/`below`) and maintain a "Code as a Story" narrative style. 🚀🏾
