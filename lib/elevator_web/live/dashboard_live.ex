defmodule ElevatorWeb.DashboardLive do
  @moduledoc """
  Industrial Monitoring Dashboard.
  Provides real-time visualization of the elevator's internal and physical states.
  """
  use ElevatorWeb, :live_view
  require Logger

  import ElevatorWeb.DashboardComponents
  import ElevatorWeb.DashboardHelpers

  # ---------------------------------------------------------------------------
  # ## LiveView Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Logger.info("Dashboard: Connected")
      Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:status")
      Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:telemetry")
    end

    # Initial state from the real Controller (via Discovery Layer)
    state =
      case Registry.lookup(Elevator.Registry, :controller) do
        [{pid, _}] -> Elevator.Controller.get_state(pid)
        _ -> %Elevator.Core{}
      end

    {:ok,
     assign(socket,
       current_floor: state.current_floor,
       visual_floor: visual_floor(state.current_floor, state.motor_status, state.heading),
       is_moving: state.motor_status == :running,
       requests: state.requests,
       target_floor: get_target_floor(state),
       door_state: state.door_status,
       motor_state: state.motor_status,
       sensor_state: state.door_sensor,
       controller_state: state.status,
       activity_log: [
         %{actor: "🧠", id: 1, time: current_time(), msg: "LiveView Connected."}
       ]
     )}
  end

  @impl true
  @spec handle_info({:elevator_state, Elevator.Core.t()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:elevator_state, state}, socket) do
    {:noreply,
     socket
     |> assign(
       current_floor: state.current_floor,
       visual_floor: visual_floor(state.current_floor, state.motor_status, state.heading),
       is_moving: state.motor_status == :running,
       requests: state.requests,
       target_floor: get_target_floor(state),
       door_state: state.door_status,
       motor_state: state.motor_status,
       sensor_state: state.door_sensor,
       controller_state: state.status
     )}
  end

  @impl true
  @spec handle_info({:telemetry_event, map()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:telemetry_event, entry}, socket) do
    # Append to the end and keep the last 30 entries for higher density
    {:noreply,
     update(socket, :activity_log, fn logs ->
       Enum.take(logs ++ [entry], -30)
     end)}
  end

  # Catch-all for unexpected industrial messages
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(msg, socket) do
    Logger.warning("Dashboard: Unexpected info message #{inspect(msg)}")
    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("request_floor", %{"floor" => floor}, socket) do
    Elevator.Controller.request_floor(:car, String.to_integer(floor))
    {:noreply, socket}
  end

  def handle_event("open_door", _params, socket) do
    Elevator.Controller.open_door()
    {:noreply, socket}
  end

  def handle_event("close_door", _params, socket) do
    Elevator.Controller.close_door()
    {:noreply, socket}
  end

  # Catch-all for unexpected industrial events
  def handle_event(event, params, socket) do
    Logger.warning(
      "Dashboard: Unexpected event #{inspect(event)} with params: #{inspect(params)}"
    )

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard-container">
      <div class="main-content">
        <!-- SHAFT PANEL (25%) -->
        <div class="left-panel">
          <div class="shaft-container">
            <!-- Digital Floor Indicator -->
            <div class="digital-indicator">
              <%= if @current_floor == :unknown, do: "--", else: @current_floor %>
            </div>

            <div class="shaft-layout">
              <!-- Interactive Floor Labels -->
              <div class="floor-labels">
                <%= for floor <- 5..0//-1 do %>
                  <div
                    class={["floor-label", floor_class(floor, @requests, @target_floor)]}
                    phx-click="request_floor"
                    phx-value-floor={floor}
                    id={"label-#{floor}"}
                  >
                    <%= floor %>
                  </div>
                <% end %>
                <div class="door-controls">
                  <button phx-click="open_door">&lt;|&gt;</button>
                  <button phx-click="close_door">&gt;|&lt;</button>
                </div>
              </div>

              <!-- Shaft Visualization -->
              <div class="shaft-visual">
                <%= if @controller_state == :rehoming do %>
                  <div class="rehoming-banner">REHOMING</div>
                <% end %>

                <div class="car-container" style={"bottom: #{floor_to_pixels(@visual_floor)}px;"}>
                  <.elevator_car door_state={@door_state} slow={@controller_state == :rehoming} />
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- ACTIVITY LOG PANEL (75%) -->
        <div class="right-panel">
          <div class="log-header">
            <span>ACTIVITY LOG</span>
            <span class="text-xs opacity-50">REAL-TIME TELEMETRY</span>
          </div>
          <div id="log" class="activity-log" phx-hook="LogScroll">
            <%= for entry <- @activity_log do %>
              <div class={["log-entry", log_class(entry.actor)]}>
                [<%= entry.time %>] <%= entry.actor %>: <%= entry.msg %>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- HEALTH FOOTER -->
      <div class="status-footer">
        <.footer_item icon="🧠" label="Core" state={@controller_state} />
        <.footer_item icon="⚙️" label="Motor" state={@motor_state} />
        <.footer_item icon="🚪" label="Doors" state={@door_state} />
        <.footer_item icon="👁️" label="Sensors" state={@sensor_state} />
      </div>
    </div>
    """
  end

  defp footer_item(assigns) do
    ~H"""
    <div class="footer-item">
      <div class="status-icon"><%= @icon %></div>
      <div class="status-info">
        <span class="status-label"><%= @label %></span>
        <span class="status-value" style={"color: #{state_color(@state)}"}>
          <%= format_status(@state) %>
        </span>
      </div>
    </div>
    """
  end

  defp get_target_floor(%{requests: [], status: :rehoming}), do: 0
  defp get_target_floor(%{requests: []}), do: nil

  defp get_target_floor(%{requests: requests, current_floor: current, heading: heading}) do
    case heading do
      :up ->
        requests
        |> Enum.map(fn {_, f} -> f end)
        |> Enum.filter(&(&1 >= current))
        |> Enum.min(fn -> nil end)

      :down ->
        requests
        |> Enum.map(fn {_, f} -> f end)
        |> Enum.filter(&(&1 <= current))
        |> Enum.max(fn -> nil end)

      _ ->
        nil
    end
  end

  @spec current_time() :: String.t()
  defp current_time do
    Time.utc_now() |> Time.to_string() |> String.slice(0, 8)
  end
end
