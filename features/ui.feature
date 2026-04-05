Feature: Elevator Dashboard UI
  As a passenger
  I want to interact with the elevator via the dashboard
  To reach my destination floor safely and see real-time status

  @S-UI-JOURNEY @R-CORE-SHELL
  Scenario: Full Journey from F0 to F3
    Given the dashboard is loaded and LiveView is connected
    And "phase" is ":idle" and "current_floor" is "0"
    When the user clicks the Floor 3 button on the dashboard
    Then the button label should show a "pending" or "targeting" status
    And the activity log should record "Controller: Floor 3"
    And the digital indicator should transition to "3" within 20s
    And the doors should open on arrival
    And the car visual should align correctly with Floor 3
