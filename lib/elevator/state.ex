defmodule Elevator.State do
  @moduledoc """
  The internal state of the elevator box.
  """
  defstruct [
    current_floor: 1,
    direction: :idle,
    door_status: :closed,
    requests: [],
    last_activity_at: 0,
    status: :normal,
    door_sensor: :clear
  ]
end
