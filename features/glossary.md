# Cabbage Step Definitions Glossary

## Given Steps

| Step | Source |
| :--- | :--- |
| "door_status" is ":closed" | homing_test.exs:48 |
| a _\<source\>_ request for floor _\<floor\>_ | sweep_test.exs:58 |
| a request exists for Floor _\<floor\>_ | core_test.exs:50 |
| a request for floor _\<target\>_ is active | movement_test.exs:141 |
| a request for the current floor is pending | movement_test.exs:333 |
| a sweep with car and hall requests for floor _\<floor\>_ | sweep_test.exs:81 |
| a sweep with heading _\<heading\>_ and the elevator at floor _\<floor\>_ | sweep_test.exs:16 |
| heading is _\<direction\>_ | core_test.exs:67 |
| it is moving up to serve a request at floor _\<target\>_ | movement_test.exs:196 |
| no pending requests remain | core_test.exs:62 |
| pending work exists in the queue | core_test.exs:56 |
| requests for floors: _\<floors\>_ | sweep_test.exs:26 |
| the "phase" is ":rehoming" | homing_test.exs:36 |
| the Elevator Sensor is ":unknown" or mismatches | homing_test.exs:31 |
| the Elevator Sensor is currently at _\<floor\>_ | homing_test.exs:24 |
| the Elevator Vault is empty | homing_test.exs:15 |
| the Elevator Vault stores _\<floor\>_ | homing_test.exs:19 |
| the core is in phase _\<phase\>_ | core_test.exs:17 |
| the doors are closing | movement_test.exs:187 |
| the doors are opening | movement_test.exs:176 |
| the elevator is (idle )?at floor _\<current\>_ | movement_test.exs:15 |
| the elevator is in "phase: :rehoming" | homing_test.exs:42 |
| the elevator is in phase _\<phase\>_ | safety_test.exs:14 |
| the elevator is moving up towards floor _\<target\>_ | movement_test.exs:128 |
| the elevator is stopping at a floor | movement_test.exs:167 |

## When Steps

| Step | Source |
| :--- | :--- |
| 5 minutes pass without any activity | movement_test.exs:217 |
| _\<source\>_ request for floor _\<target\>_ is received | safety_test.exs:34 |
| a hall request is received for floor _\<floor\>_ | movement_test.exs:229 |
| a passenger inside the car selects floor _\<floor\>_ | movement_test.exs:223 |
| a request for a different floor is received | core_test.exs:73 |
| a request for floor _\<target\>_ is received | movement_test.exs:21 |
| any floor request is received | homing_test.exs:80 |
| floor _\<floor\>_ is serviced | sweep_test.exs:95 |
| hall requests are received for floors _\<floors\>_ | movement_test.exs:258 |
| passengers inside the car select floors _\<floors\>_ | movement_test.exs:249 |
| requests are added for floors: _\<floors\>_ | sweep_test.exs:34 |
| the ":motor_stopped" confirmation is received after homing arrival | homing_test.exs:73 |
| the _\<button\>_ button is pressed | safety_test.exs:44 |
| the Core receives its very first ":floor_arrival" event | homing_test.exs:67 |
| the core arrives at floor _\<floor\>_ | core_test.exs:78 |
| the door confirms it has fully opened | movement_test.exs:212 |
| the door sensor detects an obstruction | movement_test.exs:281 |
| the elevator arrives at floor _\<floor\>_ | movement_test.exs:235 |
| the elevator is at floor _\<floor\>_ | sweep_test.exs:75 |
| the elevator passes floor _\<floor\>_ | movement_test.exs:241 |
| the elevator travels upward | movement_test.exs:267 |
| the elevator travels upward, passing floors 2 and 4 to reach floor 5 | movement_test.exs:272 |
| the motor confirms it has stopped | movement_test.exs:207 |
| the sensor confirms arrival at floor _\<target\>_ | movement_test.exs:148 |
| the system (starts|reboots) | homing_test.exs:56 |

## Then Steps

| Step | Source |
| :--- | :--- |
| "door_status" should remain ":closed" | homing_test.exs:170 |
| (floor )?_\<target\>_? is in the pending requests | movement_test.exs:80 |
| (the )?"?_\<field\>_"? is "_\<value\>_" | homing_test.exs:111 |
| (the )?"?_\<field\>_"? is "_\<value\>_" | movement_test.exs:71 |
| (the )?"?door_status"? is _\<value\>_ | homing_test.exs:102 |
| (the )?"?door_status"? is _\<value\>_ | movement_test.exs:59 |
| (the )?"?motor_status"? is _\<value\>_ | homing_test.exs:93 |
| (the )?"?motor_status"? is _\<value\>_ | movement_test.exs:38 |
| (the )?"?phase"? is _\<value\>_ | homing_test.exs:87 |
| (the )?"?phase"? is _\<value\>_ | movement_test.exs:32 |
| _\<attr\>_ should become _\<val\>_ | homing_test.exs:199 |
| a stop command should be sent to the motor | movement_test.exs:162 |
| floor _\<target\>_ is fulfilled | movement_test.exs:98 |
| floor _\<target\>_ should be in the pending requests | movement_test.exs:118 |
| it should continue towards floor _\<floor\>_ | movement_test.exs:310 |
| it should stop at floors: _\<floors\>_ | movement_test.exs:316 |
| no ":open_door" command should be issued | homing_test.exs:175 |
| no _\<cmd\>_ command is issued | homing_test.exs:155 |
| no motor movement should be triggered | homing_test.exs:134 |
| the "?request"? for floor _\<target\>_ is still pending | movement_test.exs:86 |
| the "phase" should transition to ":idle" | homing_test.exs:165 |
| the _\<attr\>_ should immediately become _\<val\>_ | homing_test.exs:180 |
| the Vault is updated with the current floor | homing_test.exs:146 |
| the button should be ignored | safety_test.exs:59 |
| the door is _\<value\>_ | core_test.exs:113 |
| the door timeout timer is set | core_test.exs:125 |
| the door timeout timer is set for 5 seconds | movement_test.exs:104 |
| the elevator should begin to stop | movement_test.exs:156 |
| the elevator should move until the first physical sensor confirms arrival | homing_test.exs:139 |
| the elevator should not stop at floor _\<floor\>_ | movement_test.exs:305 |
| the elevator should return to floor _\<floor\>_ | movement_test.exs:294 |
| the elevator should return to floor ground | movement_test.exs:288 |
| the elevator should stop at floor _\<floor\>_ | movement_test.exs:300 |
| the heading should be _\<heading\>_ | sweep_test.exs:116 |
| the motor is _\<value\>_ | core_test.exs:92 |
| the next stop should be floor _\<floor\>_ | sweep_test.exs:109 |
| the phase is _\<value\>_ | core_test.exs:86 |
| the queue should be: _\<floors\>_ | sweep_test.exs:43 |
| the request (for the current floor )?is fulfilled | movement_test.exs:92 |
| the request is fulfilled without any motor movement | movement_test.exs:109 |
| the request should be ignored | safety_test.exs:52 |
| the request should be ignored and NOT added to the queue | homing_test.exs:212 |
| there should be no requests for floor _\<floor\>_ | sweep_test.exs:102 |

