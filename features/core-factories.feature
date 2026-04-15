Feature: Elevator Core State Machine
    As the elevator core
    I want to transition between operational phases explicitly
    To ensure logic is predictable and deadlock-free
    # See states.md for all valid phases and transitions
    #
    # Factories
    #

  Scenario: Idle at floor 3
    Given the core is in phase idle at floor 3
    Then the motor is stopped
    And the door is closed
    And the heading is idle
    And the queue is empty
    And the elevator is at floor 3
    And the phase is idle

  Scenario: Docked at floor 3
    Given the core is in phase docked at floor 3
    Then the motor is stopped
    And the door is open
    And the heading is idle
    And the queue is empty
    And the current floor position is 3
    And the phase is docked

  Scenario: Moving from and to
    Given the core is moving from floor 2 to floor 3
    Then the motor is running
    And the door is closed
    And the heading is up
    And the queue is 3
    And the current floor position is unknown
    And the phase is moving

  Scenario: Booting
    Given the core is booting
    Then the motor is stopped
    And the door is closed
    And the heading is idle
    And the queue is empty
    And the current floor position is unknown
    And the phase is booting
    # Scenario: Rehoming
    #     Given the core is rehoming
    #     Then the motor is crawling
    #     And the door is closed
    #     And the heading is down
    #     And the queue is empty
    #     And the current floor position is unknown
    #     And the phase is rehoming
