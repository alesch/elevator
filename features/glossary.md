# Cabbage Step Definitions Glossary

## Given Steps

| Step | Source |
| :--- | :--- |
| a _\<source\>_ request for floor _\<floor\>_ | sweep_test.exs:58 |
| a request exists for Floor _\<floor\>_ | core_test.exs:50 |
| a request for floor _\<target\>_ is active | movement_test.exs:143 |
| a request for the current floor is pending | movement_test.exs:335 |
| a sweep with car and hall requests for floor _\<floor\>_ | sweep_test.exs:81 |
| a sweep with heading _\<heading\>_ and the elevator at floor _\<floor\>_ | sweep_test.exs:16 |
| door is closing | core_test.exs:142 |
| door is open | core_test.exs:137 |
| door is opening | core_test.exs:132 |
| door_sensor is clear | core_test.exs:147 |
| door_status is :closed | homing_test.exs:45 |
| heading is _\<direction\>_ | core_test.exs:67 |
| it is moving up to serve a request at floor _\<target\>_ | movement_test.exs:198 |
| no pending requests remain | core_test.exs:62 |
| pending work exists in the queue | core_test.exs:56 |
| requests for floors: _\<floors\>_ | sweep_test.exs:26 |
| the Elevator Sensor is :unknown or mismatches | homing_test.exs:31 |
| the Elevator Sensor is currently at Floor _\<floor\>_ | homing_test.exs:24 |
| the Elevator Vault is empty | homing_test.exs:15 |
| the Elevator Vault stores Floor _\<floor\>_ | homing_test.exs:19 |
| the core is in phase _\<phase\>_ | core_test.exs:17 |
| the doors are closing | movement_test.exs:189 |
| the doors are opening | movement_test.exs:178 |
| the elevator is (idle )?at floor _\<current\>_ | movement_test.exs:15 |
| the elevator is in phase _\<phase\>_ | safety_test.exs:14 |
| the elevator is moving up towards floor _\<target\>_ | movement_test.exs:130 |
| the elevator is rehoming | homing_test.exs:36 |
| the elevator is stopping at a floor | movement_test.exs:169 |
| the motor is stopped | core_test.exs:152 |

## When Steps

| Step | Source |
| :--- | :--- |
| 5 minutes pass without any activity | movement_test.exs:219 |
| _\<source\>_ request for floor _\<target\>_ is received | safety_test.exs:34 |
| a hall request is received for floor _\<floor\>_ | movement_test.exs:231 |
| a passenger inside the car selects floor _\<floor\>_ | movement_test.exs:225 |
| a request for a different floor is received | core_test.exs:73 |
| a request for floor _\<target\>_ is received | movement_test.exs:21 |
| any floor request is received | homing_test.exs:77 |
| floor _\<floor\>_ is serviced | sweep_test.exs:95 |
| hall requests are received for floors _\<floors\>_ | movement_test.exs:260 |
| passengers inside the car select floors _\<floors\>_ | movement_test.exs:251 |
| requests are added for floors: _\<floors\>_ | sweep_test.exs:34 |
| the :motor_stopped confirmation is received after homing arrival | homing_test.exs:70 |
| the _\<button\>_ button is pressed | safety_test.exs:44 |
| the Core receives its very first :floor_arrival event | homing_test.exs:64 |
| the core arrives at floor _\<floor\>_ | core_test.exs:78 |
| the door confirms it has fully opened | movement_test.exs:214 |
| the door is confirmed closed | core_test.exs:162 |
| the door is confirmed open | core_test.exs:157 |
| the door is obstructed | core_test.exs:172 |
| the door sensor detects an obstruction | movement_test.exs:283 |
| the door timeout expires | core_test.exs:167 |
| the elevator arrives at floor _\<floor\>_ | movement_test.exs:237 |
| the elevator is at floor _\<floor\>_ | sweep_test.exs:75 |
| the elevator passes floor _\<floor\>_ | movement_test.exs:243 |
| the elevator travels upward | movement_test.exs:269 |
| the elevator travels upward, passing floors 2 and 4 to reach floor 5 | movement_test.exs:274 |
| the motor confirms it has stopped | movement_test.exs:209 |
| the sensor confirms arrival at floor _\<target\>_ | movement_test.exs:150 |
| the system (starts|reboots) | homing_test.exs:53 |

## Then Steps

| Step | Source |
| :--- | :--- |
| (floor )?_\<target\>_ is in the pending requests | movement_test.exs:76 |
| (the )?(\w+) is ([^ ]+) | homing_test.exs:84 |
| (the )?(\w+) is ([^ ]+) | homing_test.exs:116 |
| (the )?_\<field\>_ is _\<val\>_ | movement_test.exs:32 |
| _\<attr\>_ should become _\<val\>_ | homing_test.exs:213 |
| a stop command should be sent to the motor | movement_test.exs:164 |
| door is closing | core_test.exs:177 |
| door is open | core_test.exs:187 |
| door is opening | core_test.exs:182 |
| door_status should remain :closed | homing_test.exs:184 |
| floor _\<target\>_ is fulfilled | movement_test.exs:100 |
| floor _\<target\>_ should be in the pending requests | movement_test.exs:120 |
| it should continue towards floor _\<floor\>_ | movement_test.exs:312 |
| it should stop at floors: _\<floors\>_ | movement_test.exs:318 |
| no :open_door command should be issued | homing_test.exs:189 |
| no _\<cmd\>_ command is issued | homing_test.exs:169 |
| no motor movement should be triggered | homing_test.exs:148 |
| the _\<attr\>_ should immediately become _\<val\>_ | homing_test.exs:194 |
| the Vault is updated with the current floor | homing_test.exs:160 |
| the button should be ignored | safety_test.exs:59 |
| the door is _\<value\>_ | core_test.exs:113 |
| the door timeout timer is set | core_test.exs:125 |
| the door timeout timer is set for 5 seconds | movement_test.exs:106 |
| the elevator should begin to stop | movement_test.exs:158 |
| the elevator should move until the first physical sensor confirms arrival | homing_test.exs:153 |
| the elevator should not stop at floor _\<floor\>_ | movement_test.exs:307 |
| the elevator should return to floor _\<floor\>_ | movement_test.exs:296 |
| the elevator should return to floor ground | movement_test.exs:290 |
| the elevator should stop at floor _\<floor\>_ | movement_test.exs:302 |
| the heading should be _\<heading\>_ | sweep_test.exs:116 |
| the motor is _\<value\>_ | core_test.exs:92 |
| the motor is running | core_test.exs:192 |
| the motor is stopping | core_test.exs:197 |
| the next stop should be floor _\<floor\>_ | sweep_test.exs:109 |
| the phase is _\<value\>_ | core_test.exs:86 |
| the phase should transition to :idle | homing_test.exs:179 |
| the queue should be: _\<floors\>_ | sweep_test.exs:43 |
| the request (for the current floor )?is fulfilled | movement_test.exs:94 |
| the request for floor _\<target\>_ is still pending | movement_test.exs:88 |
| the request is fulfilled without any motor movement | movement_test.exs:111 |
| the request should be ignored | safety_test.exs:52 |
| the request should be ignored and NOT added to the queue | homing_test.exs:226 |
| there should be no requests for floor _\<floor\>_ | sweep_test.exs:102 |

