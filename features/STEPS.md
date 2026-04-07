# Elevator BDD - Step Glossary

This document serves as the "Source of Truth" for all Gherkin steps implemented in the Elevator project. Use these patterns when writing new `.feature` files.

> [!TIP]
> Patterns support optional words like "the", "elevator", and "should" to make scenarios more readable.
> Most patterns are implemented in `test/support/common_steps.ex`.

## Given (Context)

| Pattern | Description | Example |
| :--- | :--- | :--- |
| `the elevator is "{status}" and doors are "{status}" at floor {n}` | Sets initial heading, doors, and floor. | `Given the elevator is ":idle" and doors are ":closed" at floor 0` |
| `the elevator is at floor {n} and is "{status}"` | Sets floor and phase/heading. | `Given the elevator is at floor 0 and is ":docked"` |
| `doors are "{status}"` | Sets door status specifically. | `And the doors are ":open"` |
| `is in "{field1}" with "{field2}"` | Sets two state fields. | `Given the elevator is in "phase: :moving" with "heading: :up"` |
| `is in "{f1}" with "{f2}" and "{f3}" is "{v3}"` | Sets three state fields (Safety). | `Given the elevator is in "phase: :docked" with "door_status: :open" and "door_sensor" is ":clear"` |
| `is in "{field}"` | Sets a single state field. | `Given the elevator is in "phase: :moving"` |
| `"{field}" is "{value}"` | Generic field assignment. | `Given "door_sensor" is ":blocked"` |
| `"{field}" includes {value}` | Adds to a list (requests). | `Given "requests" includes floor 5` |
| `the only request in the queue is "{value}"` | Sets exact request list. | `Given the only request in the queue is "{:car, 3}"` |
| `approaching floor {n}` | Moves current_floor near target. | `Given the elevator is approaching floor 3` |
| `is idle at floor {n}` | Sets phase to :idle and current_floor to n. | `Given the elevator is idle at floor 0` |

## When (Actions/Events)

| Pattern | Description | Example |
| :--- | :--- | :--- |
| `(new )?request for floor {n} is received` | Triggers a floor request event. | `When a new request for floor 5 is received` |
| `(a\|the) "{event}" message is received` | Triggers a general core event. | `When the ":door_closed" message is received` |
| `sensor confirms arrival at floor {n}` | Simulates floor sensor trigger. | `When the sensor confirms arrival at floor 3` |
| `{n} seconds pass without activity ("{event}" event)` | Simulates inactivity timeout. | `When 5 seconds pass without activity (":door_timeout" event)` |

## Then (Assertions)

| Pattern | Description | Example |
| :--- | :--- | :--- |
| `"{field}" (becomes?\|reverts? to\|stays?\|transitions? back to) "{value}"` | Verifies a state field value. | `Then "phase" becomes ":moving"` |
| `"{field}" should (become\|revert to\|stay) "{value}"` | Formal state transition check. | `Then "phase" should become ":moving"` |
| `the actions should be "{action}"` | Verifies expected outcome list. | `Then the actions should be "{:close_door}"` |
| `motor MUST stay "{status}" while...` | Safety invariant check. | `Then the motor MUST stay ":stopped" while...` |
| `should return to floor {n}` | Verifies return to base behavior. | `Then the elevator should return to floor 0` |
| `should start moving {heading}` | Verifies phase transition to :moving with heading. | `Then the elevator should start moving up` |
| `floor {n} should be in the pending requests` | Asserts floor n is in the request queue. | `And floor 5 should be in the pending requests` |
