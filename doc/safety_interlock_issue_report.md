# Issue Report: Hardware Safety Interlock (The Golden Rule)

## 1. Problem Description
We have a critical safety race condition in the `Elevator.Controller`. When a floor request is received, the system simultaneously commands the motor to start moving and the doors to start closing. 

**Observed Safety Violation:**
High-fidelity telemetry logs show the motor spinning up (e.g., `Motor: [Action] Moving down...`) while the door is still in its `closing` phase. 

## 2. Technical Context
- **Requirement**: The Motor MUST stay `:stopped` whenever the doors are not in the `:closed` state.
- **Fidelity Proof**: This issue was discovered after unifying telemetry across the hardware actors, revealing that the controller was dispatching asynchronous commands too aggressively in `sync_physical_limbs/1`.

## 3. Current State (Rollback)
The previous implementation (a guard in `ensure_motor_status`) was rejected and has been **rolled back**. However, the **Test** and **Scenario Documentation** have been retained to define the successful outcome.

## 4. How to Reproduce
Run the dedicated safety check:
```bash
mix test test/controller_test.exs:263
```

**Expected Failure**:
The test fails on the following assertion:
```elixir
assert_receive {:elevator_state, %{door_status: :closing, motor_status: :stopped}}
```
Instead of staying `:stopped`, the motor transitions to `:running` immediately.

## 5. Next Steps for Agents
- Propose a more robust architectural solution (e.g., using a state-machine wrapper or explicit event-ordering) to solve this race.
- Ensure that the motor only wakes up after the `:door_closed` event is received in `handle_info/2`.
- Do NOT simply add a guard that drops the request silently, as this may lead to stalled elevators if the door is already closed.
