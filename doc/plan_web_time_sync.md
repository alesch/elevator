# Plan: Web Layer Time Synchronization

## 1. Fix initial floor to 0 — match SystemCase.start_system

`SystemCase.start_system/1` seeds `Vault` with floor 0 and starts Sensor with
`current_floor: 0` (the fallback when the Vault is empty). `HardwareSupervisor`
must follow the same pattern.

**`hardware_supervisor.ex`**:
```elixir
# Before
{Elevator.Hardware.Sensor, [current_floor: 1, name: Elevator.Hardware.Sensor]},
{Elevator.Controller, [current_floor: 1, name: Elevator.Controller]}

# After — matches SystemCase.start_system defaults
{Elevator.Hardware.Sensor, [current_floor: 0, name: Elevator.Hardware.Sensor]},
{Elevator.Controller, [name: Elevator.Controller]}   # current_floor unused by Controller
```

**`application.ex` line 37** — World fallback floor:
```elixir
# Before
{Elevator.World, [name: Elevator.World, floor: 1]}
# After
{Elevator.World, [name: Elevator.World, floor: 0]}
```

---

## 2. Two animations, both timed from Elevator.Time

The `World` module defines two distinct physical phases:

| Phase | World constant | Duration at 1× |
| :--- | :--- | :--- |
| Travel (running) | `@ticks_per_floor[:running] = 6` | `6 × 250ms = 1500ms` |
| Braking (stopping) | `@brake_ticks = 2` | `2 × 250ms = 500ms` |

Both durations must be computed from `Elevator.Time` so they track the speed
multiplier (needed for the future speed slider).

```
transit_ms = round(tick_ms / speed) * 6
brake_ms   = round(tick_ms / speed) * 2
```

### DashboardLive changes

**`mount/3`**:
- Subscribe to `"elevator:simulation"`
- Look up `Elevator.Time` via Registry, call `get_state/1`
- Compute `transit_ms` and `brake_ms`
- Add both to assigns

**`handle_info({:tick, _counter}, socket)`** — new clause:
- Re-read `Elevator.Time.get_state()` and recompute both durations
- Update assigns — this keeps durations in sync when the speed slider changes

**Template — car-container div** switches transition style by `motor_status`:
```heex
# Before
<div class="car-container" style={"bottom: #{floor_to_pixels(@visual_floor)}px;"}>

# After
<div class="car-container" style={car_style(@visual_floor, @motor_state, @transit_ms, @brake_ms)}>
```

New private helper in `DashboardLive` (or `DashboardHelpers`):
```elixir
defp car_style(visual_floor, motor_state, transit_ms, brake_ms) do
  px = floor_to_pixels(visual_floor)
  transition =
    case motor_state do
      s when s in [:running, :crawling] -> "bottom #{transit_ms}ms linear"
      :stopping                         -> "bottom #{brake_ms}ms ease-out"
      _                                 -> "none"
    end
  "bottom: #{px}px; transition: #{transition};"
end
```

**`app.css`** — remove hardcoded transition from `.car-container`:
```css
/* Remove: transition: bottom 1.5s linear; */
```

---

## Files changed

| File | Change |
| :--- | :--- |
| `lib/elevator/application.ex` | `floor: 1` → `floor: 0` for World |
| `lib/elevator/hardware_supervisor.ex` | Sensor `current_floor: 0`; remove Controller `current_floor` |
| `lib/elevator_web/live/dashboard_live.ex` | Subscribe simulation; `transit_ms`/`brake_ms` assigns; tick handler |
| `lib/elevator_web/live/dashboard_live.ex` | `car_style/4` private helper (or in DashboardHelpers) |
| `priv/static/assets/app.css` | Remove hardcoded `transition` from `.car-container` |
