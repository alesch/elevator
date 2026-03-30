defmodule Elevator.Motor do
  @moduledoc """
  The 'Dumb Muscle' of the system.
  It pulls cables indefinitely until told to stop.
  """
  use GenServer

  @transit_ms 2000 # 2 seconds per floor

  # --- API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Starts pulling cables in the specified direction."
  def move(pid \\ __MODULE__, direction, opts \\ []) when direction in [:up, :down] do
    GenServer.cast(pid, {:move, direction, opts})
  end

  @doc "Stops all motion immediately."
  def stop(pid \\ __MODULE__) do
    GenServer.cast(pid, :stop_now)
  end

  @doc "Peeks at the internal state (Diagnostics)."
  def get_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_state)
  end

  # --- Callbacks ---

  def init(opts) do
    sensor = Keyword.get(opts, :sensor)
    {:ok, %{status: :stopped, direction: nil, speed: :normal, timer: nil, sensor: sensor}}
  end

  def handle_cast({:move, direction, opts}, state) do
    speed = Keyword.get(opts, :speed, :normal)

    state = state
            |> cancel_timer()
            |> update_motion_state(:moving, direction, speed)
            |> start_transit_timer()

    {:noreply, state}
  end

  def handle_cast(:stop_now, state) do
    state = state
            |> cancel_timer()
            |> update_motion_state(:stopped, nil, :normal)

    {:noreply, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_info({:pulse, _direction}, state) do
    # Notify the Sensor (Nervous System) that a physical unit has been traversed
    notify_sensor(state, state.direction)

    # Schedule the next pulse (Keep spinning at current speed)
    {:noreply, start_transit_timer(state)}
  end

  # --- Private Helpers ---

  defp update_motion_state(state, status, direction, speed) do
    %{state | status: status, direction: direction, speed: speed}
  end

  defp start_transit_timer(%{direction: direction, speed: speed} = state) do
    ms = case speed do
      :slow -> 5000
      _ -> @transit_ms
    end
    timer = Process.send_after(self(), {:pulse, direction}, ms)
    %{state | timer: timer}
  end

  defp cancel_timer(%{timer: nil} = state), do: state
  defp cancel_timer(%{timer: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timer: nil}
  end

  defp notify_sensor(%{sensor: nil}, _direction), do: :ok
  defp notify_sensor(%{sensor: sensor}, direction) do
    # Message: {:motor_pulse, direction}
    send(sensor, {:motor_pulse, direction})
  end
end
