defmodule Elevator.Door do
  @moduledoc """
  The 'Safety Boundary' of the system.
  A 5-state machine: :opening, :open, :closing, :closed, :obstructed.
  """
  use GenServer
  require Logger

  @op_ms 1000 # 1 second for opening/closing

  # --- API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Commands the door to start opening."
  def open(pid \\ __MODULE__) do
    GenServer.cast(pid, :open)
  end

  @doc "Commands the door to start closing."
  def close(pid \\ __MODULE__) do
    GenServer.cast(pid, :close)
  end

  @doc "Stops the door and enters a stable OBSTRUCTED state."
  def obstruct(pid \\ __MODULE__) do
    GenServer.cast(pid, :door_obstructed)
  end

  @doc "Peeks at the door state."
  def get_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_state)
  end

  # --- Callbacks ---

  def init(opts) do
    controller = Keyword.get(opts, :controller)
    {:ok, %{status: :closed, timer: nil, controller: controller}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast(:open, state) do
    state = state
            |> cancel_timer()
            |> start_timer(:fully_opened, @op_ms)
            |> update_status(:opening)

    {:noreply, state}
  end

  def handle_cast(:close, state) do
    state = state
            |> cancel_timer()
            |> start_timer(:fully_closed, @op_ms)
            |> update_status(:closing)

    {:noreply, state}
  end

  def handle_cast(:door_obstructed, state) do
    # If a safety sensor is hit, stop immediately and lock out
    state = state
            |> cancel_timer()
            |> update_status(:obstructed)

    notify_controller(state, :door_obstructed)

    {:noreply, state}
  end

  def handle_info(:fully_opened, state) do
    notify_controller(state, :door_opened)
    {:noreply, %{state | status: :open, timer: nil}}
  end

  def handle_info(:fully_closed, state) do
    notify_controller(state, :door_closed)
    {:noreply, %{state | status: :closed, timer: nil}}
  end

  # --- Private Helpers ---

  defp update_status(state, status) do
    Logger.info("Door: [State Change] Transitioned to #{status}")
    %{state | status: status}
  end

  defp start_timer(state, msg, ms) do
    timer = Process.send_after(self(), msg, ms)
    %{state | timer: timer}
  end

  defp cancel_timer(%{timer: nil} = state), do: state
  defp cancel_timer(%{timer: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timer: nil}
  end

  defp notify_controller(%{controller: nil}, _msg), do: :ok
  defp notify_controller(%{controller: controller}, msg) do
    # Messages: :door_opened, :door_closed, :door_obstructed
    send(controller, msg)
  end
end
