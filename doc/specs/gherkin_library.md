# Gherkin Step Library: Elevator Behavioral Language

This document tracks finalized phrasing for our BDD stories to ensure high reusability and clear domain alignment across all features.

## 1. Initial States (Given)

| Step Type | Step Text | Example |
| :--- | :--- | :--- |
| **Given** | `the elevator is operational` | `Given the elevator is operational` |
| **Given** | `the elevator is idle at floor {floor}` | `Given the elevator is idle at floor ground` |
| **Given** | `the elevator is at floor {floor}` | `Given the elevator is at floor ground` |
| **Given** | `it is moving {direction} to serve a request at floor {floor}` | `And it is moving up to serve a request at floor 5` |
| **Given** | `a request for floor {floor} is active` | `Given a request for floor 3 is active` |
| **Given** | `hall requests are received for floors {list}` | `And hall requests are received for floors 2, 4, and 5` |
| **Given** | `the elevator doors are opening at floor {floor}` | `Given the elevator doors are opening at floor 3` |
| **Given** | `the doors are opening` | `And the doors are opening` |
| **Given** | `the doors are closing` | `And the doors are closing` |
| **Given** | `a request for the current floor is pending` | `And a request for the current floor is pending` |

## 2. Input Triggers (When)

| Step Type | Step Text | Example |
| :--- | :--- | :--- |
| **When** | `a request for floor {floor} is received` | `When a request for floor 3 is received` |
| **When** | `a hall request is received for floor {floor}` | `When a hall request is received for floor 3` |
| **When** | `a passenger inside the car selects floor {floor}` | `When a passenger inside the car selects floor 3` |
| **When** | `passengers inside the car select floors {list}` | `When passengers inside the car select floors 2, 4, and 5` |
| **When** | `{time} pass without any activity` | `When 5 minutes pass without any activity` |
| **When** | `the sensor confirms arrival at floor {floor}` | `When the sensor confirms arrival at floor 3` |
| **When** | `the elevator arrives at floor {floor}` | `And the elevator arrives at floor 3` |
| **When** | `the elevator passes floor {floor}` | `And the elevator passes floor 3` |
| **When** | `the motor confirms it has stopped` | `When the motor confirms it has stopped` |
| **When** | `the door confirms it has fully opened` | `When the door confirms it has fully opened` |
| **When** | `the door sensor detects an obstruction` | `When the door sensor detects an obstruction` |
| **When** | `the elevator travels {direction}` | `When the elevator travels upward` |
| **When** | `the elevator travels {direction}, passing floors {list} to reach floor {floor}` | `When the elevator travels upward, passing floors 2 and 4 to reach floor 5` |

## 3. Behavioral Outcomes (Then)

| Step Type | Step Text | Example |
| :--- | :--- | :--- |
| **Then** | `the elevator should be idle at floor {floor}` | `Then the elevator should be idle at floor ground` |
| **Then** | `the elevator should return to floor {floor}` | `Then the elevator should return to floor ground` |
| **Then** | `the elevator should be at floor {floor}` | `Then the elevator should be at floor 3` |
| **Then** | `the elevator should not stop at floor {floor}` | `Then the elevator should not stop at floor 3` |
| **Then** | `the elevator should be docked at floor {floor}` | `Then the elevator should be docked at floor 3` |
| **Then** | `the motor should stay stopped` | `Then the motor should stay stopped` |
| **Then** | `the elevator should remain inert` | `Then the elevator should remain inert` |
| **Then** | `it should stop at floors: {list}` | `Then it should stop at floors: 2, 4, 5` |
| **Then** | `the elevator should begin opening the doors` | `Then the elevator should begin opening the doors` |
| **Then** | `the elevator should stop at floor {floor}` | `Then the elevator should stop at floor 3` |
| **Then** | `it should continue towards floor {floor}` | `And it should continue towards floor 5` |
| **Then** | `the doors should be set to close in {seconds} seconds` | `Then the doors should be set to close in 5 seconds` |
| **Then** | `the elevator should start moving {direction}` | `Then the elevator should start moving up` |
| **Then** | `floor {floor} should be in the pending requests` | `Then floor 3 should be in the pending requests` |
| **Then** | `the elevator should begin to stop` | `Then the elevator should begin to stop` |
| **Then** | `a stop command should be sent to the motor` | `Then a stop command should be sent to the motor` |
| **Then** | `the request for floor {floor} should still be pending` | `Then the request for floor 3 should still be pending` |
| **Then** | `the request for the current floor should be fulfilled` | `Then the request for the current floor should be fulfilled` |
| **Then** | `the request should be fulfilled without any motor movement` | `And the request should be fulfilled without any motor movement` |
| **Then** | `a request for floor {floor} should be added` | `Then a request for floor ground should be added` |

---
