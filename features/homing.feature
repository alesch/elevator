Feature: Elevator Homing & Recovery
  As an elevator system
  I want to safely re-home the elevator after a reboot or crash
  To ensure the system starts with a verified physical position

  @S-HOME-COLD @R-HOME-STRATEGY
  Scenario: Cold Start (No Persistence)
    Given the Elevator Vault is empty
    When the system starts
    Then the "phase" is ":rehoming"
    And "heading" is ":down"
    And "motor_speed" is ":crawling"
    And "current_floor" is ":unknown"

  @S-HOME-ZERO @R-HOME-STRATEGY
  Scenario: Mid-Floor Recovery (Zero-Move)
    Given the Elevator Vault stores "Floor 3"
    And the Elevator Sensor is currently at "Floor 3"
    When the system reboots
    Then the "phase" is ":idle"
    And no motor movement should be triggered

  @S-HOME-MOVE @R-HOME-STRATEGY
  Scenario: Recovery between floors (Move-to-Physical)
    Given the Elevator Vault stores "Floor 3"
    And the Elevator Sensor is ":unknown" or mismatches
    When the system reboots
    Then the "phase" is ":rehoming"
    And "heading" is ":down"
    And "motor_speed" is ":crawling"
    And the elevator should move until the first physical sensor confirms arrival

  @S-HOME-ANCHOR @R-HOME-STRATEGY @R-HOME-VAULT
  Scenario: Homing Completion (Anchoring)
    Given the "phase" is ":rehoming"
    When the Core receives its very first ":floor_arrival" event
    Then the "heading" is ":idle"
    And "motor_status" is ":stopping"
    And "door_status" is ":closed"
    And the Vault is updated with the current floor

  @S-HOME-NO-DOOR @R-HOME-STRATEGY
  Scenario: No Door Cycle on Homing Arrival
    Given the "phase" is ":rehoming"
    And "door_status" is ":closed"
    And the Core receives its very first ":floor_arrival" event
    When the ":motor_stopped" confirmation is received after homing arrival
    Then the "phase" is ":idle"
    And "door_status" is ":closed"
    And no ":open_door" command is issued

  @S-HOME-BLOCK-REQ @R-HOME-STRATEGY
  Scenario: Request Blocking during Rehoming
    Given the elevator is in "phase: :rehoming"
    When any floor request is received
    Then the request should be ignored and NOT added to the queue
