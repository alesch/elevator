defmodule ElevatorWeb.DashboardLive do
  @moduledoc """
  Industrial Monitoring Dashboard.
  Provides real-time visualization of the elevator's internal and physical states.
  """
  use ElevatorWeb, :live_view
  require Logger

  import ElevatorWeb.DashboardComponents

  # ---------------------------------------------------------------------------
  # ## LiveView Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:status")
      Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:telemetry")
    end

    # Initial state from the real Controller (via Discovery Layer)
    state =
      case Registry.lookup(Elevator.Registry, :controller) do
        [{pid, _}] -> Elevator.Controller.get_state(pid)
        _ -> %Elevator.State{}
      end

    {:ok,
     assign(socket,
       current_floor: state.current_floor,
       is_moving: state.motor_status == :running,
       door_state: state.door_status,
       motor_state: state.motor_status,
       sensor_state: state.door_sensor,
       controller_state: state.status,
       activity_log: [
         %{actor: "🧠", time: current_time(), msg: "LiveView Connected."}
       ]
     )}
  end

  @impl true
  @spec handle_info({:elevator_state, Elevator.State.t()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:elevator_state, state}, socket) do
    # Visual updates only (Log is now handled by telemetry)
    {:noreply,
     socket
     |> assign(
       current_floor: state.current_floor,
       is_moving: state.motor_status == :running,
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
    # Append to the end and keep the last 20 entries
    {:noreply,
     update(socket, :activity_log, fn logs ->
       Enum.take(logs ++ [entry], -20)
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
    # Commands find the :controller via discovery automatically in the API
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
        <!-- LEFT PANEL (SHAFT & CONSOLE) -->
        <div class="left-panel">
          <div class="shaft-container">
            <div class="floor-labels">
              <div>5</div>
              <div>4</div>
              <div>3</div>
              <div>2</div>
              <div>1</div>
              <div>0</div>
            </div>

            <div class="shaft-visualization">
              <%= if @controller_state == :rehoming do %>
                <div class="rehoming-banner">REHOMING</div>
              <% end %>
              <div id="indicator" class="elevator-indicator">
                <%= if @current_floor == :unknown, do: "--", else: @current_floor %>
              </div>
              <div class="shaft-diagram">
                <!-- Decorative floor slots -->
                <.floor_slot :for={floor <- 5..0//-1} floor={floor} active={@current_floor == floor} />

                <!-- The Elevator Car -->
                <.elevator_car floor={@current_floor} door_state={@door_state} />
              </div>
            </div>
          </div>

          <div class="button-console">
            <%= for floor <- [5, 4, 3, 2, 1, 0] do %>
              <div
                class="console-button"
                phx-click="request_floor"
                phx-value-floor={floor}
              >
                <%= floor %>
              </div>
            <% end %>

            <div class="special-buttons">
              <div
                class="console-button"
                style="width:40px; height:40px; font-size: 0.8rem;"
                phx-click="open_door"
              >
                &lt;|&gt;
              </div>
              <div
                class="console-button"
                style="width:40px; height:40px; font-size: 0.8rem;"
                phx-click="close_door"
              >
                &gt;|&lt;
              </div>
            </div>
          </div>
        </div>

        <!-- RIGHT PANEL (ACTIVITY LOG) -->
        <div class="right-panel">
          <h3 class="log-header">ACTIVITY LOG</h3>
          <div id="log" class="activity-log" phx-hook="LogScroll">
            <%= for entry <- @activity_log do %>
              <div class="log-entry">
                <span><%= entry.actor %></span> [<%= entry.time %>] <%= entry.msg %>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- FOOTER (Live Actor Status) -->
      <div class="status-footer">
        <.status_box icon="🧠" label="Controller" state={@controller_state} />
        <.status_box icon="⚙️" label="Motor" state={@motor_state} />
        <.status_box icon="🚪" label="Door" state={@door_state} />
        <.status_box icon="👁️" label="Sensor" state={@sensor_state} />
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  @spec current_time() :: String.t()
  defp current_time do
    Time.utc_now() |> Time.to_string() |> String.slice(0, 8)
  end
end
