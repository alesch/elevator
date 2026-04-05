Feature: Elevator Movement
  As an elevator system
  I want to travel between floors efficiently
  To serve passenger requests while following the LOOK algorithm

  @S-MOVE-WAKEUP @R-MOVE-WAKEUP @R-CORE-STATE
  Scenario Outline: Context-Aware Wake Up (Request from IDLE)
    Given the elevator is ":idle" and doors are ":closed" at floor <current>
    When a request for floor <target> is received
    Then the "requests" queue should include the new request
    And the elevator "heading" should become "<heading>"
    And the "phase" should become ":moving"

    Examples:
      | current | target | heading |
      | 0       | 3      | :up     |
      | 5       | 1      | :down   |

  @S-MOVE-BRAKING @R-SAFE-ARRIVAL
  Scenario: Arrival at Target Floor (Braking)
    Given the elevator is in "phase: :moving" with "heading: :up"
    And "requests" includes "{:car, 3}"
    And the elevator is approaching floor 3
    When the sensor confirms arrival at floor 3
    Then the "phase" should become ":arriving"
    And "motor_status" should become ":stopping"
    And the motor should receive a ":stop_now" command
    And the request should remain in the queue until the motor physically stops

  @S-MOVE-OPENING @R-SAFE-ARRIVAL
  Scenario: Braking Complete (Door Opening)
    Given the elevator is in "phase: :arriving" with "motor_status: :stopping"
    And a request for the current floor is in the queue
    When the ":motor_stopped" confirmation is received
    Then the "phase" should remain ":arriving"
    And "motor_status" should become ":stopped"
    And "door_status" should become ":opening"
    And the door should receive an ":open" command
    And the request for the current floor should be removed from the queue

  @S-MOVE-DOCKED @R-CORE-STATE @R-SAFE-TIMEOUT
  Scenario: Door Open Confirmation
    Given the elevator is in "phase: :arriving" with "door_status: :opening"
    When the ":door_opened" confirmation is received
    Then the "phase" should become ":docked"
    And "door_status" should become ":open"
    And the auto-close timer should be armed for 5000ms

  @S-MOVE-BASE @R-MOVE-BASE
  Scenario: Return to Base (Inactivity Timeout)
    Given the elevator is in "phase: :idle" with no pending requests
    When 5 minutes (300s) pass without any activity
    Then a "{:car, 0}" request should be automatically added
    And the elevator should return to floor 0

  @S-MOVE-SWEEP-UP @R-MOVE-SWEEP
  Scenario: Pick-up on the Way (Sweep)
    Given the elevator is in "phase: :moving" with "heading: :up"
    And "requests" includes floor 5
    When a hall request for floor 3 is added
    And the sensor confirms arrival at floor 3
    Then the "phase" should become ":arriving"
    And "motor_status" should become ":stopping"

  @S-MOVE-REVERSE @R-MOVE-SWEEP
  Scenario: Reverse or Retire
    Given the elevator is in "phase: :arriving" at floor 3
    And the only request in the queue is "{:car, 3}"
    When the ":motor_stopped" confirmation is received
    Then the "heading" should remain ":up" until a new direction is chosen
    And if a new request arrives for floor 1, "heading" should become ":down"

  @S-MOVE-SAME-FLOOR @R-MOVE-WAKEUP
  Scenario: Same-Floor Interaction
    Given the elevator is in "phase: :idle" at floor 3 with doors ":closed"
    When a request for floor 3 is received
    Then the "phase" should become ":arriving"
    And the request should be immediately fulfilled
    And "motor_status" should remain ":stopped"
    And "door_status" should become ":opening"

  @S-MOVE-MULTI-STOP @R-MOVE-SWEEP
  Scenario: Multi-Stop Sweep Ordering
    Given the elevator is ":idle" at floor 0
    And car requests exist for floors 2, 4, and 6
    When the elevator moves upward through each floor
    Then stops should be made in ascending order: floor 2, then 4, then 6

  @S-MOVE-BOUNDARY @R-MOVE-SWEEP
  Scenario: Boundary Reversals
    Given the elevator is ":idle" at floor 5 (top floor)
    And "heading" is ":up"
    And there are no requests above floor 5
    When a same-floor request triggers a heading update
    Then the "heading" should become ":idle"
