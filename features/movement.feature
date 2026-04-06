Feature: Elevator Movement
  As an elevator system
  I want to travel between floors efficiently
  To serve passenger requests while following the LOOK algorithm

  @S-MOVE-WAKEUP @R-MOVE-WAKEUP @R-CORE-STATE
  Scenario Outline: Wake up from idle state
    Given the elevator is idle at floor <current>
    When a request is received for floor <target>
    Then the elevator should start moving <heading>
    And the floor <target> should be in the pending requests

    Examples:
      | current | target | heading |
      | 0       | 3      | up      |
      | 5       | 1      | down    |

  @S-MOVE-BRAKING @R-SAFE-ARRIVAL
  Scenario: Arrival at target floor
    Given the elevator is moving up towards floor 3
    And a request for floor 3 is active
    When the sensor confirms arrival at floor 3
    Then the elevator should begin to stop
    And a stop command should be sent to the motor
    And the request for floor 3 should still be pending

  @S-MOVE-OPENING @R-SAFE-ARRIVAL
  Scenario: Doors start opening after motor stops
    Given the elevator is stopping at a floor
    And a request for the current floor is pending
    When the motor confirms it has stopped
    Then the elevator should begin opening the doors
    And the request for the current floor should be fulfilled

  @S-MOVE-DOCKED @R-CORE-STATE @R-SAFE-TIMEOUT
  Scenario: Doors are fully open
    Given the elevator doors are opening
    When the door confirms it has fully opened
    Then the elevator should be docked at the floor
    And the doors should be set to close automatically after 5 seconds

  @S-MOVE-BASE @R-MOVE-BASE
  Scenario: Return to base after inactivity
    Given the elevator is idle with no pending requests
    When 5 minutes pass without any activity
    Then a request for the ground floor should be automatically added
    And the elevator should return to the ground floor

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
