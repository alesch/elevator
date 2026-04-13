# BDD Traceability Matrix

This table maps every Business Rule defined in [`doc/core_rules.md`](core_rules.md) to the Scenarios in the **[`features/`](../features/)** directory that validate it.

| Rule ID | Rule Name | Validating Scenarios |
| :--- | :--- | :--- |
| **[R-CORE-PURE]** | Pure Logic Core | `[S-SYS-REDUNDANT]` |
| **[R-CORE-SHELL]** | Imperative Shell | `[S-SYS-PUBSUB]`, `[S-UI-JOURNEY]` |
| **[R-CORE-STATE]** | Explicit Phase State Machine | `[S-MOVE-WAKEUP]`, `[S-MOVE-DOCKED]`, `[S-MOVE-CLOSING]`, `[S-PHASE-IDLE-MOVE]`, `[S-PHASE-MOVE-ARRIVE]`, `[S-PHASE-ARRIVE-DOCK]`, `[S-PHASE-DOCK-LEAVE]`, `[S-PHASE-LEAVE-MOVE]`, `[S-PHASE-LEAVE-IDLE]`, `[S-PHASE-LEAVE-DOCK]` |
| **[R-BOOT-GUARD]** | Boot Blocking | `[S-BOOT-BLOCK-REQ]` |
| **[R-MOVE-INTENT]** | Intent vs. Action | (Implicitly covered by all Movement scenarios) |
| **[R-MOVE-LOOK]** | The Four Rules of LOOK | `[S-MOVE-LOOK-UP]`, `[S-MOVE-LOOK-DOWN]`, `[S-MOVE-LOOK-CAR]`, `[S-MOVE-LOOK-HALL-DEFER]`, `[S-MOVE-LOOK-SERVICE]`, `[S-MOVE-LOOK-NEXT]`, `[S-MOVE-SWEEP-CAR]`, `[S-MOVE-SWEEP-HALL]`, `[S-MOVE-MULTI-CAR]`, `[S-MOVE-MULTI-HALL]`, `[S-PHASE-LEAVE-MOVE]`, `[S-PHASE-LEAVE-IDLE]`, `[S-MOVE-LOOK-UNKNOWN]`, `[S-MOVE-HEADING-MAINTENANCE]`, `[S-MOVE-LOOK-IDLE]`, `[S-MOVE-LOOK-PRIORITY]` |
| **[R-MOVE-BASE]** | Return to Base | `[S-MOVE-BASE]` |
| **[R-SAFE-GOLDEN]** | The Golden Rule (Structural Safety) | `[S-SAFE-GOLDEN]` |
| **[R-SAFE-ARRIVAL]** | Asynchronous Arrival Protocol | `[S-MOVE-BRAKING]`, `[S-MOVE-OPENING]`, `[S-SAFE-SERVICE-DELAY]` |
| **[R-SAFE-TIMEOUT]** | Automatic Door Closing (Timer) | `[S-MOVE-DOCKED]`, `[S-SAFE-TIMEOUT]` |
| **[R-SAFE-MANUAL]** | Manual Door Override | `[S-MANUAL-OPEN-IDLE]`, `[S-MANUAL-OPEN-WIN]`, `[S-MANUAL-RESET-TIMER]`, `[S-MANUAL-CLOSE]`, `[S-MANUAL-EXTEND]` |
| **[R-SAFE-OBSTRUCT]** | Door Obstruction | `[S-MOVE-OBSTRUCT]`, `[S-SAFE-OBSTRUCT]`, `[S-SAFE-CLEARED]`, `[S-PHASE-LEAVE-DOCK]` |
| **[R-HOME-VAULT]** | State Persistence (Vault Backup) | `[S-HOME-ANCHOR]` |
| **[R-HOME-STRATEGY]** | Homing Procedure (Power-On Safety) | `[S-HOME-COLD]`, `[S-HOME-ZERO]`, `[S-HOME-MOVE]`, `[S-HOME-ANCHOR]`, `[S-HOME-NO-DOOR]`, `[S-HOME-BLOCK-REQ]`, `[S-MOVE-LOOK-UNKNOWN]`, `[S-HOME-HEADING-STABILITY]` |
| **[R-HW-MOTOR]** | Motor Protocols | `[S-HW-MOTOR]` |
| **[R-HW-DOOR]** | Door Protocols | `[S-HW-DOOR]` |
| **[R-HW-SENSOR]** | Sensor Protocols | `[S-HW-SENSOR]` |
