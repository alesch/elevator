# Elixir Elevator Learning Plan

This plan is designed to explore Elixir's core concepts through the modeling of an elevator system. We will proceed iteratively, focusing on one concept at a time.

## Proposed Learning Path

### Phase 0: Conceptual State Machine (Current Focus)

Before writing any Elixir, we'll map out the state machine.

- Define the **inputs**: Floor buttons (external), Elevator buttons (internal), Sensors (door, floor arrival).
- Define the **states**: `IDLE`, `MOVING_UP`, `MOVING_DOWN`, `DOOR_OPENING`, `DOOR_OPEN`, `DOOR_CLOSING`.
- Define the **transitions**: What triggers a move from `IDLE` to `MOVING_UP`? What happens if a door sensor detects an obstruction?

### Phase 1: Pure Logic with Elixir Structs

We'll start by defining the "shape" of our data.

- **Goal**: Model a `%{floor: 1, direction: :up}` state using Elixir Structs.
- **Learning Point**: Immutability and Pattern Matching.
- **TDD**: Write simple assertions for state updates (e.g., `move_up(state)` returns a new state).

### Phase 2: Project Architecture & ExUnit

Only once Phase 1 is clear, we will initialize the `mix` project.

- **Goal**: Set up the project structure.
- **Learning Point**: Mix, dependencies, and the `ExUnit` testing framework.

### Phase 3: Concurrency & GenServers

Introducing the "actor model".

- **Goal**: Separate the Motor, Door, and Controller into independent processes.
- **Learning Point**: How processes communicate, holding state in a `GenServer`, and basic message passing (`handle_call`, `handle_cast`).

### Phase 4: Fault Tolerance (Hardware Failures)

Simulating the "real world".

- **Goal**: Inject failures (e.g., a "sensor" process crashes).
- **Learning Point**: Supervision Trees and the "Let it Crash" philosophy.

### Phase 5: Rich UI with Phoenix LiveView

Visualization.

- **Goal**: Build a premium web dashboard.
- **Learning Point**: LiveView's real-time capabilities and modern CSS animations.

## Open Questions

- Does this "conceptual-first" breakdown align with the pace you're looking for?
- Would you like to start by defining the specific rules for our state machine (e.g., "Door cannot open while moving")?

## Verification Plan

1. **Conceptual**: Review and approve the state transition diagram.
2. **Logic**: Run `mix test` for unit tests of pure functions.
3. **Concurrency**: Observe process restarts in the Elixir observer.
4. **UI**: Manual interaction with the web dashboard.
