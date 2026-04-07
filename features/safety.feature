@skip
Feature: Elevator Safety
  As an elevator system
  I want to maintain structural and operational safety
  To protect passengers and equipment

  @S-SAFE-GOLDEN @R-SAFE-GOLDEN
  Scenario: Hardware Safety Interlock (The Golden Rule)
    Given the elevator is at floor 0 and is ":docked"
    When a request for floor 3 is received
    Then the motor MUST stay ":stopped" while the doors are ":opening", ":open", or ":closing"
    And the motor is ONLY commanded to ":move" after ":motor_stopped" and ":door_closed" signals are confirmed

  @S-SAFE-OBSTRUCT @R-SAFE-OBSTRUCT
  Scenario: Door Obstruction
    Given the elevator is in "phase: :leaving" with "door_status: :closing"
    When a ":door_obstructed" message is received
    Then "door_status" becomes ":obstructed"
    And "door_sensor" becomes ":blocked"
    And "phase" becomes ":arriving"
    And the actions should include "{:open_door}"

  @S-SAFE-CLEARED @R-SAFE-OBSTRUCT
  Scenario: Door Sensor Cleared
    Given "door_sensor" is ":blocked"
    When a ":door_cleared" message is received
    Then "door_sensor" becomes ":clear"

  @S-SAFE-TIMEOUT @R-SAFE-TIMEOUT
  Scenario Outline: Door Auto-Close Timeout (5s)
    Given the elevator is in "phase: :docked" with "door_status: :open" and "door_sensor" is "<sensor>"
    When 5 seconds pass without activity (":door_timeout" event)
    Then the actions should be "<action>"
    And "door_status" should become "<door_status>"
    And "phase" should become "<phase>"

    Examples:
      | sensor   | action        | door_status | phase    |
      | :clear   | {:close_door} | :closing    | :leaving |
      | :blocked | (No action)   | :open       | :docked  |

  @S-SAFE-SERVICE-DELAY @R-SAFE-ARRIVAL
  Scenario: Service Delay (Auto-Close Integration)
    Given the elevator is in "phase: :docked" at floor 1
    And the doors are ":open"
    When a new request for floor 5 is received
    Then the "heading" should become ":up"
    And the door should stay ":open" until the 5s timer fires
    And the movement should ONLY begin after the doors are confirmed ":closed"
