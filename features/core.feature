Feature: Elevator Core State Machine
  As the elevator core
  I want to transition between operational phases explicitly
  To ensure logic is predictable and deadlock-free
  # See states.md for all valid phases and transitions

  #
  # Phase :idle
  #
  @R-CORE-STATE
  Scenario: idle means motor stopped, door closed and no requests pending
    Given the core is in phase idle at floor 0
    Then the motor is stopped
    And the door is closed
    And the heading is idle
    And the queue is empty

  @S-PHASE-IDLE-MOVE @R-CORE-STATE
  Scenario: (:idle → :moving) Hall request different floor
    Given the core is in phase idle at floor 0
    When a car request for floor 3 is received
    Then the phase is moving
    And the motor is running
    And the door is closed
    And the heading is up

  @S-PHASE-IDLE-ARRIVE @R-CORE-STATE
  Scenario: (:idle → :arriving) Hall request same floor
    Given the core is in phase idle at floor 0
    When a hall request for floor 0 is received
    Then the phase is arriving
    And the door is opening

  @S-PHASE-IDLE-INACTIVITY @R-CORE-STATE
  Scenario: (:idle → :moving) Inactivity Timeout
    Given the core is in phase idle at floor 3
    And the last activity was 5 minutes ago
    When the inactivity timeout expires
    Then the phase is moving
    And the queue is 0
    And the heading is down

  #
  # Phase :moving
  #
  @S-PHASE-MOVE-ARRIVE @R-CORE-STATE
  Scenario: (:moving -> :arriving) Target floor reached
    Given the core is in phase idle at floor 0
    And a car request for floor 3 is received
    Then the phase is moving
    When the arrival at floor 3 is received
    Then the phase is arriving
    And the motor is stopping
    And the door is closed

  #
  # Phase :arriving
  #
  @R-CORE-STATE
  Scenario: (:arriving -> :arriving) Doors open after motor is stopped
    Given the core is in phase idle at floor 0
    And a car request for floor 3 is received
    Then the phase is moving
    When the arrival at floor 3 is received
    Then the phase is arriving
    # ---
    When the motor is stopped
    Then the door is opening
    And the phase is arriving

  @S-PHASE-ARRIVE-DOCK @R-CORE-STATE
  Scenario: (:arriving -> :docked) Doors opening after motor is stopped
    Given the core is in phase idle at floor 0
    And a car request for floor 3 is received
    Then the phase is moving
    When the arrival at floor 3 is received
    Then the phase is arriving
  # ---




  @S-PHASE-MOVE-ARRIVE @R-CORE-STATE
  Scenario: :moving → :arriving
    Given the core is in phase moving
    And heading is up
    And a request exists for Floor 3
    When the core arrives at floor 3
    Then the phase is arriving
    And the motor is stopping

  @S-PHASE-ARRIVE-DOCK @R-CORE-STATE
  Scenario: :arriving → :docked
    Given the core is in phase arriving
    And the motor is stopped
    And door is opening
    When the door is confirmed open
    Then the phase is docked
    And door is open
    And the door timeout timer is set

  @S-PHASE-DOCK-LEAVE @R-CORE-STATE
  Scenario: :docked → :leaving
    Given the core is in phase docked
    And door is open
    And door_sensor is clear
    When the door timeout expires
    Then the phase is leaving
    And door is closing

  @S-PHASE-LEAVE-MOVE @R-CORE-STATE @R-MOVE-LOOK
  Scenario: :leaving → :moving
    Given the core is in phase leaving
    And pending work exists in the queue
    When the door is confirmed closed
    Then the phase is moving
    And the motor is running

  @S-PHASE-LEAVE-IDLE @R-CORE-STATE @R-MOVE-LOOK
  Scenario: :leaving → :idle
    Given the core is in phase leaving
    And no pending requests remain
    When the door is confirmed closed
    Then the phase is idle
    And the motor is stopped

  @S-PHASE-LEAVE-ARRIVE @R-CORE-STATE @R-SAFE-OBSTRUCT
  Scenario: :leaving → :arriving (Obstruction Gateway)
    Given the core is in phase leaving
    And door is closing
    When the door is obstructed
    Then the phase is arriving
    And door is opening
