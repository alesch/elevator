# Vault State Is Not Durable Across Process Crashes

## Context
- **Scenario**: N/A
- **Component**: Elevator.Vault
- **Source Reference**: [vault.ex](file:///home/alex/dev/elevator/lib/elevator/vault.ex)

## Current Status / Issue
`Elevator.Vault` stores the last known floor in GenServer process memory only (`init/1`
returns `{:ok, nil}`). If the Vault process crashes and is restarted by the root
supervisor, its state is lost and it returns `nil`.

This directly contradicts the module docstring which states: "Preserves the last known
arrival floor across crashes." It only survives HardwareStack crashes (because Vault
lives in a separate supervisor branch), but not Vault-process crashes or application
restarts.

When Vault restarts with `nil` and the HardwareStack subsequently restarts, the
Controller's homing check receives vault=`nil` and sensor=current_floor. Because
`warm_start?/2` requires both values to be equal integers, `nil` never satisfies this
condition and rehoming is triggered unconditionally, regardless of whether the elevator
is already at a known, safe position.

## Expected Behavior
The Vault must survive its own process crash and application restarts. After a Vault
crash and recovery, a subsequent Controller restart must be able to perform a warm start
if the persisted floor matches the sensor reading.

## How to Reproduce
- **Failing Test**: `mix test test/reset_test.exs` (before the `reset/0` hotfix that
  sets vault to `0` — revert `controller.ex` line and change `start_system` call back
  to `vault_floor: nil` to observe)
- **Scenario**: post-reset with vault=nil, sensor=0
- **Observed**: elevator docks at floor -1 instead of floor 0

## Proposed Solution
Replace the in-memory GenServer state with a durable backend:

1. **DETS or ETS with `:persistent_term`** — simplest option, file-backed, survives
   process crashes and node restarts.
2. **File-based storage** — write floor to a known path on `put_floor/2`, read on
   `init/1`.

On `init/1`, read the persisted value (defaulting to `0` if absent) instead of
returning `{:ok, nil}`.

## Verification Plan
- [ ] `mix test test/reset_test.exs` — warm start after simulated reset passes
- [ ] Kill the Vault process manually in IEx (`Process.exit(pid, :kill)`), confirm it
  restarts and `get_floor/1` returns the last written value
- [ ] `mix test` — full suite remains green
