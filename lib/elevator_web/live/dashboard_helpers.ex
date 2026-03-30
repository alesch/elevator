defmodule ElevatorWeb.DashboardHelpers do
  @moduledoc """
  Functional presentation logic for the Elevator Dashboard.
  Translates logical system states into visual CSS values.
  """

  # ---------------------------------------------------------------------------
  # ## Visual Helpers
  # ---------------------------------------------------------------------------

  @doc "Maps a floor number to its vertical pixel offset in the shaft visualization."
  @spec floor_to_pixels(integer() | :unknown) :: integer()
  def floor_to_pixels(:unknown), do: 0
  def floor_to_pixels(floor) when is_integer(floor), do: floor * 50

  @doc "Determines the industrial color code for a given component status."
  @spec state_color(atom()) :: String.t()
  def state_color(state) when state in [:idle, :stopped, :clear, :open, :normal], do: "#2ecc71" # Green
  def state_color(state) when state in [:moving, :running, :tracking, :closed, :rehoming], do: "#3498db" # Blue
  def state_color(_), do: "#f39c12" # Yellow/Orange

  @doc "Formats a status atom for display."
  @spec format_status(atom()) :: String.t()
  def format_status(nil), do: "---"
  def format_status(status), do: status |> Atom.to_string() |> String.upcase()
end
