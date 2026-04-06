@skip
Feature: Elevator Booting & Synchronization
  As an elevator system
  I want to remain inert during the initial booting phase
  To ensure no physical movement occurs until hardware positions are verified

  @S-BOOT-GATED
  Scenario: Logical Gating during Boot
    Given the elevator has just powered on
    Then the "phase" should be ":booting"
    And the "motor_status" should be ":stopped"
    When any floor request or arrival is received
    Then the logical state machine should NOT transition
    And no hardware commands should be issued

  @S-BOOT-RECOVERY
  Scenario: Transition to Idle on Recovery
    Given the "phase" is ":booting"
    When the system confirms "vault_floor == sensor_floor"
    Then the "phase" should transition to ":idle"
    And "current_floor" should be updated to the verified floor

  @S-BOOT-REHOMING
  Scenario: Transition to Rehoming on Mismatch
    Given the "phase" is ":booting"
    When the system detects a floor mismatch or cold start
    Then the "phase" should transition to ":rehoming"
    And "heading" should be ":down"
    And "motor_speed" should be ":crawling"
