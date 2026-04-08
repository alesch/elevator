@skip
Feature: Elevator Movement
  As an elevator system
  I want to travel between floors efficiently
  To serve passenger requests while following the LOOK algorithm

  @S-MOVE-WAKEUP @R-MOVE-WAKEUP @R-CORE-STATE
  Scenario Outline: Wake up from idle state
    Given the elevator is idle at floor <current>
    When a request for floor <target> is received
    Then the elevator should start moving <heading>
    And floor <target> should be in the pending requests

    Examples:
      | current | target | heading |
      | ground  |      3 | up      |
      |       5 |      1 | down    |

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
    Given the elevator is idle at floor 3
    And the doors are opening
    When the door confirms it has fully opened
    Then the elevator should be docked at floor 3
    And the doors should be set to close in 5 seconds

  @S-MOVE-BASE @R-MOVE-BASE
  Scenario: Return to base after inactivity
    Given the elevator is idle at floor 3
    When 5 minutes pass without any activity
    Then a request for floor ground should be added
    And the elevator should return to floor ground

  @S-MOVE-SWEEP-CAR @R-MOVE-LOOK
  Scenario: Stop for car request on the way
    Given the elevator is at floor ground
    And it is moving up to serve a request at floor 5
    When a passenger inside the car selects floor 3
    And the elevator arrives at floor 3
    Then the elevator should stop at floor 3

  @S-MOVE-SWEEP-HALL @R-MOVE-LOOK
  Scenario: Defer hall request to the return journey
    Given the elevator is at floor ground
    And it is moving up to serve a request at floor 5
    When a hall request is received for floor 3
    And the elevator passes floor 3
    Then the elevator should not stop at floor 3
    And it should continue towards floor 5

  @S-MOVE-SAME-FLOOR @R-MOVE-WAKEUP
  Scenario: Request on the current floor
    Given the elevator is idle at floor 3
    When a request for floor 3 is received
    Then the elevator should begin opening the doors
    And the request should be fulfilled without any motor movement

  @S-MOVE-MULTI-CAR @R-MOVE-LOOK
  Scenario: Multiple car requests are served in order on the way up
    Given the elevator is idle at floor ground
    And passengers inside the car select floors 2, 4, and 5
    When the elevator travels upward
    Then it should stop at floors: 2, 4, 5

  @S-MOVE-MULTI-HALL @R-MOVE-LOOK
  Scenario: Multiple hall requests are deferred to the return journey
    Given the elevator is idle at floor ground
    And hall requests are received for floors 2, 4, and 5
    When the elevator travels upward, passing floors 2 and 4 to reach floor 5
    Then it should stop at floors: 5, 4, 2

  @S-MOVE-OBSTRUCT @R-SAFE-OBSTRUCT
  Scenario: Door obstruction during closing sequence
    Given the elevator is idle at floor 3
    And the doors are closing
    When the door sensor detects an obstruction
    Then the elevator should begin opening the doors
