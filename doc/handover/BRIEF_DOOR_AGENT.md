# Agent Brief: Elevator Door Specialist

## 1. Mission

Build the **`Elevator.Door`** GenServer. Its job is to handle the physical opening and closing cycle.

## 2. Constraints (Dumb Door Model)

*   **No Internal Timers**: You do NOT manage how long a door stays open. You simply listen for `:open` and `:close` commands from the Controller.
*   **Safety First**: The door MUST handle **`:door_obstructed`** sensor messages. If obstructed during closing, it must enter a stable **`:obstructed`** state and report back to the Controller.
*   **Five-State Machine**: `:opening`, `:open`, `:closing`, `:closed`, **`:obstructed`**.

## 3. The Contract (See `doc/PROTOCOL_SPEC.md`)

*   **Receive**: `:open` (Cast).
*   **Receive**: `:close` (Cast).
*   **Send**: `:door_opened` (When fully open).
*   **Send**: `:door_closed` (When fully locked).
*   **Send**: `:door_obstructed` (Safety alert).

## 4. Testing

*   Implement `test/door_test.exs`.
*   Verify the auto-reopen logic when blocked during closing.
*   Verify the 1:1 sync with the **`PROTOCOL_SPEC.md`**.

## 5. Completion Signal (MANDATORY)

When your mission is 100% complete and tests are GREEN:

1.  Use (**and create if necessary**) the directory: `handover_status/`
2.  Create the file: `handover_status/DONE_DOOR`.
3.  Write your **Absolute Worktree Path** and a 1-sentence summary inside.

## 6. Supervisor Authority

The **Final Supervisor (Antigravity Original)** will audit your code against the 'Code as a Story' design principles. 🚀🏾
