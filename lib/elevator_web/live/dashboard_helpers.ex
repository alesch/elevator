defmodule ElevatorWeb.DashboardHelpers do
  @moduledoc """
  Functional presentation logic for the Elevator Dashboard.
  Translates logical system states into visual CSS values.
  """

  # ---------------------------------------------------------------------------
  # ## Visual Helpers
  # ---------------------------------------------------------------------------

  @doc """
  Builds the inline style for the car container.
  Switches transition duration and easing between the travel and braking phases.
  """
  @spec car_style(integer() | :unknown, atom(), pos_integer(), pos_integer()) :: String.t()
  def car_style(visual_floor, motor_state, transit_ms, brake_ms) do
    px = floor_to_pixels(visual_floor)

    transition =
      case motor_state do
        s when s in [:running, :crawling] -> "bottom #{transit_ms}ms linear"
        :stopping -> "bottom #{brake_ms}ms ease-out"
        _ -> "none"
      end

    "bottom: #{px}px; transition: #{transition};"
  end

  @doc "Maps a floor number to its vertical pixel offset in the shaft visualization."
  @spec floor_to_pixels(integer() | :unknown) :: integer()
  def floor_to_pixels(:unknown), do: 0
  def floor_to_pixels(floor) when is_integer(floor), do: floor * 50

  @doc "Calculates the anticipatory visual floor for smooth synchronization."
  @spec visual_floor(integer() | :unknown, atom(), atom()) :: integer() | :unknown
  def visual_floor(:unknown, _, _), do: :unknown
  def visual_floor(floor, status, :up) when status in [:running, :crawling], do: floor + 1
  def visual_floor(floor, status, :down) when status in [:running, :crawling], do: floor - 1
  def visual_floor(floor, _, _), do: floor

  @doc "Determines the industrial color code for a given component status."
  @spec state_color(atom()) :: String.t()
  # Cyan (Healthy: Active or Ready)
  def state_color(state)
      when state in [
             :crawling,
             :running,
             :tracking,
             :closed,
             :idle,
             :stopped,
             :clear,
             :open,
             :docked,
             :moving
           ],
      do: "#00f2ff"

  # Amber (Intent & Transitions)
  def state_color(state)
      when state in [:stopping, :opening, :closing, :rehoming, :booting, :arriving, :leaving],
      do: "#ffae00"

  # Red (Alert / Unspecified)
  def state_color(state) when state in [:obstructed],
    do: "#ff3131"

  def state_color(_), do: "#ff3131"

  @doc "Formats a status atom for display."
  @spec format_status(atom()) :: String.t()
  def format_status(nil), do: "---"
  def format_status(status), do: status |> Atom.to_string() |> String.upcase()

  @doc "Determines CSS class for floor labels based on state."
  @spec floor_class(integer(), list(), integer() | nil) :: String.t()
  def floor_class(floor, requests, target) do
    cond do
      floor == target -> "targeting"
      Enum.any?(requests, fn {_, f} -> f == floor end) -> "pending"
      true -> ""
    end
  end

  @doc "Maps telemetry actors to log styles."
  @spec log_class(String.t()) :: String.t()
  def log_class("🧠"), do: "system"
  def log_class("⚙️"), do: "event"
  def log_class("🚪"), do: "event"
  def log_class(_), do: ""
end
