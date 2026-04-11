Feature: Elevator Sweep Algorithm (LOOK)
  As an elevator brain
  I want an ordered queue of requests relative to my position
  So that I can travel efficiently using the LOOK algorithm

  @S-MOVE-LOOK-UP
  Scenario: Upward sweep orders ahead-requests first
    Given a sweep with heading up and the elevator at floor 3
    When requests are added for floors: 5, 2, 4
    Then the queue should be: 4, 5, 2

  @S-MOVE-LOOK-DOWN
  Scenario: Downward sweep orders ahead-requests first
    Given a sweep with heading down and the elevator at floor 3
    When requests are added for floors: 1, 5, 4
    Then the queue should be: 1, 4, 5

  @S-MOVE-LOOK-CAR
  Scenario: Stopping for car requests on the way up
    Given a sweep with heading up and the elevator at floor 2
    And a car request for floor 5
    And a car request for floor 3
    When the elevator is at floor 3
    Then the next stop should be floor 3

  @S-MOVE-LOOK-HALL-DEFER
  Scenario: Deferring hall requests on the way up
    Given a sweep with heading up and the elevator at floor 2
    And a car request for floor 5
    And a hall request for floor 3
    When the elevator is at floor 3
    Then the next stop should be floor 5

  @S-MOVE-LOOK-HALL-PEAK
  Scenario: Picking up hall requests at the top of the sweep
    Given a sweep with heading up and the elevator at floor 4
    And a hall request for floor 5
    When the elevator is at floor 5
    Then the next stop should be floor 5

  @S-MOVE-LOOK-HALL-DOWN
  Scenario: Picking up hall requests on the way down
    Given a sweep with heading down and the elevator at floor 4
    And a car request for floor 1
    And a hall request for floor 3
    When the elevator is at floor 3
    Then the next stop should be floor 3

  @S-MOVE-LOOK-SERVICE
  Scenario: Servicing a floor removes all requests for that floor
    Given a sweep with car and hall requests for floor 3
    When floor 3 is serviced
    Then there should be no requests for floor 3

  @S-MOVE-LOOK-NEXT
  Scenario: Calculating next stop
    Given a sweep with heading up and the elevator at floor 1
    And requests for floors: 2, 5
    Then the next stop should be floor 2

  @S-MOVE-LOOK-IDLE-START
  Scenario: Calculating next stop from IDLE
    Given a sweep with heading idle and the elevator at floor 3
    And a car request for floor 5
    Then the next stop should be floor 5
    And the heading should be up

  @S-MOVE-LOOK-IDLE-SAME
  Scenario: Request on current floor while IDLE
    Given a sweep with heading idle and the elevator at floor 3
    And a car request for floor 3
    Then the next stop should be floor 3
    And the heading should be idle

  @S-MOVE-LOOK-UP-SKIP
  Scenario: Defer Hall Request on the way up (Asymmetry Rule)
    Given a sweep with heading up and the elevator at floor 1
    And a hall request for floor 5
    When the elevator is at floor 3
    And a hall request for floor 3 is added
    Then the next stop should be floor 5
    And the queue should be: 5, 3

  @S-MOVE-LOOK-UNKNOWN @R-HOME-STRATEGY @R-MOVE-LOOK
  Scenario: Unknown position defaults to downward heading if requests exist
    Given a sweep with heading idle and the elevator at floor :unknown
    When a car request for floor 0 is added
    Then the heading should be down
    And the queue should be: 0
