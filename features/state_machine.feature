@skip
Feature: Elevator State Machine
  As an elevator system
  I want to transition between operational phases explicitly
  To ensure logic is predictable and deadlock-free

  @S-PHASE-IDLE-MOVE @R-CORE-STATE
  Scenario: :idle → :moving
    Given the elevator is ":idle" and doors are ":closed"
    When a request for a different floor is received
    Then the "phase" should become ":moving"
    And "motor_status" should become ":running"

  @S-PHASE-MOVE-ARRIVE @R-CORE-STATE
  Scenario: :moving → :arriving
    Given the elevator is in "phase: :moving"
    And "heading" is ":up"
    And a request exists for Floor 3
    When the elevator arrives at floor 3
    Then the "phase" should become ":arriving"
    And "motor_status" should become ":stopping"

  @S-PHASE-ARRIVE-DOCK @R-CORE-STATE
  Scenario: :arriving → :docked
    Given the elevator is in "phase: :arriving"
    And "motor_status" is ":stopped"
    And "door_status" is ":opening"
    When the ":door_opened" message is received
    Then the "phase" should become ":docked"
    And "door_status" should become ":open"
    And the door timeout timer should be set

  @S-PHASE-DOCK-LEAVE @R-CORE-STATE
  Scenario: :docked → :leaving
    Given the elevator is in "phase: :docked"
    And "door_status" is ":open"
    And "door_sensor" is ":clear"
    When the ":door_timeout" event is received
    Then the "phase" should become ":leaving"
    And "door_status" should become ":closing"

  @S-PHASE-LEAVE-MOVE @R-CORE-STATE @R-MOVE-SWEEP
  Scenario: :leaving → :moving
    Given the elevator is in "phase: :leaving"
    And pending work exists in the queue
    When the ":door_closed" message is received
    Then the "phase" should become ":moving"
    And "motor_status" should become ":running"

  @S-PHASE-LEAVE-IDLE @R-CORE-STATE @R-MOVE-IDLE
  Scenario: :leaving → :idle
    Given the elevator is in "phase: :leaving"
    And no pending requests remain
    When the ":door_closed" message is received
    Then the "phase" should become ":idle"
    And "motor_status" should stay ":stopped"

  @S-PHASE-LEAVE-ARRIVE @R-CORE-STATE @R-SAFE-OBSTRUCT
  Scenario: :leaving → :arriving (Obstruction Gateway)
    Given the elevator is in "phase: :leaving"
    And "door_status" is ":closing"
    When a ":door_obstructed" message is received
    Then the "phase" should become ":arriving"
    And "door_status" should become ":obstructed"
