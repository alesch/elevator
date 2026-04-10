# Cabbage Step Definitions Glossary

## Given Steps

| Step | Source |
| :--- | :--- |
| "door_status" is ":closed" | homing_test.exs:48 |
| a _\<source\>_ request for floor _\<floor\>_ | sweep_test.exs:58 |
| a request for floor _\<target\>_ is active | movement_wakeup_test.exs:94 |
| a sweep with car and hall requests for floor _\<floor\>_ | sweep_test.exs:81 |
| a sweep with heading _\<heading\>_ and the elevator at floor _\<floor\>_ | sweep_test.exs:16 |
| requests for floors: _\<floors\>_ | sweep_test.exs:26 |
| the "phase" is ":rehoming" | homing_test.exs:36 |
| the Elevator Sensor is ":unknown" or mismatches | homing_test.exs:31 |
| the Elevator Sensor is currently at _\<floor\>_ | homing_test.exs:24 |
| the Elevator Vault is empty | homing_test.exs:15 |
| the Elevator Vault stores _\<floor\>_ | homing_test.exs:19 |
| the elevator is idle at floor _\<current\>_ | movement_wakeup_test.exs:18 |
| the elevator is in "phase: :rehoming" | homing_test.exs:42 |
| the elevator is in phase _\<phase\>_ | safety_test.exs:14 |
| the elevator is moving up towards floor _\<target\>_ | movement_wakeup_test.exs:83 |

## When Steps

| Step | Source |
| :--- | :--- |
| _\<source\>_ request for floor _\<target\>_ is received | safety_test.exs:34 |
| a request for floor _\<target\>_ is received | movement_wakeup_test.exs:24 |
| any floor request is received | homing_test.exs:80 |
| floor _\<floor\>_ is serviced | sweep_test.exs:95 |
| requests are added for floors: _\<floors\>_ | sweep_test.exs:34 |
| the ":motor_stopped" confirmation is received after homing arrival | homing_test.exs:73 |
| the _\<button\>_ button is pressed | safety_test.exs:44 |
| the Core receives its very first ":floor_arrival" event | homing_test.exs:67 |
| the elevator is at floor _\<floor\>_ | sweep_test.exs:75 |
| the sensor confirms arrival at floor _\<target\>_ | movement_wakeup_test.exs:102 |
| the system (starts|reboots) | homing_test.exs:56 |

## Then Steps

| Step | Source |
| :--- | :--- |
| "current_floor" should be ":unknown" | homing_test.exs:105 |
| "door_status" should remain ":closed" | homing_test.exs:151 |
| "door_status" should stay ":closed" | homing_test.exs:134 |
| "heading" should be _\<heading\>_ | homing_test.exs:93 |
| "motor_speed" should be _\<speed\>_ | homing_test.exs:99 |
| _\<attr\>_ should become _\<val\>_ | homing_test.exs:174 |
| a stop command should be sent to the motor | movement_wakeup_test.exs:118 |
| floor _\<target\>_ should be in the pending requests | movement_wakeup_test.exs:71 |
| motor_status" should become ":stopping" | homing_test.exs:129 |
| no ":open_door" command should be issued | homing_test.exs:156 |
| no motor movement should be triggered | homing_test.exs:117 |
| the "phase" should be _\<phase\>_ | homing_test.exs:87 |
| the "phase" should transition ":rehoming" -> ":idle" immediately | homing_test.exs:110 |
| the "phase" should transition to ":idle" | homing_test.exs:146 |
| the _\<attr\>_ should immediately become _\<val\>_ | homing_test.exs:161 |
| the Vault should be updated with the current floor | homing_test.exs:139 |
| the button should be ignored | safety_test.exs:59 |
| the elevator should begin opening the doors | movement_wakeup_test.exs:50 |
| the elevator should begin to stop | movement_wakeup_test.exs:111 |
| the elevator should move until the first physical sensor confirms arrival | homing_test.exs:122 |
| the elevator should start moving _\<heading\>_ | movement_wakeup_test.exs:34 |
| the heading should be _\<heading\>_ | sweep_test.exs:116 |
| the next stop should be floor _\<floor\>_ | sweep_test.exs:109 |
| the queue should be: _\<floors\>_ | sweep_test.exs:43 |
| the request for floor _\<target\>_ should still be pending | movement_wakeup_test.exs:124 |
| the request should be fulfilled without any motor movement | movement_wakeup_test.exs:58 |
| the request should be ignored | safety_test.exs:52 |
| the request should be ignored and NOT added to the queue | homing_test.exs:182 |
| there should be no requests for floor _\<floor\>_ | sweep_test.exs:102 |

