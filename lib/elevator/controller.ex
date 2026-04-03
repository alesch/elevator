defmodule Elevator.Controller do
  @moduledoc """
  The Imperative Shell for the Elevator.
  Handles concurrency, state persistence, and discovery-based behavior.
  """
  use GenServer
  require Logger
  alias Elevator.Core
  alias Elevator.Hardware

  # 5 minutes
  @default_return_to_base_ms 300_000

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @doc "Starts a new elevator controller process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Adds a floor request asynchronously."
  @spec request_floor(pid() | atom(), atom(), integer()) :: :ok
  def request_floor(pid \\ __MODULE__, source, floor) do
    GenServer.cast(pid, {:request_floor, source, floor})
  end

  @doc "Triggers a manual door opening command."
  @spec open_door(pid() | atom()) :: :ok
  def open_door(pid \\ __MODULE__) do
    GenServer.cast(pid, :manual_open_door)
  end

  @doc "Triggers a manual door closing command."
  @spec close_door(pid() | atom()) :: :ok
  def close_door(pid \\ __MODULE__) do
    GenServer.cast(pid, :manual_close_door)
  end

  @doc "Fetches the current state snapshot."
  @spec get_state(pid() | atom()) :: Elevator.Core.t()
  def get_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_state)
  end

  @doc "Fetches the internal timer reference (Diagnostics only)."
  @spec get_timer_ref(pid() | atom()) :: reference() | nil
  def get_timer_ref(pid \\ __MODULE__) do
    GenServer.call(pid, :get_timer_ref)
  end

  # ---------------------------------------------------------------------------
  # ## Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, map(), {:continue, :homing_check}}
  def init(opts) do
    # Register brain only if it's a named process (Supervisor/Production)
    if Keyword.get(opts, :name) != nil do
      {:ok, _} = Registry.register(Elevator.Registry, :controller, nil)
    end

    timer_ms = Keyword.get(opts, :timer_ms, @default_return_to_base_ms)

    data = %{
      state: build_initial_state(opts),
      timer_ms: timer_ms,
      timer: schedule_return_to_base(timer_ms),
      deps: %{
        motor: Keyword.get(opts, :motor),
        door: Keyword.get(opts, :door),
        sensor: Keyword.get(opts, :sensor),
        vault: Keyword.get(opts, :vault)
      }
    }

    {:ok, data, {:continue, :homing_check}}
  end

  @impl true
  @spec handle_continue(:homing_check, map()) :: {:noreply, map()}
  def handle_continue(:homing_check, data) do
    vault_floor = lookup_hardware(data, :vault, &Elevator.Vault.get_floor/1)
    sensor_floor = lookup_hardware(data, :sensor, &Hardware.Sensor.get_floor/1)

    if vault_floor == sensor_floor and vault_floor != nil do
      # CASE 1: Perfect agreement (Zero-move recovery)
      :telemetry.execute([:elevator, :controller, :recovery], %{}, %{floor: vault_floor})
      {new_state, actions} = Core.handle_event(data.state, :recovery_complete, vault_floor)

      new_data =
        %{data | state: new_state}
        |> execute_actions(actions)

      broadcast_state(new_data.state)
      {:noreply, new_data}
    else
      # CASE 2: Ambiguity or Cold Start (Perform physical homing)
      :telemetry.execute([:elevator, :controller, :rehoming], %{}, %{
        direction: :down,
        speed: :slow
      })

      {new_state, actions} = Core.handle_event(data.state, :rehoming_started, nil)

      new_data =
        %{data | state: new_state}
        |> execute_actions(actions)

      broadcast_state(new_data.state)
      {:noreply, new_data}
    end
  end

  @impl true
  @spec handle_cast({:request_floor, atom(), integer()}, map()) :: {:noreply, map()}
  def handle_cast({:request_floor, source, floor}, %{state: %{status: :rehoming}} = data) do
    Logger.warning("Ignoring request #{inspect(source)} to floor #{floor} during REHOMING")
    {:noreply, data}
  end

  def handle_cast({:request_floor, source, floor}, data) do
    # SILENT IDEMPOTENCY:
    # 1. We ignore if it's already in the queue.
    # 2. We ignore if we are at the floor AND the door is already opening/open.
    already_queued? = Enum.any?(data.state.requests, fn {_, f} -> f == floor end)

    already_satisfied? =
      data.state.current_floor == floor and data.state.door_status in [:open, :opening]

    if already_queued? or already_satisfied? do
      # Silent ignore for external inputs
      {:noreply, data}
    else
      :telemetry.execute([:elevator, :controller, :request], %{}, %{source: source, floor: floor})

      {new_state, actions} = Core.request_floor(data.state, source, floor)

      new_data =
        %{data | state: new_state}
        |> execute_actions(actions)
        |> broadcast_and_reset_timer()

      {:noreply, new_data}
    end
  end

  @impl true
  @spec handle_cast(:manual_open_door, map()) :: {:noreply, map()}
  def handle_cast(:manual_open_door, data) do
    now = System.system_time(:millisecond)
    {new_state, actions} = Core.handle_button_press(data.state, :door_open, now)

    new_data =
      %{data | state: new_state}
      |> execute_actions(actions)
      |> broadcast_and_reset_timer()

    {:noreply, new_data}
  end

  @impl true
  @spec handle_cast(:manual_close_door, map()) :: {:noreply, map()}
  def handle_cast(:manual_close_door, data) do
    now = System.system_time(:millisecond)
    {new_state, actions} = Core.handle_button_press(data.state, :door_close, now)

    new_data =
      %{data | state: new_state}
      |> execute_actions(actions)
      |> broadcast_and_reset_timer()

    {:noreply, new_data}
  end

  @impl true
  @spec handle_info({:floor_arrival, integer()}, map()) :: {:noreply, map()}
  def handle_info({:floor_arrival, floor}, data) do
    # 1. Persist the arrival
    lookup_hardware(data, :vault, &Elevator.Vault.put_floor(&1, floor))

    # 2. Update functional state
    was_rehoming? = data.state.status == :rehoming
    new_status = if was_rehoming?, do: :normal, else: data.state.status

    :telemetry.execute([:elevator, :controller, :arrival], %{}, %{
      floor: floor,
      was_rehoming: was_rehoming?
    })

    # Intermediate state to handle manual rehoming logic override
    # (In a real system, the Brain would handle this internally)
    {mid_state, _} = Core.process_arrival(%{data.state | status: new_status}, floor)
    final_heading = if was_rehoming?, do: :idle, else: mid_state.heading

    {final_state, actions} = Core.process_arrival(%{data.state | status: new_status, heading: final_heading}, floor)

    new_data =
      %{data | state: final_state}
      |> execute_actions(actions)
      |> broadcast_and_reset_timer()

    {:noreply, new_data}
  end

  @impl true
  @spec handle_info(:door_opened, data :: map()) :: {:noreply, map()}
  def handle_info(:door_opened, data) do
    now = System.system_time(:millisecond)
    {new_state, actions} = Core.handle_event(data.state, :door_opened, now)

    new_data =
      %{data | state: new_state}
      |> execute_actions(actions)
      |> broadcast_and_reset_timer()

    {:noreply, new_data}
  end

  @impl true
  @spec handle_info(:door_closed, map()) :: {:noreply, map()}
  def handle_info(:door_closed, data) do
    {new_state, actions} = Core.handle_event(data.state, :door_closed, nil)

    new_data =
      %{data | state: new_state}
      |> execute_actions(actions)
      |> broadcast_and_reset_timer()

    {:noreply, new_data}
  end

  @impl true
  @spec handle_info(:motor_stopped, map()) :: {:noreply, map()}
  def handle_info(:motor_stopped, data) do
    {new_state, actions} = Core.handle_event(data.state, :motor_stopped, nil)

    new_data =
      %{data | state: new_state}
      |> execute_actions(actions)
      |> broadcast_and_reset_timer()

    {:noreply, new_data}
  end

  @impl true
  @spec handle_info(:door_obstructed, map()) :: {:noreply, map()}
  def handle_info(:door_obstructed, data) do
    {new_state, actions} = Core.handle_event(data.state, :door_obstructed, nil)

    new_data =
      %{data | state: new_state}
      |> execute_actions(actions)
      |> broadcast_and_reset_timer()

    {:noreply, new_data}
  end

  @impl true
  @spec handle_info(:door_cleared, map()) :: {:noreply, map()}
  def handle_info(:door_cleared, data) do
    {new_state, actions} = Core.handle_event(data.state, :door_cleared, nil)

    new_data =
      %{data | state: new_state}
      |> execute_actions(actions)
      |> broadcast_and_reset_timer()

    {:noreply, new_data}
  end

  @impl true
  @spec handle_info({:timeout, atom()}, map()) :: {:noreply, map()}
  def handle_info({:timeout, id}, data) do
    Logger.info("Controller: Timer expired for #{id}")
    now = System.system_time(:millisecond)
    {new_state, actions} = Core.handle_event(data.state, id, now)

    new_data =
      %{data | state: new_state}
      |> execute_actions(actions)
      |> broadcast_and_reset_timer()

    {:noreply, new_data}
  end

  @impl true
  @spec handle_info(:return_to_base, map()) :: {:noreply, map()}
  def handle_info(:return_to_base, data) do
    {new_state, actions} = Core.request_floor(data.state, :hall, 1)

    new_data =
      %{data | state: new_state}
      |> execute_actions(actions)
      |> broadcast_and_reset_timer()

    {:noreply, new_data}
  end

  @impl true
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info(msg, state) do
    Logger.warning("Controller: Unexpected message #{inspect(msg)} in state: #{inspect(state)}")
    {:noreply, state}
  end

  @impl true
  @spec handle_call(:get_state, GenServer.from(), map()) :: {:reply, Elevator.Core.t(), map()}
  def handle_call(:get_state, _from, data) do
    {:reply, data.state, data}
  end

  @impl true
  @spec handle_call(:get_timer_ref, GenServer.from(), map()) :: {:reply, reference() | nil, map()}
  def handle_call(:get_timer_ref, _from, data) do
    {:reply, data.timer, data}
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  @spec execute_actions(map(), [Core.action()]) :: map()
  defp execute_actions(data, actions) do
    if actions != [], do: Logger.info("Controller executing actions: #{inspect(actions)}")
    Enum.reduce(actions, data, fn action, acc ->
      case action do
        {:move_motor, dir, speed} ->
          lookup_hardware(acc, :motor, &Hardware.Motor.move(&1, dir, speed: speed))
          acc

        {:stop_motor} ->
          lookup_hardware(acc, :motor, &Hardware.Motor.stop/1)
          acc

        {:open_door} ->
          lookup_hardware(acc, :door, &Hardware.Door.open/1)
          acc

        {:close_door} ->
          lookup_hardware(acc, :door, &Hardware.Door.close/1)
          acc

        {:set_timer, id, ms} ->
          Process.send_after(self(), {:timeout, id}, ms)
          acc

        {:cancel_timer, _id} ->
          # MVP uses process mailboxes as queues; cancellation is not strictly required
          # if the Brain is idempotent to late timeouts.
          acc
      end
    end)
  end

  defp broadcast_and_reset_timer(data) do
    broadcast_state(data.state)
    reset_inactivity_timer(data)
  end

  @spec broadcast_state(Elevator.Core.t()) :: :ok | {:error, term()}
  defp broadcast_state(state) do
    Phoenix.PubSub.broadcast(Elevator.PubSub, "elevator:status", {:elevator_state, state})
  end

  @spec build_initial_state(keyword()) :: Elevator.Core.t()
  defp build_initial_state(opts) do
    opts
    |> create_base_state()
    |> position_at_provided_floor(opts)
  end

  @spec create_base_state(keyword()) :: Elevator.Core.t()
  defp create_base_state(opts) do
    case Keyword.get(opts, :type, :passenger) do
      :freight -> Core.new_freight()
      _ -> Core.new_passenger()
    end
  end

  @spec position_at_provided_floor(Core.t(), keyword()) :: Core.t()
  defp position_at_provided_floor(state, opts) do
    if floor = Keyword.get(opts, :current_floor) do
      %{state | current_floor: floor}
    else
      state
    end
  end

  # Dispatch logic: Priority to explicit deps (Test Way) -> Discovery (Industrial Way)
  @spec lookup_hardware(map(), atom(), (pid() -> term())) :: term()
  defp lookup_hardware(data, key, func) do
    target = Map.get(data.deps, key) || registry_lookup(key)
    if target, do: func.(target), else: log_hardware_failure(key)
  end

  defp registry_lookup(key) do
    case Registry.lookup(Elevator.Registry, key) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end

  defp log_hardware_failure(key) do
    Logger.warning("Hardware Link Failure: No :#{key} found via injection or registry.")
    nil
  end

  @spec reset_inactivity_timer(map()) :: map()
  defp reset_inactivity_timer(%{timer: timer, timer_ms: ms} = data) do
    if timer, do: Process.cancel_timer(timer)
    %{data | timer: schedule_return_to_base(ms)}
  end

  @spec schedule_return_to_base(integer()) :: reference()
  defp schedule_return_to_base(ms) do
    Process.send_after(self(), :return_to_base, ms)
  end
end
