Feature: System End-to-End Behaviour
  As the elevator system
  I want to service passenger requests in order and return to base when idle
  So that the full hardware-to-logic stack is verified as a unit

  @S-SYS-E2E-FULL-TRIP
  Scenario: System services two floor requests then docks at base after inactivity
    Given the system is docked at floor 0
    When a car request for floor 5 is received
    And a car request for floor 3 is received
    Then the elevator docks at floor 3
    And the elevator docks at floor 5
    And the elevator becomes idle at floor 5
    And the elevator docks at floor 0
