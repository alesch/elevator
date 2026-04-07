Feature: Elevator Movement Wakeup
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
