@skip
Feature: Elevator System Behavior
  As an elevator system
  I want to handle actor redundancy and message spam
  To maintain a reliable audit trail and high performance

  @S-SYS-REDUNDANT @R-CORE-PURE
  Scenario: Actor Redundancy (Loud Warnings)
    Given the system motor is already in status ":stopped"
    When a redundant internal command to transition to ":stopped" is received
    Then a "Logger.warning" should be logged for the audit trail
    And the hardware timer should NOT be re-triggered

  @S-REQ-SPAM @R-REQ-TAGS
  Scenario: Button Spamming (Silent Idempotency)
    Given the "requests" list already contains a request for Floor 3
    When an additional external request for Floor 3 is received
    Then the system should ignore it SILENTLY
    And no warnings should be logged

  @S-SYS-PUBSUB @R-CORE-SHELL
  Scenario: Observable State Change (Broadcasting)
    Given any change occurs in the Elevator Core state
    When the Controller processes the change
    Then the new state should be broadcast over PubSub
    And the topic should be "elevator:status"

  @S-REQ-CONCURRENCY @R-REQ-TAGS
  Scenario: Concurrent Requests (Race Condition Safety)
    Given the elevator is ":idle"
    When multiple hall requests for different floors arrive simultaneously
    Then all requests should be recorded exactly once in the "requests" queue
    And no requests should be dropped or duplicated
