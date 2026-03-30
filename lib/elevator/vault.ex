defmodule Elevator.Vault do
  @moduledoc """
  The 'Black Box' of the building.
  Stores the last confirmed physical floor that the elevator visited.
  """
  use Agent

  @doc "Starts the Vault agent."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> nil end, name: name)
  end

  @doc "Puts a new floor into the vault."
  def put_floor(pid \\ __MODULE__, floor) do
    Agent.update(pid, fn _ -> floor end)
  end

  @doc "Gets the last known floor from the vault."
  def get_floor(pid \\ __MODULE__) do
    Agent.get(pid, & &1)
  end
end
