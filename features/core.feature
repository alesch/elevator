Feature: Elevator Core State Machine
  As the elevator core
  I want to transition between operational phases explicitly
  To ensure logic is predictable and deadlock-free
  # See states.md for all valid phases and transitions
  #
  #
  # Phase: booting
  #

  Scenario: (:booting -> :opening) Zero movement recovery
    Given the elevator is booting
    And the last saved elevator position is 3
    And the elevator is at floor 3
    When the signal startup-check is received
    Then the phase is opening

  Scenario: (:booting -> :rehoming) Rehoming recovery
    Given the elevator is booting
    And the last saved elevator position is unknown
    When the signal startup-check is received
    Then the phase is rehoming
    And the motor begins crawling
    And the heading is down
  #
  # Phase: rehoming
  #

  Scenario: (:rehoming -> :arriving) Crawling to find position
    Given the elevator is rehoming
    When the arrival at floor 1 is received
    Then the motor phase is arriving
    And the motor begins stopping
  #
  # Phase :idle
  #

  @S-PHASE-IDLE-MOVE @R-CORE-STATE
  Scenario: (:idle → :moving) Hall request different floor
    Given the core is in phase idle at floor 0
    When a car request for floor 3 is received
    Then the phase is leaving
    And the motor begins running
    And the door is closed
    And the heading is up

  @S-PHASE-IDLE-ARRIVE @R-CORE-STATE
  Scenario: (:idle → :arriving) Hall request same floor
    Given the core is in phase idle at floor 0
    When a hall request for floor 0 is received
    Then the phase is opening
    And the door begins opening

  @S-PHASE-IDLE-INACTIVITY @R-CORE-STATE
  Scenario: (:idle → :moving) Inactivity Timeout
    Given the core is in phase idle at floor 3
    And the last activity was 5 minutes ago
    When the inactivity timeout expires
    Then the phase is leaving
    And the queue is 0
    And the heading is down
  #
  # Phase :moving
  #

  @S-PHASE-MOVE-ARRIVE @R-CORE-STATE
  Scenario: (:moving -> :arriving) Target floor reached
    Given the core is moving from floor 2 to floor 3
    When the arrival at floor 3 is received
    Then the phase is arriving
    And the motor begins stopping
    And the door is closed
  #
  # Phase :arriving
  #

  @S-PHASE-MOVE-ARRIVE @R-CORE-STATE
  Scenario: (:arriving -> :opening) Transition after motor is stopped
    Given the core is moving from floor 2 to floor 3
    When the arrival at floor 3 is received
    Then the phase is arriving
    # ---
    When the motor is stopped
    Then the phase is opening
  #
  # Phase: opening
  #

  @S-PHASE-ARRIVE-DOCK @R-CORE-STATE
  Scenario: (:opening -> :docked) Transition after door opened
    Given the core is moving from floor 2 to floor 3
    When the arrival at floor 3 is received
    Then the phase is arriving
    When the motor is stopped
    Then the phase is opening
    # ---
    When the door is open
    Then the phase is docked
    And the door timeout timer is set
  #
  # Phase: docked
  #

  Scenario: (:docked -> :closing) Transition after door timeout
    Given the core is in phase docked at floor 3
    When the door timeout is received
    Then the door begins closing
    And the phase is closing

  Scenario: (:docked -> :closing) Transition after button door-close is pressed
    Given the core is in phase docked at floor 3
    When the button door-close is pressed
    Then the door begins closing
    And the phase is closing
  #
  # Phase: closing
  #

  @S-PHASE-DOCK-LEAVE @R-CORE-STATE
  Scenario: (:closing → :leaving) Transition after door is closed and requests pending
    Given the core is in phase docked at floor 3
    And a car request for floor 0 is received
    When the door timeout is received
    And the door is closed
    Then the phase is leaving
    And the motor is stopped

  @S-PHASE-LEAVE-ARRIVE @R-CORE-STATE @R-SAFE-OBSTRUCT
  Scenario: (:closing → :opening) Door obstruction
    Given the core is in phase docked at floor 3
    And the door timeout is received
    Then the door begins closing
    When the door is obstructed
    Then the phase is opening
    And the door begins opening

  @S-PHASE-LEAVE-IDLE @R-CORE-STATE @R-MOVE-LOOK
  Scenario: (:closing → :idle) Door timeout and no requests pending
    Given the core is in phase docked at floor 3
    And the door timeout is received
    Then the door begins closing
    When the door is closed
    Then the motor is stopped
    And the phase is idle
    And the queue is empty
  #
  # Phase: leaving
  #

  @S-PHASE-LEAVE-MOVE @R-CORE-STATE @R-MOVE-LOOK
  Scenario: :leaving → :moving
    Given the core is in phase docked at floor 3
    And a car request for floor 0 is received
    When the door timeout is received
    Then the door begins closing
    When the door is closed
    Then the motor begins running
    When the motor is running
    And the phase is moving
  #
  # Buttons ignored during boot and rehoming
  #

  @S-BOOT-BLOCK-REQ @R-BOOT-GUARD
  Scenario Outline: Request Blocking during Booting
    Given the elevator is in phase <phase>
    Then the queue is empty
    When a <source> request for floor <target> is received
    Then the queue is empty

    Examples:
      | phase     | source | target |
      | :booting  | :car   |      2 |
      | :rehoming | :hall  |      3 |

  @S-BOOT-BLOCK-BUTTON @R-BOOT-GUARD
  Scenario Outline: Button Blocking during Booting
    Given the elevator is in phase <phase>
    When the button <button> is pressed
    Then no action should be taken

    Examples:
      | phase     | button      |
      | :booting  | :door_open  |
      | :booting  | :door_close |
      | :rehoming | :door_close |
      | :rehoming | :door_open  |
