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
