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

---

## Broken: Persistence during Rehoming Arrival

### Context

When the elevator reaches its target floor during the `:rehoming` phase, it must persist its current position to the Vault (Rule **[R-HOME-VAULT]**).

### Broken: Persistence during Rehoming Arrival
- **Scenario**: `@S-HOME-ANCHOR`
- **Issue**: System reaches Floor 0 during rehoming, but fails to issue `{:persist_arrival}`.
- **Root Cause**: The differential `floor_reached?` check in `Core.ex` fails because the floor is updated in the Ingest stage BEFORE the pulse, making baseline/transition identical.

### Broken: Heading Maintenance after Docking
- **Scenario**: `@S-MOVE-HEADING-MAINTENANCE`
- **Issue**: Heading remains `:up` or `:down` after the door is confirmed fully open and the system is `:docked`, even if no more work exists.
- **Requirement**: Heading should become `:idle` immediately upon reaching the target floor/opening doors if the request queue is empty (Idle-Aggressive).

### Broken: Movement Phase Transition Lags
- **Scenario**: Multiple scenarios in `movement.feature`.
- **Issue**: System remains in `:moving` or `:arriving` when it should have transitioned to `:docked`.
- **Likely Cause**: Reality ingestion of motor/door events isn't correctly triggering the phase progression logic in all code paths.

### Proposed Solution

1. Update the `pulse/1` flow to pass the pre-ingestion state so `derive_actions` can compare against the truly "old" state.
2. OR: Explicitly issue the persistence action when handling the `:floor_arrival` event signal during rehoming.
