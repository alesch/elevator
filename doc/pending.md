# Pending Architectural Gaps

This document tracks identified discrepancies between the technical specifications and the current implementation.

## Missing: `:door_cleared` Signal

### Context
The [Elevator States & Transitions Ledger](file:///home/alex/dev/elevator/doc/states.md) and the [Controller](file:///home/alex/dev/elevator/lib/elevator/controller.ex#L224) reference a `:door_cleared` event. This event is intended to notify the system when a physical obstruction has been removed from the door's path.

### Current Status
- **Missing in Hardware**: [door.ex](file:///home/alex/dev/elevator/lib/elevator/hardware/door.ex) has no handler or simulation hook for clearing an obstruction.
- **Missing in State Logic**: Once the door enters the `:obstructed` state, it remains there until it receives an explicit `open/1` or `close/1` command. There is no automated "Safety Recovery" pulse.

### Proposed Solution
1. Add `simulate_clearance/1` to `Elevator.Hardware.Door` to emit the `:door_cleared` signal.
2. Update the `Core` and `Controller` to handle `:door_cleared` by potentially triggering an automatic retry of the last interrupted action.
