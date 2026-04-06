# Gherkin Step Library: Elevator Behavioral Language

This document tracks finalized phrasing for our BDD stories to ensure high reusability and clear domain alignment across all features.

## 1. Direction & Intent (Given/When)

| Step Type | Step Text | Example |
| :--- | :--- | :--- |
| **Given** | `the elevator is operational` | `Given the elevator is operational` |
| **Given** | `the elevator is idle at floor {floor}` | `Given the elevator is idle at floor ground` |
| **When** | `a request for floor {floor} is received` | `When a request for floor 3 is received` |
| **When** | `passengers inside the car select floors {list}` | `When passengers inside the car select floors 2, 4, and 5` |

## 2. Outcomes & Observations (Then)

| Step Type | Step Text | Example |
| :--- | :--- | :--- |
| **Then** | `the elevator should be idle at floor {floor}` | `Then the elevator should be idle at floor ground` |
| **Then** | `the elevator should return to floor {floor}` | `Then the elevator should return to floor ground` |
| **Then** | `the elevator should be at floor {floor}` | `Then the elevator should be at floor 3` |
| **Then** | `the motor should stay stopped` | `Then the motor should stay stopped` |
| **Then** | `the elevator should remain inert` | `Then the elevator should remain inert` |

## 3. Interaction & Sequences

| Step Type | Step Text | Example |
| :--- | :--- | :--- |
| **Then** | `it should stop at floors: {list}` | `Then it should stop at floors: 2, 4, 5` |
| **Then** | `the elevator should begin opening the doors` | `Then the elevator should begin opening the doors` |

---
