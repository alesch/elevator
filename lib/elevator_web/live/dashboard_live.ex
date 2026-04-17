defmodule ElevatorWeb.DashboardLive do
  @moduledoc """
  Industrial Monitoring Dashboard.
  Provides real-time visualization of the elevator's internal and physical states.
  """
  use ElevatorWeb, :live_view
  require Logger

  import ElevatorWeb.DashboardComponents
  import ElevatorWeb.DashboardHelpers

  alias Elevator.Core

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
      Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:simulation")
      Elevator.Time.set_speed(1.0)
    end

    # Initial state from the real Controller (via Discovery Layer)
    state =
      case Registry.lookup(Elevator.Registry, :controller) do
        [{pid, _}] -> Elevator.Controller.get_state(pid)
        _ -> %Core{}
      end

    {transit_ms, brake_ms, door_ms} = time_durations()

    {:ok,
     assign(socket,
       current_floor: state.hardware.current_floor,
       visual_floor:
         visual_floor(
           state.hardware.current_floor,
           state.hardware.motor_status,
           Core.heading(state)
         ),
       is_moving: state.hardware.motor_status == :running,
       requests: state.logic.sweep.requests,
       target_floor: get_target_floor(state),
       door_state: state.hardware.door_status,
       motor_state: state.hardware.motor_status,
       sensor_state: state.hardware.door_sensor,
       controller_state: state.logic.phase,
       transit_ms: transit_ms,
       brake_ms: brake_ms,
       door_ms: door_ms,
       tick_blink: false,
       sim_speed: 1.0,
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
       current_floor: state.hardware.current_floor,
       visual_floor:
         visual_floor(
           state.hardware.current_floor,
           state.hardware.motor_status,
           Core.heading(state)
         ),
       is_moving: state.hardware.motor_status == :running,
       requests: state.logic.sweep.requests,
       target_floor: get_target_floor(state),
       door_state: state.hardware.door_status,
       motor_state: state.hardware.motor_status,
       sensor_state: state.hardware.door_sensor,
       controller_state: state.logic.phase
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

  @impl true
  @spec handle_info({:tick, non_neg_integer()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:tick, _counter}, socket) do
    {transit_ms, brake_ms, door_ms} = time_durations()

    {:noreply,
     assign(socket,
       transit_ms: transit_ms,
       brake_ms: brake_ms,
       door_ms: door_ms,
       tick_blink: !socket.assigns.tick_blink
     )}
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

  def handle_event("set_speed", %{"speed" => value}, socket) do
    {speed, _} = Float.parse(value)
    Elevator.Time.set_speed(speed)
    {:noreply, assign(socket, sim_speed: speed)}
  end

  def handle_event("set_speed", _params, socket), do: {:noreply, socket}

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
    <a class="github-ribbon" href="https://github.com/alesch/elevator" target="_blank" rel="noopener">
      <img width="149" height="149" src={~p"/images/forkme.png"} alt="Fork me on GitHub" />
    </a>

    <main class="dashboard-container">
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
                  <div class="floor-slot">
                    <div
                      class={["floor-label", floor_class(floor, @requests, @target_floor)]}
                      phx-click="request_floor"
                      phx-value-floor={floor}
                      id={"label-#{floor}"}
                    >
                      <%= floor %>
                    </div>
                  </div>
                <% end %>
              </div>

              <!-- Shaft Visualization -->
              <div class="shaft-visual">
                <%= if @controller_state == :rehoming do %>
                  <div class="rehoming-banner">REHOMING</div>
                <% end %>

                <div class="car-container" style={car_style(@visual_floor, @motor_state, @transit_ms, @brake_ms)}>
                  <.elevator_car door_state={@door_state} slow={@controller_state == :rehoming} door_ms={@door_ms} />
                </div>
              </div>
            </div>

            <div class="door-controls">
              <button type="button" phx-click="open_door">&lt;|&gt;</button>
              <button type="button" phx-click="close_door">&gt;|&lt;</button>
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
        <.time_item speed={@sim_speed} blink={@tick_blink} />
        <.footer_item icon="🧠" label="Core" state={@controller_state} />
        <.footer_item icon="⚙️" label="Motor" state={@motor_state} />
        <.footer_item icon="🚪" label="Doors" state={@door_state} />
        <.queue_item requests={@requests} />
      </div>
    </main>

    <div class="page-footer">
      ❤️ Coded by Alex Schenkman, Gemini 3 Flash, and Claude Sonnet 4.6.
    </div>
    """
  end

  defp time_item(assigns) do
    ~H"""
    <div class="footer-item time-item">
      <div class="status-info">
        <span class="status-label">TIME <span class={["tick-dot", @blink && "tick-dot--on"]}></span></span>
        <span class="status-value time-readout">
          <%= Float.round(@speed * 1.0, 1) %>x
          &nbsp;
          <%= round(250 / @speed) %>ms
          &nbsp;
          <%= Float.round(1000 / (250 / @speed), 1) %>Hz
        </span>
        <div class="speed-buttons">
          <%= for s <- [0.5, 1.0, 2.0, 5.0] do %>
            <button type="button" class={["speed-btn", @speed == s && "speed-btn--active"]}
                    phx-click="set_speed" phx-value-speed={s}>
              <%= s %>x
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp queue_item(assigns) do
    ~H"""
    <div class="footer-item">
      <div class="status-icon">📋</div>
      <div class="status-info">
        <span class="status-label">QUEUE</span>
        <span class="status-value" style="color: #445566">
          <%= if @requests == [], do: "[]", else: "[#{@requests |> Enum.map(fn {_, f} -> f end) |> Enum.join(" ")}]" %>
        </span>
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

  defp get_target_floor(%Core{logic: %{phase: :rehoming, sweep: %{requests: []}}}), do: 0
  defp get_target_floor(%Core{logic: %{sweep: %{requests: []}}}), do: nil

  defp get_target_floor(%Core{} = state) do
    requests = state.logic.sweep.requests
    current = state.hardware.current_floor

    case Core.heading(state) do
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

  # Returns {transit_ms, brake_ms} computed from the live Time state.
  # transit_ms: one floor at running speed (6 ticks)
  # brake_ms:   braking phase (2 ticks)
  @spec time_durations() :: {pos_integer(), pos_integer(), pos_integer()}
  defp time_durations do
    time_state =
      case Registry.lookup(Elevator.Registry, :time) do
        [{pid, _}] -> Elevator.Time.get_state(pid)
        _ -> %{tick_ms: 250, speed: 1.0}
      end

    scaled_tick = round(time_state.tick_ms / time_state.speed)
    {scaled_tick * 6, scaled_tick * 2, scaled_tick * 4}
  end
end
