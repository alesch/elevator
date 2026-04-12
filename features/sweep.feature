Feature: Elevator Sweep Algorithm (LOOK)
  As the module controlling the movement of the elevator, named sweep
  I want an ordered queue of requests relative to my position
  So that I can travel efficiently using the LOOK algorithm

  #
  # Basics
  #

  Scenario: A new sweep has no requests and idle heading
    Given a new sweep
    Then the queue should be empty
    And the heading should be idle

  Scenario: Adding and servicing a request
    Given a new sweep
    When a car request for floor 3 is added
    Then the queue should be 3
    When floor 3 is serviced
    Then the queue should be empty
    And the heading should be idle

  Scenario: Calculating heading up
    Given a new sweep
    And the elevator is at floor 3
    When a car request for floor 5 is added
    Then the heading should be up

  Scenario: Calculating heading down
    Given a new sweep
    And the elevator is at floor 3
    When a car request for floor 1 is added
    Then the heading should be down

  Scenario: duplicates are ignored
    Given a new sweep
    And the elevator is at floor 0
    When car requests are added for floors 2, 3, 2, 5
    Then the queue should be 2, 3, 5

  Scenario: Ignore request for the current floor
    Given a new sweep
    And the elevator at floor 3
    When a hall request for floor 3 is added
    Then the next stop should be none
    And the heading should be idle
    When a car request for floor 3 is added
    Then the next stop should be none
    And the heading should be idle

  Scenario: Next stop follows the queue
    Given a new sweep
    And the elevator is at floor 0
    When car requests are added for floors 2, 5
    Then the next stop should be floor 2
    And the queue should be 2, 5
    When floor 2 is serviced
    Then the next stop should be floor 5
    And the queue should be empty

  Scenario: Requests persist until serviced
    Given a new sweep
    And the elevator is at floor 0
    When a car request for floor 3 is added
    When elevator is at floor 3
    Then the queue should be 3
    And the next stop should be 3
    And the heading should be up
    When floor 3 is serviced
    Then the queue should be empty
    And the next stop should be none
    And the heading should be idle

  @S-MOVE-LOOK-SERVICE
  Scenario: Servicing a floor removes all requests for that floor
    Given a new Sweep
    And a car request for floor 3 is added
    And a hall request for floor 3 is added
    When floor 3 is serviced
    Then there should be no requests for floor 3

  #
  # LOOK Algorithm
  #

  @S-MOVE-LOOK-UP
  Scenario: Upward sweep orders ahead-requests first
    Given a new sweep
    And the elevator is at floor 3
    When car requests are added for floors 5, 2, 4
    Then the queue should be 4, 5, 2

  @S-MOVE-LOOK-DOWN
  Scenario: Downward sweep orders ahead-requests first
    Given a new sweep
    And the elevator is at floor 3
    When car requests are added for floors 1, 5, 4
    Then the queue should be 1, 5, 4

  @S-MOVE-LOOK-CAR
  Scenario: Stopping for car requests on the way up
    Given a new sweep
    And the elevator is at floor 0
    And a car request for floor 5 is added
    When the elevator is at floor 2
    And a car request for floor 3 is added
    Then the next stop should be floor 3
    And the queue should be 3, 5

  @S-MOVE-LOOK-HALL-DEFER
  Scenario: Deferring hall requests on the way up
    Given a new sweep
    And the elevator is at floor 0
    And a car request for floor 5 is added
    And a hall request for floor 3 is added
    When the elevator is at floor 2
    Then the next stop should be floor 5
    And the queue should be 5, 3

  #
  # rehoming
  #

  @S-MOVE-LOOK-UNKNOWN @R-HOME-STRATEGY @R-MOVE-LOOK
  Scenario: Unknown position defaults to downward heading if requests exist
    Given a new sweep
    And the elevator is at floor unknown
    When a car request for floor 0 is added
    Then the heading should be down
    And the queue should be 0
