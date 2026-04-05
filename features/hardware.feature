Feature: Hardware Protocols
  As a hardware driver
  I want to maintain internal state for motor, door, and sensors
  To ensure the Physical Shell accurately reflects Core intent

  @S-HW-MOTOR
  Scenario: Motor Movement Protocol
    Given the motor receives a ":move" command
    When the command includes "direction" and "speed"
    Then the internal hardware state should accurately reflect these parameters

  @S-HW-DOOR
  Scenario: Door Operation Protocol
    Given the door receives an ":open" or ":close" command
    When the operation begins
    Then the door state should transition to ":opening" or ":closing"

  @S-HW-SENSOR
  Scenario: Sensor Floor Tracking
    Given the sensor receives a physical floor pulse
    When the pulse is received at Floor X
    Then the internal hardware state should correctly identify Floor X as the current position
