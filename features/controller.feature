Feature: Elevator Controller — Imperative Shell
  As the controller
  I want to wire core logic to hardware and message bus
  So that state changes are observable and hardware is driven

  @S-SYS-PUBSUB
  Scenario: Core state change is broadcast over PubSub
    Given the controller is running
    When the floor sensor reads floor 0
    Then a state update is broadcast on elevator:status

  @S-SYS-DISPATCH
  Scenario: Core actions are dispatched to hardware
    Given the controller is running
    When the floor sensor reads floor 0
    Then the motor receives a stop command

  @S-SYS-MOTOR-STOPPING
  Scenario: :motor_stopping hardware event is forwarded to Core and broadcast
    Given the controller is running
    When the floor sensor reads floor 0
    And the motor confirms it is stopping
    Then the core gets notified the motor status is stopping
