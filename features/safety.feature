@skip
Feature: Elevator Safety
  As an elevator system
  I want to maintain structural and operational safety
  To protect passengers and equipment
  #
  #
  # @S-SAFE-OBSTRUCT @R-SAFE-OBSTRUCT
  # Scenario: Door Obstruction
  #   Given the elevator is in phase: :leaving with door_status: :closing
  #   When a :door_obstructed message is received
  #   Then door_status becomes :obstructed
  #   And door_sensor becomes :blocked
  #   And phase becomes :arriving
  #   And the actions should include {:open_door}
  # @S-SAFE-CLEARED @R-SAFE-OBSTRUCT
  # Scenario: Door Sensor Cleared
  #   Given door_sensor is :blocked
  #   When a :door_cleared message is received
  #   Then door_sensor becomes :clear
  # @S-SAFE-SERVICE-DELAY @R-SAFE-ARRIVAL
