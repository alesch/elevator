# Elevator States & Transitions Ledger

This document is the **Single Source of Truth** for all operational phases and state transitions of the Elevator.

## Operational Phases

| Phase | Description | Motor | Door |
| :--- | :--- | :--- | :--- |
| **`:booting`** | Initial synchronization; waiting for hardware discovery. External requests are ignored. | `:stopped` | `:closed` |
| **`:idle`** | At floor, stationary, no active work. | `:stopped` | `:closed` |
| **`:rehoming`** | Recovering position by moving down slowly to Ground Floor (F0). | `:crawling` | `:closed` |
| **`:moving`** | Traveling toward a target floor at normal speed. | `:running` | `:closed` |
| **`:arriving`** | Target reached: motor is braking. Waiting for confirmation of stop. | **`:stopping`** | `:closed` |
| **`:opening`** | Motor stopped; issuing `{:open_door}`. Waiting for door sensor. | `:stopped` | **`:opening`** |
| **`:docked`** | At floor, doors confirmed open, serving passengers. | `:stopped` | `:open` |
| **`:closing`** | Service complete: doors are confirmed closing. | `:stopped` | **`:closing`** |

---

## The Transition Ledger (SECA)

Formal definition of state changes based on **State, Event, Condition, and Action**.

| Current State | Event (Trigger) | Condition | Action (Effect) | Next State |
| :--- | :--- | :--- | :--- | :--- |
| **`:booting`** | `:startup_check` | `vault == sensor` | None | **`:idle`** |
| **`:booting`** | `:startup_check` | `vault != sensor` | `{:crawl, :down}` | **`:rehoming`** |
| **`:rehoming`** | `:floor_arrival` | `floor == 0` | `{:stop_motor}` | **`:arriving`** |
| **`:idle`** | `:request_floor` | `target == current` | `{:open_door}` | **`:opening`** |
| **`:idle`** | `:request_floor` | `target != current` | `{:move, dir}` | **`:moving`** |
| **`:idle`** | `:inactivity_timeout` | `floor != 0` | Request Floor 0 | **`:moving`** |
| **`:moving`** | `:floor_arrival` | `floor == target` | `{:stop_motor}` | **`:arriving`** |
| **`:arriving`** | **`:motor_stopped`** | None | `{:open_door}` | **`:opening`** |
| **`:opening`** | **`:door_opened`** | None | `{:set_timer, :door_timeout}` | **`:docked`** |
| **`:docked`** | `:door_timeout` | None | `{:close_door}` | **`:closing`** |
| **`:docked`** | `:door_close` | None | `{:close_door}` | **`:closing`** |
| **`:closing`** | **`:door_closed`** | `requests.empty?` | None | **`:idle`** |
| **`:closing`** | **`:door_closed`** | `not requests.empty?` | `{:move, dir}` | **`:moving`** |
| **`:closing`** | `:door_obstructed` | None | `{:open_door}` | **`:opening`** |

---

## Hardware Feedback Ledger

The following events update the system's "Reality" but might trigger an immediate phase transition.

| Event | Logic Effect |
| :--- | :--- |
| **`:motor_running`** | Updates `hardware.motor_status` to `:running`. |
| **`:motor_crawling`** | Updates `hardware.motor_status` to `:crawling`. |
| **`:door_opening`** | Updates `hardware.door_status` to `:opening`. |
| **`:door_closing`** | Updates `hardware.door_status` to `:closing`. |
| **`:door_cleared`** | Updates `hardware.door_sensor` to `:clear`. |

---

## Startup Flow (:startup_check)

The transition from `:booting` is managed by the "Smart Homing" sequence:

1. **Comparison**: The Controller provides both the `Vault` floor (persisted) and the `Hardware.Sensor` floor.
2. **Logic**:
    - If they match (and are not `:unknown`), the Brain determines it is a safe recovery and signals `:recovery_complete`.
    - If they mismatch or are `:unknown`, the Brain triggers `:rehoming_started`.
