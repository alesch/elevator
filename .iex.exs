defmodule Dev do
  @moduledoc "Convenience helpers for IEx development sessions."

  def restart do
    Elevator.Vault.put_floor(Elevator.Vault, nil)
    Process.whereis(Elevator.HardwareSupervisor) |> Process.exit(:kill)
    :ok
  end

  def floor(n), do: Elevator.Controller.request_floor(:car, n)
  def hall(n), do: Elevator.Controller.request_floor(:hall, n)
  def open, do: Elevator.Controller.open_door()
  def close, do: Elevator.Controller.close_door()
  def state, do: Elevator.Controller.get_state()
end

IO.puts("\n== Dev helpers loaded ==")
IO.puts("  Dev.restart()  — clear vault and rehome to F0")
IO.puts("  Dev.floor(n)   — car request for floor n")
IO.puts("  Dev.hall(n)    — hall request for floor n")
IO.puts("  Dev.open()     — open doors")
IO.puts("  Dev.close()    — close doors")
IO.puts("  Dev.state()    — inspect Core state")
IO.puts("")
