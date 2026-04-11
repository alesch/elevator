alias Elevator.Core
alias Elevator.Sweep

# Test 1: Rehoming heading bug
state = Core.init()
{state, _} = Core.handle_event(state, :startup_check, %{vault: 3, sensor: 0}) # Mismatch -> Rehoming
IO.puts("Phase after mismatch: #{Core.phase(state)}")
IO.puts("Heading while rehoming (unknown floor): #{Core.heading(state)}") # Should be :down

{state, _} = Core.handle_event(state, :floor_arrival, 0)
IO.puts("Phase after F0 arrival: #{Core.phase(state)}")
IO.puts("Heading after F0 arrival (but motor still crawling): #{Core.heading(state)}") # Should be :down, but likely :idle now

# Test 2: floor_serviced heading staleness
state = Core.idle_at(0)
{state, _} = Core.request_floor(state, :car, 3)
IO.puts("Heading after request to F3: #{Core.heading(state)}") # Should be :up

{state, _} = Core.handle_event(state, :motor_running)
{state, _} = Core.handle_event(state, :floor_arrival, 3)
IO.puts("Phase after F3 arrival: #{Core.phase(state)}")
IO.puts("Heading after F3 arrival (in arriving phase): #{Core.heading(state)}") # Should be :up

{state, _} = Core.handle_event(state, :motor_stopped)
{state, _} = Core.handle_event(state, :door_opened, 0)
IO.puts("Phase after door opened: #{Core.phase(state)}")
IO.puts("Heading after door opened (docked): #{Core.heading(state)}") # Should it be :idle or :up?
