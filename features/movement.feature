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

  @S-MOVE-SWEEP-CAR @R-MOVE-SWEEP
  Scenario: Stop for car request on the way
    Given the elevator is at the ground floor
    And it is moving up to serve a request at floor 5
    When a passenger inside the car selects floor 3
    And the elevator arrives at floor 3
    Then the elevator should stop at floor 3

  @S-MOVE-SWEEP-HALL @R-MOVE-SWEEP
  Scenario: Defer hall request to the return journey
    Given the elevator is at the ground floor
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

  @S-MOVE-MULTI-CAR @R-MOVE-SWEEP
  Scenario: Multiple car requests are served in order on the way up
    Given the elevator is idle at the ground floor
    And passengers inside the car select floors 2, 4, and 5
    When the elevator travels upward
    Then it should stop at floors: 2, 4, 5

  @S-MOVE-MULTI-HALL @R-MOVE-SWEEP
  Scenario: Multiple hall requests are deferred to the return journey
    Given the elevator is idle at the ground floor
    And hall requests are received for floors 2, 4, and 5
    When the elevator travels to the highest floor at floor 5
    Then it should stop at floors: 5, 4, 2

