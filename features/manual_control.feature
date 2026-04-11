@skip
Feature: Manual Door Control
  As a passenger
  I want to manually control the elevator doors
  To ensure safe boarding or to reduce wait time

  @S-MANUAL-OPEN-IDLE @R-SAFE-MANUAL
  Scenario: Manual Door Open from Closed
    Given the elevator is in phase: :idle with door_status: :closed
    When the passenger presses the <|> (door open) button
    Then door_status should transition to :opening
    And the door should receive an :open command

  @S-MANUAL-OPEN-WIN @R-SAFE-MANUAL
  Scenario: Door Open Button Wins
    Given the elevator is in phase: :leaving with door_status: :closing
    When the passenger presses the <|> (door open) button
    Then the closing attempt should be discarded
    And door_status should transition back to :opening

  @S-MANUAL-RESET-TIMER @R-SAFE-MANUAL
  Scenario: Reset Auto-Close Timer
    Given the elevator is in phase: :docked with door_status: :open
    When the passenger presses the <|> (door open) button
    Then the last_activity_at timestamp should be updated
    And the auto-close timer should be restarted for 5000ms

  @S-MANUAL-CLOSE @R-SAFE-MANUAL
  Scenario: Manual Close Button Override
    Given the elevator is in phase: :docked with door_status: :open
    And pending requests exist in the queue
    When the passenger presses the >|< (door close) button
    Then door_status should become :closing immediately
    And the {:cancel_timer, :door_timeout} action should be emitted

  @S-MANUAL-EXTEND @R-SAFE-MANUAL
  Scenario: Activity Extension (Open Button)
    Given the elevator is in phase: :docked with door_status: :open
    When the passenger presses the <|> (door open) button
    Then the last_activity_at timestamp should be updated
    And the auto-close timer should be restarted (:set_timer, :door_timeout, 5000)
