@skip
Feature: Elevator Homing & Recovery
  As an elevator system
  I want to safely re-home the elevator after a reboot or crash
  To ensure the system starts with a verified physical position

  @S-HOME-COLD @R-HOME-STRATEGY
  Scenario: Cold Start (No Persistence)
    Given the Elevator Vault is empty
    When the system starts
    Then the "phase" should be ":rehoming"
    And "heading" should be ":down"
    And "motor_speed" should be ":crawling"
    And "current_floor" should be ":unknown"

  @S-HOME-ZERO @R-HOME-STRATEGY
  Scenario: Mid-Floor Recovery (Zero-Move)
    Given the Elevator Vault stores "Floor 3"
    And the Elevator Sensor is currently at "Floor 3"
    When the system reboots
    Then the "phase" should transition ":rehoming" -> ":idle" immediately
    And no motor movement should be triggered

  @S-HOME-MOVE @R-HOME-STRATEGY
  Scenario: Recovery between floors (Move-to-Physical)
    Given the Elevator Vault stores "Floor 3"
    And the Elevator Sensor is ":unknown" or mismatches
    When the system reboots
    Then the "phase" should be ":rehoming"
    And "heading" should be ":down"
    And "motor_speed" should be ":crawling"
    And the elevator should move until the first physical sensor confirms arrival

  @S-HOME-ANCHOR @R-HOME-STRATEGY @R-HOME-VAULT
  Scenario: Homing Completion (Anchoring)
    Given the "phase" is ":rehoming"
    When the Core receives its very first ":floor_arrival" event
    Then the "heading" should immediately become ":idle"
    And "motor_status" should become ":stopping"
    And "door_status" should stay ":closed"
    And the Vault should be updated with the current floor

  @S-HOME-NO-DOOR @R-HOME-STRATEGY
  Scenario: No Door Cycle on Homing Arrival
    Given the "phase" is ":rehoming"
    And "door_status" is ":closed"
    When the ":motor_stopped" confirmation is received after homing arrival
    Then the "phase" should transition to ":idle"
    And "door_status" should remain ":closed"
    And no ":open_door" command should be issued

  @S-HOME-BLOCK-REQ @R-HOME-STRATEGY
  Scenario: Request Blocking during Rehoming
    Given the elevator is in "phase: :rehoming"
    When any floor request is received
    Then the request should be ignored and NOT added to the queue
