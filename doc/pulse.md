# The Pulse Machine

The **Pulse Machine** is the heart of the Elevator's Functional Core. It is responsible for transforming raw signals into logical movements and hardware commands using a deterministic, three-stage pipeline.

---

## The Pipeline

The system processes every event in a single "pulse," transforming the state through three distinct representations to produce a unified **Pulse Result**.

```mermaid
graph TD
    start((start)) -->|Ingest reality| reality_updated((reality_updated))
    reality_updated -->|Logic transitions| transitions_applied((transitions_applied))
    
    subgraph "Action Derivation & Finalization"
        start -.->|Sample Past| Derivation{Derivation Logic}
        transitions_applied -->|Sample Present| Derivation
        Derivation --> Actions[Actions]
        transitions_applied -->|Clear Signals| final((final))
    end

    Actions & final --- Result((Pulse Result Bundle))
    Result -->|Return to Shell| Controller
```

### 1. start

The state **before** the pulse begins. It represents the "Absolute Past"—the reality as it was known just a millisecond ago.

### 2. reality_updated

The `Ingest` layer takes the incoming signal and updates the `hardware` map.

- If the signal is `:floor_arrival`, the floor number is updated here.
- If the signal is a hall call, it is added to the request queue here.
- **reality_updated** represents the system's "Current Reality" including the new event.

### 3. transitions_applied

The `Transit` layer evaluates the **reality_updated** state to see if any logical phases should change (e.g., from `:moving` to `:arriving`).

- **transitions_applied** represents the system's "New Intention."

---

## The Pulse Result Bundle: `{final, actions}`

The Pulse Machine returns a single tuple: **`{final, actions}`**.
`final` is the state of the elevator **after** the pulse.
`actions` is the list of actions to perform on the elevator

---

## Action Derivation (The Decision)

The most critical part of the Pulse Machine is that hardware commands (Actions) are derived by comparing **start** and **transitions_applied**.

> **Differential Advantage**: Comparing **start** to **transitions_applied** allows the system to react to hardware changes (ingested in `reality_updated`) and logic changes (decided in `transitions_applied`) simultaneously.

---

## Walkthrough: Arriving at the Target Floor

Consider an elevator moving up from Floor 0, tasked with stopping at Floor 3.  
A `:floor_arrival` signal for Floor 3 is received.

| Pipeline Stage | State Snapshot | Key Data |
| :--- | :--- | :--- |
| **start** | The baseline at the beginning. | `phase: :moving`, `floor: 0`, `target: 3` |
| **reality_updated**| After ingestion. | `phase: :moving`, **`floor: 3`**, `target: 3` |
| **transitions_applied**| After logic transitions. | **`phase: :arriving`**, `floor: 3`, `target: 3` |

### Derived Pulse Result (start vs transitions_applied)

| Reconciliation Logic | Observations | Output Included in Bundle |
| :--- | :--- | :--- |
| **Persistence** | `start.floor (0) != transitions_applied.floor (3)` | `{:persist_arrival, 3}` |
| **Motor Control** | `start.phase (:moving)` vs `transitions_applied.phase (:arriving)` | `{:stop_motor}` |
| **Finalization** | Cleanup of the `:floor_arrival` trigger. | **`final` State** |

---

## Why skip reality_updated for Derivation?

If we derived actions by comparing **reality_updated** and **transitions_applied**, the system would be "blind" to the hardware updates that happened during ingestion.

In the example above, **reality_updated** and **transitions_applied** both have `floor: 3`. A comparison would conclude that no floor change occurred during this pulse, and it would **forget to persist the arrival** to the database. By using **start**, we ensure every physical change is reconciled with the outside world.
