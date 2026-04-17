# Simulation & Testing

To run without waiting for real time, the system replaces wall-clock delays with a virtual clock and a physical simulation layer. Tests can run at any chosen speed without changing any application logic.

## Time Module

`Elevator.Time` is the system clock. It knows nothing about elevators.

- Ticks at a configurable interval (default **250ms**) and broadcasts `{:tick, n}` on `"elevator:simulation"`.
- Provides `send_after/4`: schedules a message after a delay divided by the speed multiplier.
- The **speed multiplier** (default `1.0`) compresses all delays proportionally. At `100.0×`, a 1,500ms floor transit fires in 15ms.
- `cancel/2` wraps `Process.cancel_timer/1` and is safe to call on an already-fired timer.

Test instances start with `name: nil` and skip the PubSub subscription — ticks are injected directly into the test process.

## World Module

`Elevator.World` simulates physical reality by counting ticks from Time.

The `World` will poke the doors, motor and sensors, at the right time to simulate the reality of time passing and its mechanical workings taking place (motor breaking, doors opening, a sensor firing).

**Physical constants** (at 250ms/tick):

| Scenario | Ticks | Wall time |
| :--- | :--- | :--- |
| Running: floor crossing | 6 | 1,500ms |
| Crawling: floor crossing | 18 | 4,500ms |
| Braking: motor stop | 2 | 500ms |

**Event flow for a floor crossing:**

```
Fixme: 
```

**Event flow for motor stopping:**

```
Controller  →  bus broadcast  {:command, :stop}
Motor       ←  (bus subscription)
Motor       →  bus broadcast  :motor_stopping       (announces intent)
World       →  Motor (direct, registry lookup)  :motor_stopped   (after brake ticks)
Motor       →  bus broadcast  :motor_stopped         (announces completion)
Controller  ←  (bus subscription)
```
