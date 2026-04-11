alias Elevator.Core

state = Core.idle_at(0)
IO.inspect(state, label: "Initial State (Idle at 0)")

{new_state, actions} = Core.request_floor(state, :car, 0)
IO.inspect(new_state, label: "State after request_floor(0, :car, 0)")
IO.inspect(actions, label: "Actions after request_floor(0, :car, 0)")

if new_state.door_status != :opening do
  IO.puts "FAILURE: door_status is #{new_state.door_status}, expected :opening"
end
