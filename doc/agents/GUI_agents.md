# GUI Agent Guide

This document is the mental map for any agent working on the frontend of the Elevator GUI.

---

## 1. Key Files

| File | Purpose |
| :--- | :--- |
| `lib/elevator_web/live/dashboard_live.ex` | LiveView module: mount, event handlers, render template, and private components |
| `lib/elevator_web/live/dashboard_components.ex` | Reusable Phoenix components (`elevator_car`) |
| `lib/elevator_web/live/dashboard_helpers.ex` | Pure presentation logic: `floor_to_pixels/1`, `state_color/1`, `floor_class/3`, etc. |
| `priv/static/assets/app.css` | Single static CSS file. No build pipeline. Edit directly. |
| `priv/static/images/` | Static images (e.g. `forkme.png` GitHub ribbon) |
| `lib/elevator_web/layouts/root.html.heex` | HTML shell: loads CSS, fonts, and boots the LiveSocket |
| `lib/elevator_web/router.ex` | CSP headers configured here via `put_secure_browser_headers` |

There is **no esbuild, no webpack, no Tailwind**. The CSS is served as-is from `priv/static`.

---

## 2. Layout Structure

```text
<a class="github-ribbon">  (position: fixed, top-right corner)
<main class="dashboard-container">   (16:9 aspect-ratio locked, max 90vh)
├── .main-content      (flex row, overflow: hidden — clips anything that overflows)
│   ├── .left-panel    (fixed width: --shaft-width = 280px, flex column)
│   │   └── .shaft-container  (flex: 1, glassmorphism box — fills left-panel height)
│   │       ├── .digital-indicator   (current floor display, JetBrains Mono font)
│   │       ├── .shaft-layout        (flex row: labels column + shaft visual)
│   │       │   ├── .floor-labels    (6 clickable floor buttons, floor 5 → 0)
│   │       │   └── .shaft-visual    (dashed shaft, contains the moving car)
│   │       │       └── .car-container  (position: absolute, bottom: Xpx)
│   │       │           └── .elevator-car  (doors animate open/close)
│   │       └── .door-controls       (open/close buttons, INSIDE shaft-container)
│   └── .right-panel   (flex: 1, activity log — JetBrains Mono font)
└── .status-footer     (fixed 80px, justify-content: space-evenly)
    ├── .time-item      (TIME label + tick dot + readout + speed buttons)
    ├── .footer-item    (Core)
    ├── .footer-item    (Motor)
    ├── .footer-item    (Doors)
    └── .footer-item    (Queue)
<div class="page-footer">  (position: fixed, bottom credits line)
```

> [!IMPORTANT]
> `.main-content` has `overflow: hidden`. Anything that overflows its children will be **silently clipped**. This is the most common source of invisible UI elements.

---

## 3. The Floor Height Coupling (Critical)

Two values must always be equal and changed together:

- **CSS**: `--floor-height: 50px` in `app.css` `:root`
- **Elixir**: `floor_to_pixels(floor)` returns `floor * 50` in `dashboard_helpers.ex`

The car's `bottom:` position is computed in Elixir as `floor * N` pixels. The floor label slots are sized by `--floor-height: Npx`. If they disagree, the car will mis-align with the floor labels.

**Current value: 50px per floor.**

---

## 4. Car Positioning

The elevator car moves via inline style:

```heex
<div class="car-container" style={"bottom: #{floor_to_pixels(@visual_floor)}px;"}>
```

`visual_floor/3` in `dashboard_helpers.ex` applies a one-floor look-ahead while the motor is running (so the car appears to move smoothly toward its target before arrival is confirmed).

The CSS transition on `.car-container` handles the animation. The duration is computed from live `Elevator.Time` state and passed as `transit_ms` / `brake_ms` assigns.

---

## 5. Fonts

Fonts are loaded from **Google Fonts CDN** in `root.html.heex` with `&display=swap`:
- **Inter** — all UI text
- **JetBrains Mono** — digital indicator and activity log

Every CSS rule has an **explicit `font-family`** declaration. Do not rely on inheritance — elements rendered outside `.dashboard-container` (e.g. `position: fixed`) do not inherit `body` fonts reliably across all browsers.

---

## 6. Static Assets

Phoenix serves `priv/static/` via the plug in `endpoint.ex`. The allowed paths are declared in `ElevatorWeb.static_paths/0` in `elevator_web.ex`:

```elixir
def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)
```

To add a new static file, place it in the correct subfolder and reference it with `~p"/images/file.png"` (verified path helper). Do **not** use external URLs for assets — they may be blocked by CSP or unavailable in the deployed environment.

---

## 7. Security (CSP)

The Content Security Policy is set in `router.ex`:

```elixir
plug :put_secure_browser_headers, %{
  "content-security-policy" =>
    "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline' fonts.googleapis.com; font-src 'self' fonts.gstatic.com; img-src 'self' data:;"
}
```

If you add new external resources (CDN stylesheets, external images), you must update the CSP here or they will be silently blocked.

---

## 8. Reloading Changes

| Change type | How to reload |
| :--- | :--- |
| Template (`.ex` LiveView file) | Phoenix LiveReloader hot-reloads automatically |
| CSS (`app.css`) | Requires manual refresh: `Ctrl+R` |
| Elixir helpers/components | Phoenix LiveReloader hot-reloads automatically |

Always test in **Incognito/Private Mode** to avoid cookie conflicts from prior sessions on different ports.

---

## 9. Layout Budget (Approximate)

The `shaft-container` has roughly **480–560px** of vertical space depending on the viewport. Its content budget:

| Element | Height |
| :--- | :--- |
| `.digital-indicator` | 60px + 12px margin = **72px** |
| `.shaft-layout` (6 floors × 50px) | **300px** |
| `.door-controls` (buttons + padding) | **~54px** |
| `shaft-container` padding (12px × 2) | **40px** |
| **Total** | **~466px** |

If you need to add UI elements inside `.shaft-container`, reduce `--floor-height` (and `floor_to_pixels`) to reclaim space. Do **not** add elements as siblings of `.shaft-container` inside `.left-panel` — `shaft-container` uses `flex: 1` and will leave no room for them.

---

## 10. PubSub & State Flow

```text
Elevator.Controller
  └── Phoenix.PubSub.broadcast("elevator:status", {:elevator_state, state})
        └── DashboardLive.handle_info/2  →  assigns  →  render/1  →  DOM patch

Elevator.TelemetryLogger
  └── Phoenix.PubSub.broadcast("elevator:telemetry", {:telemetry_event, entry})
        └── DashboardLive.handle_info/2  →  activity_log append
```

The LiveView never calls the Controller directly except on `mount/3` (to read initial state) and on user events (`request_floor`, `open_door`, `close_door`).

On `mount/3`, when `connected?(socket)` is true, the LiveView also resets `Elevator.Time` speed to `1.0` — so a page reload always returns the speed buttons to their default state.
