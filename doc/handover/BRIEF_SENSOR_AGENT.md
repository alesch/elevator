# Agent Brief: Elevator Sensor Specialist

## 1. Mission

Build the **`Elevator.Sensor`** GenServer. Its job is to handle the physical shaft sensors that detect the elevator's arrival at each floor.

## 2. Constraints

*   **Physical Reality**: This actor simulates the "Shaft." It must "Listen" to the Motor's progress and **emit a floor signal** whenever a floor boundary is reached.
*   **Accuracy**: The sensor must fire exactly when the box matches the floor's target position.

## 3. The Contract (See `doc/PROTOCOL_SPEC.md`)

*   **Internal**: Watch the Motor's state (or receive progress updates).
*   **Send**: `{:floor_arrival, floor}` back to the **original Controller.**

## 4. Testing

*   Implement `test/sensor_test.exs`.
*   Verify that the sensor correctly detects the elevator passing F1, F2, and F3 during a transit.
*   Verify the timing integrity (Should not signal F3 before the Motor has had time to travel).

## 5. Completion Signal (MANDATORY)

When your mission is 100% complete and tests are GREEN:

1.  Use (**and create if necessary**) the directory: `handover_status/`
2.  Create the file: `handover_status/DONE_SENSOR`.
3.  Write your **Absolute Worktree Path** and a 1-sentence summary inside.

## 6. Supervisor Authority

The **Final Supervisor (Antigravity Original)** will audit your code against the 'Code as a Story' design principles. 🚀🏾
