Feature: Elevator Movement
  As an elevator system
  I want to travel between floors efficiently
  To serve passenger requests while following the LOOK algorithm

  @S-MOVE-WAKEUP @R-MOVE-WAKEUP @R-CORE-STATE
  Scenario Outline: Wake up from idle state
    Given the elevator is idle at floor <current>
    When a request for floor <target> is received
    Then the motor_status is :running
    And the heading is <heading>
    And the phase is :moving
    And floor <target> is in the pending requests

    Examples:
      | current | target | heading |
      | ground  | 3      | up      |
      | 5       | 1      | down    |

  @S-MOVE-BRAKING @R-SAFE-ARRIVAL
  Scenario: Arrival at target floor
    Given the elevator is moving up towards floor 3
    And a request for floor 3 is active
    When the sensor confirms arrival at floor 3
    Then the phase is :arriving
    And motor_status is :stopping
    And the request for floor 3 is still pending

  @S-MOVE-OPENING @R-SAFE-ARRIVAL
  Scenario: Doors start opening after motor stops
    Given the elevator is stopping at floor 3
    And a request for floor 3 is pending
    When the motor confirms it has stopped
    Then the door_status is :opening
    And the request for floor 3 is fulfilled

  @S-MOVE-DOCKED @R-CORE-STATE @R-SAFE-TIMEOUT
  Scenario: Doors are fully open
    Given the elevator is idle at floor 3
    And the doors are opening
    When the door confirms it has fully opened
    Then the phase is :docked
    And current floor is 3
    And the door_status is :open
    And the door timeout timer is set for 5 seconds

  @S-MOVE-BASE @R-MOVE-BASE
  Scenario: Return to base after inactivity
    Given the elevator is idle at floor 3
    When 5 minutes pass without any activity
    Then floor ground is in the pending requests
    And the heading is :down
    And motor_status is :running

  @S-MOVE-SWEEP-CAR @R-MOVE-LOOK
  Scenario: Stop for car request on the way
    Given the elevator is at floor ground
    And it is moving up to serve a request at floor 5
    When a passenger inside the car selects floor 3
    And the elevator arrives at floor 3
    Then the phase is :arriving
    And motor_status is :stopping
    And the current floor is 3

  @S-MOVE-SWEEP-HALL @R-MOVE-LOOK
  Scenario: Defer hall request to the return journey
    Given the elevator is at floor ground
    And it is moving up to serve a request at floor 5
    When a hall request is received for floor 3
    And the elevator passes floor 3
    Then the phase is :moving
    And current floor is 3
    And floor 5 is in the pending requests
    And floor 3 is in the pending requests

  @S-MOVE-SAME-FLOOR @R-MOVE-WAKEUP
  Scenario: Request on the current floor
    Given the elevator is idle at floor 3
    When a request for floor 3 is received
    Then the door_status is :opening
    And the request is fulfilled without any motor movement

  @S-MOVE-MULTI-CAR @R-MOVE-LOOK
  Scenario: Multiple car requests are served in order on the way up
    Given the elevator is idle at floor ground
    And passengers inside the car select floors 2, 4, and 5
    When the elevator travels upward
    Then the phase is :docked
    And current floor is 5
    And the request for floor 4 is fulfilled
    And the request for floor 2 is fulfilled

  @S-MOVE-MULTI-HALL @R-MOVE-LOOK
  Scenario: Multiple hall requests are deferred to the return journey
    Given the elevator is idle at floor ground
    And hall requests are received for floors 2, 4, and 5
    When the elevator travels upward, passing floors 2 and 4 to reach floor 5
    Then the phase is :docked
    And current floor is 2
    And the request for floor 5 is fulfilled
    And the request for floor 4 is fulfilled

  @S-MOVE-OBSTRUCT @R-SAFE-OBSTRUCT
  Scenario: Door obstruction during closing sequence
    Given the elevator is idle at floor 3
    And the doors are closing
    When the door_sensor detects an obstruction
    Then the door_status is :opening

  @S-MOVE-HEADING-MAINTENANCE @R-MOVE-LOOK
  Scenario: Heading maintenance during arrival cycle
    Given the elevator is idle at floor 0
    When a request for floor 3 is received
    Then the heading is :up
    When the sensor confirms arrival at floor 3
    Then the phase is :arriving
    And the heading is :up
    When the motor confirms it has stopped
    And the door confirms it has fully opened
    Then the phase is :docked
    And the heading is :idle
