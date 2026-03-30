defmodule ElevatorWeb.DashboardComponents do
  @moduledoc """
  Functional UI components for the Industrial Elevator Dashboard.
  Uses modern Phoenix.Component declarative syntax.
  """
  use Phoenix.Component
  import ElevatorWeb.DashboardHelpers

  # ---------------------------------------------------------------------------
  # ## Public UI Components
  # ---------------------------------------------------------------------------

  @doc "Renders a visual indicator for a specific floor slot in the shaft."
  attr :floor, :integer, required: true
  attr :active, :boolean, default: false
  def floor_slot(assigns) do
    ~H"""
    <div class={["floor-slot", @active && "floor-active"]}></div>
    """
  end

  @doc "Renders the elevator car itself with animated doors."
  attr :floor, :any, required: true
  attr :door_state, :atom, required: true
  def elevator_car(assigns) do
    ~H"""
    <div
      id="elevator-car"
      class={["car-placeholder", @door_state in [:open, :opening] && "doors-open"]}
      style={"bottom: #{floor_to_pixels(@floor)}px;"}
    >
      <div class="door door-left"></div>
      <div class="door door-right"></div>
    </div>
    """
  end

  @doc "Renders a status box for a specific industrial system component."
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :state, :atom, required: true
  def status_box(assigns) do
    ~H"""
    <div class="actor-status">
      <div class="actor-icon"><%= @icon %></div>
      <div class="actor-label"><%= @label %></div>
      <div class="actor-state" style={"color: #{state_color(@state)}"}>
        <%= format_status(@state) %>
      </div>
    </div>
    """
  end
end
