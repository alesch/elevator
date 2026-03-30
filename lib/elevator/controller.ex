defmodule Elevator.Controller do
  @moduledoc """
  The Imperative Shell for the Elevator.
  Handles concurrency, state persistence, and timer-based behavior.
  """
  use GenServer
  require Logger
  alias Elevator.State

  @default_return_to_base_ms 300_000 # 5 minutes

  # ---------------------------------------------------------------------------
  # ## Client API
  # ---------------------------------------------------------------------------

  @doc "Starts a new elevator controller process."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Adds a floor request asynchronously."
  def request_floor(pid \\ __MODULE__, source, floor) do
    GenServer.cast(pid, {:request_floor, source, floor})
  end

  @doc "Fetches the current state snapshot."
  def get_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_state)
  end

  @doc "Fetches the internal timer reference (Diagnostics only)."
  def get_timer_ref(pid \\ __MODULE__) do
    GenServer.call(pid, :get_timer_ref)
  end

  # ---------------------------------------------------------------------------
  # ## Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    timer_ms = Keyword.get(opts, :timer_ms, @default_return_to_base_ms)
    motor = Keyword.get(opts, :motor)
    door = Keyword.get(opts, :door)
    sensor = Keyword.get(opts, :sensor)
    vault = Keyword.get(opts, :vault, Elevator.Vault)

    data = %{
      state: build_initial_state(opts),
      timer_ms: timer_ms,
      timer: schedule_return_to_base(timer_ms),
      motor: motor,
      door: door,
      sensor: sensor,
      vault: vault
    }

    {:ok, data, {:continue, :homing_check}}
  end

  @impl true
  def handle_cast({:request_floor, source, floor}, %{state: %{status: :rehoming}} = data) do
    Logger.warning("Ignoring request #{inspect(source)} to floor #{floor} during REHOMING")
    {:noreply, data}
  end

  @impl true
  def handle_cast({:request_floor, source, floor}, data) do
    new_data =
      data
      |> update_core_state(source, floor)
      |> sync_physical_limbs()
      |> reset_inactivity_timer()

    {:noreply, new_data}
  end

  @impl true
  def handle_continue(:homing_check, data) do
    vault_floor = Elevator.Vault.get_floor(data.vault)
    sensor_floor = Elevator.Sensor.get_floor(data.sensor)

    cond do
      # CASE 1: Perfect agreement (Zero-move recovery)
      vault_floor == sensor_floor and vault_floor != nil ->
        Logger.info("Controller: Standard Recovery at Floor #{vault_floor}")
        {:noreply, %{data | state: %{data.state | current_floor: vault_floor, status: :normal}}}

      # CASE 2: Ambiguity or Cold Start (Perform physical homing)
      true ->
        Logger.info("Controller: Entering REHOMING mode. Moving :down at :slow speed.")
        new_state = %{data.state | status: :rehoming}
        # Manual move :down at :slow speed
        Elevator.Motor.move(data.motor, :down, speed: :slow)
        Elevator.Door.close(data.door)
        {:noreply, %{data | state: new_state}}
    end
  end

  @impl true
  def handle_info({:floor_arrival, floor}, data) do
    # 1. Persist the arrival to the Vault
    Elevator.Vault.put_floor(data.vault, floor)

    # 2. Update functional state
    # If we were rehoming, we are now NORMAL
    new_status = if data.state.status == :rehoming, do: :normal, else: data.state.status
    new_state = %{data.state | current_floor: floor, status: new_status}

    new_data =
      %{data | state: new_state}
      |> sync_physical_limbs()
      |> reset_inactivity_timer()

    {:noreply, new_data}
  end

  @impl true
  def handle_info(:door_opened, data) do
    # Placeholder for potential door-stay-open timer
    {:noreply, data}
  end

  @impl true
  def handle_info(:door_closed, data) do
    # Logic for re-evaluating moves after a door closes
    {:noreply, data}
  end

  @impl true
  def handle_info(:door_obstructed, data) do
    # Critical safety alert
    {:noreply, data}
  end

  @impl true
  def handle_info(:return_to_base, data) do
    new_data =
      data
      |> update_core_state(:hall, 1)
      |> sync_physical_limbs()
      |> reset_inactivity_timer()

    {:noreply, new_data}
  end

  @impl true
  def handle_call(:get_state, _from, data) do
    {:reply, data.state, data}
  end

  @impl true
  def handle_call(:get_timer_ref, _from, data) do
    {:reply, data.timer, data}
  end

  # ---------------------------------------------------------------------------
  # ## Private Helpers
  # ---------------------------------------------------------------------------

  defp build_initial_state(opts) do
    opts
    |> create_base_state()
    |> position_at_provided_floor(opts)
  end

  defp create_base_state(opts) do
    case Keyword.get(opts, :type, :passenger) do
      :freight -> State.new_freight()
      _ -> State.new_passenger()
    end
  end

  defp position_at_provided_floor(state, opts) do
    if floor = Keyword.get(opts, :current_floor) do
      %{state | current_floor: floor}
    else
      state
    end
  end

  defp update_core_state(data, source, floor) do
    %{data | state: State.request_floor(data.state, source, floor)}
  end

  defp sync_physical_limbs(%{motor: motor, door: door} = data) do
    # Determine the physical command based on the functional state
    case data.state.heading do
      :idle ->
        Elevator.Motor.stop(motor)
        Elevator.Door.open(door)

      direction ->
        Elevator.Motor.move(motor, direction)
        Elevator.Door.close(door)
    end

    data
  end

  defp reset_inactivity_timer(%{timer: timer, timer_ms: ms} = data) do
    Process.cancel_timer(timer)
    %{data | timer: schedule_return_to_base(ms)}
  end

  defp schedule_return_to_base(ms) do
    Process.send_after(self(), :return_to_base, ms)
  end
end
