# Messaging Protocol Specification (V1)

This document defines the **Internal Messaging Interface** for the Elevator Actor Network. All agents MUST implement these specific message patterns for interoperability.

## 1. Controller ↔ Motor (The "Muscle")

| Direction | Message | Type | Description |
| :--- | :--- | :--- | :--- |
| C → M | `{:move_to, floor}` | `cast` | Command motor to start moving toward a floor. |
| C → M | `:stop_now` | `cast` | Emergency/Immediate brake. |

## 2. Controller ↔ Sensor (The "Nerves")

| Direction | Message | Type | Description |
| :--- | :--- | :--- | :--- |
| S → C | `{:floor_arrival, floor}` | `info` | [CRITICAL] Sensor notifies that the box has precisely reached a floor. |
| S → C | `{:floor_passing, floor}` | `info` | [OPTIONAL] Sensor notifies when the box is passing a floor. |

## 3. Controller ↔ Door (The "Safety")

| Direction | Message | Type | Description |
| :--- | :--- | :--- | :--- |
| C → D | `:open` | `cast` | Command door to start opening. |
| C → D | `:close` | `cast` | Command door to start closing. |
| D → C | `:door_opened` | `info` | Door notifies that it is fully open. |
| D → C | `:door_closed` | `info` | Door notifies that it is fully locked. |
| D → C | `:door_obstructed` | `info` | [CRITICAL] Door entered the OBSTRUCTED state (Safety lock). |

## 4. Supervision Structure

The **Supervisor** will manage the following child specs:

1. `Elevator.Controller`
2. `Elevator.Motor`
3. `Elevator.Sensor`
4. `Elevator.Door`

**Restart Strategy**: `:one_for_all` (If the Brain dies, the Limbs must die. If a Limb dies, the Brain needs a clean reset).

## 5. Handover Orchestration (Completion Signal)

When an agent completes their mission, they MUST:
1. Use (and create if necessary) the directory: `handover_status/`
2. Create a file: `handover_status/DONE_[ROLE]` (e.g., `DONE_MOTOR`).
3. Write the **Absolute Worktree Path** inside that file so the Supervisor can locate the work.
