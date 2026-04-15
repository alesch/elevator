Feature: Manual Door Control
  As a passenger
  I want to manually control the elevator doors
  To ensure safe boarding or to reduce wait time

  @S-MANUAL-OPEN-WIN @R-SAFE-MANUAL
  Scenario: Door Open Button Wins over ongoing closing
    Given the core is in phase docked at floor 3
    When the door timeout is received
    Then the door begins closing
    When the button door-open is pressed
    Then the door begins opening

  @S-MANUAL-CLOSE @R-SAFE-MANUAL
  Scenario: Manual Close Button Overrides timer
    Given the core is in phase docked at floor 3
    And a car request for floor 0 is received
    When the button door-close is pressed
    Then the door begins closing

  @S-MANUAL-EXTEND @R-SAFE-MANUAL
  Scenario: Activity Extension (Open Button)
    Given the core is in phase docked at floor 3
    When the button door-open is pressed
    Then the door timeout timer is set
