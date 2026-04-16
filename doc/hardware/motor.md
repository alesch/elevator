# Hardware Motor

The Elevator Motor is a "dumb" actuator. It executes direction and speed commands, publishes its status to the message bus, and waits for World to confirm when braking is complete. It owns no timers — physical timing is delegated entirely to `Elevator.World`.

## The Transition Ledger (SECA)

Formal definition of state changes based on **State, Event, Condition, and Action**.

| Current State | Event (Trigger) | Condition | Action (Effect) | Next State |
| :--- | :--- | :--- | :--- | :--- |
| **`:stopped`** | `{:move, dir}` | None | `broadcast {:motor_running, dir}` | **`:running`** |
| **`:stopped`** | `{:crawl, dir}` | None | `broadcast {:motor_crawling, dir}` | **`:crawling`** |
| **`:running`** | `:stop_now` | None | `broadcast :motor_stopping` | **`:stopping`** |
| **`:crawling`** | `:stop_now` | None | `broadcast :motor_stopping` | **`:stopping`** |
| **`:stopping`** | `:motor_stopped` | World confirmed | — | **`:stopped`** |
| **`any active`** | `{:move, dir}` | None | `broadcast {:motor_running, dir}` | **`:running`** |
| **`any active`** | `{:crawl, dir}` | None | `broadcast {:motor_crawling, dir}` | **`:crawling`** |
| **`:stopped`** | `:stop_now` | None | (redundant, ignored) | **`:stopped`** |
| **`:stopping`** | `:stop_now` | None | (redundant, ignored) | **`:stopping`** |

All broadcasts go to the `"elevator:hardware"` channel. `World` and `Controller` subscribe to this channel and act on the events independently.

## Public API

The motor process is managed via a GenServer and supports the following commands:

- `move(pid, direction)`: Transitions from `:stopped` to **`:running`**.
- `crawl(pid, direction)`: Transitions from `:stopped` to **`:crawling`**.
- `stop(pid)`: Transitions from `:running` or `:crawling` to **`:stopping`**.

## Timing Ownership

Motor owns no timers. Physical durations are defined and enforced exclusively by `Elevator.World`:

- **Running speed**: 6 ticks × 250ms = **1,500ms** per floor
- **Crawling speed**: 18 ticks × 250ms = **4,500ms** per floor
- **Braking**: 2 ticks × 250ms = **500ms**

When braking is complete, World sends `:motor_stopped` directly to Motor via registry. Motor transitions to `:stopped` and clears its direction.

## Assumptions & Safety

1. **Stateless physics**: Motor declares intent (running, crawling, stopping) but does not simulate movement. All position and timing logic lives in World.
2. **Golden Rule**: A new move/crawl command while in motion is accepted immediately — Motor broadcasts the new status and World resets its tick counters.
3. **Directional Blindness**: Motor does not know which floor it is on; it only knows its current `direction` (`:up` or `:down`).
