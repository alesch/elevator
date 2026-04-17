defmodule Elevator.Controller do
  @moduledoc """
  The Imperative Shell for the Elevator.
  Handles concurrency, state persistence, and discovery-based behavior.
  """
  use GenServer
  alias Elevator.Core
  alias Elevator.Hardware
  alias __MODULE__, as: Controller

  @type deps :: %{
          optional(:sensor) => pid() | atom(),
          optional(:vault) => pid() | atom()
        }

  @type t :: %{
          state: Elevator.Core.t(),
          deps: deps(),
          timers: %{atom() => reference()}
        }

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @doc "Starts a new elevator controller process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, Controller)
    GenServer.start_link(Controller, opts, name: name)
  end

  @doc "Adds a floor request asynchronously."
  @spec request_floor(pid() | atom(), atom(), integer()) :: :ok
  def request_floor(pid \\ Controller, source, floor) do
    GenServer.cast(pid, {:request_floor, source, floor})
  end

  @doc "Triggers a manual door opening command."
  @spec open_door(pid() | atom()) :: :ok
  def open_door(pid \\ Controller) do
    GenServer.cast(pid, :manual_open_door)
  end

  @doc "Triggers a manual door closing command."
  @spec close_door(pid() | atom()) :: :ok
  def close_door(pid \\ Controller) do
    GenServer.cast(pid, :manual_close_door)
  end

  @doc "Fetches the current state snapshot."
  @spec get_state(pid() | atom()) :: Elevator.Core.t()
  def get_state(pid \\ Controller) do
    GenServer.call(pid, :get_state)
  end

  @doc "Fetches the internal timer reference (Diagnostics only)."
  @spec get_timer_ref(pid() | atom()) :: reference() | nil
  def get_timer_ref(pid \\ Controller) do
    GenServer.call(pid, :get_timer_ref)
  end

  @doc """
  Diagnostics: Resets the elevator to a clean state.
  Clears the vault and restarts the hardware stack.

  WARNING: This is a developer tool and should not be used in production flows.
  """
  @spec reset() :: :ok
  def reset do
    Elevator.Vault.put_floor(Elevator.Vault, 0)

    if pid = Process.whereis(Elevator.HardwareSupervisor) do
      Process.exit(pid, :kill)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # ## Server Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, t(), {:continue, :homing_check}}
  def init(opts) do
    # Register brain only if it's a named process (Supervisor/Production)
    if Keyword.get(opts, :name) != nil do
      {:ok, _} = Registry.register(Elevator.Registry, :controller, nil)
      Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:hardware")
    end

    data = %{
      state: Core.booting(),
      deps: %{
        sensor: Keyword.get(opts, :sensor),
        vault: Keyword.get(opts, :vault)
      },
      timers: %{}
    }

    {:ok, data, {:continue, :homing_check}}
  end

  @impl true
  @spec handle_continue(:homing_check, t()) :: {:noreply, t()}
  def handle_continue(:homing_check, data) do
    vault_floor = lookup_hardware(data, :vault, &Elevator.Vault.get_floor/1)
    sensor_floor = lookup_hardware(data, :sensor, &Hardware.Sensor.get_floor/1)

    data
    |> pulse_and_commit(
      :homing_check,
      %{},
      Core.handle_event(data.state, :startup_check, %{vault: vault_floor, sensor: sensor_floor})
    )
  end

  @impl true
  @spec handle_cast({:request_floor, atom(), integer()}, t()) :: {:noreply, t()}

  def handle_cast({:request_floor, source, floor}, data) do
    data
    |> pulse_and_commit(
      :request_floor,
      %{source: source, floor: floor},
      Core.request_floor(data.state, {source, floor})
    )
  end

  @impl true
  @spec handle_cast(:manual_open_door, t()) :: {:noreply, t()}
  def handle_cast(:manual_open_door, data) do
    now = System.system_time(:millisecond)

    data
    |> pulse_and_commit(
      :manual_open_door,
      %{},
      Core.handle_button_press(data.state, :door_open, now)
    )
  end

  @impl true
  @spec handle_cast(:manual_close_door, t()) :: {:noreply, t()}
  def handle_cast(:manual_close_door, data) do
    now = System.system_time(:millisecond)

    data
    |> pulse_and_commit(
      :manual_close_door,
      %{},
      Core.handle_button_press(data.state, :door_close, now)
    )
  end

  @impl true
  @spec handle_info({:floor_arrival, integer()}, t()) :: {:noreply, t()}
  def handle_info({:floor_arrival, floor}, data) do
    data
    |> pulse_and_commit(:floor_arrival, %{floor: floor}, Core.process_arrival(data.state, floor))
  end

  @impl true
  @spec handle_info(:door_opened, t()) :: {:noreply, t()}
  def handle_info(:door_opened, data) do
    now = System.system_time(:millisecond)

    data
    |> pulse_and_commit(:door_opened, %{}, Core.handle_event(data.state, :door_opened, now))
  end

  @impl true
  @spec handle_info(:door_closed, t()) :: {:noreply, t()}
  def handle_info(:door_closed, data) do
    data
    |> pulse_and_commit(:door_closed, %{}, Core.handle_event(data.state, :door_closed))
  end

  @impl true
  @spec handle_info(:door_opening, t()) :: {:noreply, t()}
  def handle_info(:door_opening, data) do
    data
    |> pulse_and_commit(:door_opening, %{}, Core.handle_event(data.state, :door_opening))
  end

  @impl true
  @spec handle_info(:door_closing, t()) :: {:noreply, t()}
  def handle_info(:door_closing, data) do
    data
    |> pulse_and_commit(:door_closing, %{}, Core.handle_event(data.state, :door_closing))
  end

  @impl true
  @spec handle_info(:motor_stopped, t()) :: {:noreply, t()}
  def handle_info(:motor_stopped, data) do
    data
    |> pulse_and_commit(:motor_stopped, %{}, Core.handle_event(data.state, :motor_stopped))
  end

  @impl true
  @spec handle_info({:motor_running, :up | :down}, t()) :: {:noreply, t()}
  def handle_info({:motor_running, _dir}, data) do
    data
    |> pulse_and_commit(:motor_running, %{}, Core.handle_event(data.state, :motor_running))
  end

  @impl true
  @spec handle_info({:motor_crawling, :up | :down}, t()) :: {:noreply, t()}
  def handle_info({:motor_crawling, _dir}, data) do
    data
    |> pulse_and_commit(:motor_crawling, %{}, Core.handle_event(data.state, :motor_crawling))
  end

  @impl true
  @spec handle_info(:door_obstructed, t()) :: {:noreply, t()}
  def handle_info(:door_obstructed, data) do
    data
    |> pulse_and_commit(:door_obstructed, %{}, Core.handle_event(data.state, :door_obstructed))
  end

  @impl true
  @spec handle_info(:door_cleared, t()) :: {:noreply, t()}
  def handle_info(:door_cleared, data) do
    data
    |> pulse_and_commit(:door_cleared, %{}, Core.handle_event(data.state, :door_cleared))
  end

  @impl true
  @spec handle_info({:timeout, atom()}, t()) :: {:noreply, t()}
  def handle_info({:timeout, id}, data) do
    :telemetry.execute([:elevator, :controller, :timer_expired], %{}, %{id: id})
    now = System.system_time(:millisecond)

    data
    |> pulse_and_commit(:timeout, %{id: id}, Core.handle_event(data.state, id, now))
  end

  @impl true
  @spec handle_info(term(), t()) :: {:noreply, t()}
  def handle_info(msg, state) do
    :telemetry.execute([:elevator, :controller, :unexpected_message], %{}, %{message: msg})
    {:noreply, state}
  end

  @impl true
  @spec handle_call(:get_state, GenServer.from(), t()) :: {:reply, Elevator.Core.t(), t()}
  def handle_call(:get_state, _from, data) do
    {:reply, data.state, data}
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  @spec execute_actions(t(), [Core.action()]) :: t()
  defp execute_actions(data, actions) do
    Enum.reduce(actions, data, &do_execute/2)
  end

  defp do_execute({:move, dir}, acc) do
    Phoenix.PubSub.broadcast_from(Elevator.PubSub, self(), "elevator:hardware", {:command, :move, dir})
    acc
  end

  defp do_execute({:crawl, dir}, acc) do
    Phoenix.PubSub.broadcast_from(Elevator.PubSub, self(), "elevator:hardware", {:command, :crawl, dir})
    acc
  end

  defp do_execute({:stop_motor}, acc) do
    Phoenix.PubSub.broadcast_from(Elevator.PubSub, self(), "elevator:hardware", {:command, :stop})
    acc
  end

  defp do_execute({:open_door}, acc) do
    Phoenix.PubSub.broadcast_from(Elevator.PubSub, self(), "elevator:hardware", {:command, :open})
    acc
  end

  defp do_execute({:close_door}, acc) do
    Phoenix.PubSub.broadcast_from(Elevator.PubSub, self(), "elevator:hardware", {:command, :close})
    acc
  end

  defp do_execute({:set_timer, id, ms}, acc) do
    if ref = acc.timers[id], do: Process.cancel_timer(ref)

    ref =
      lookup_hardware(acc, :time, &Elevator.Time.send_after(&1, self(), ms, {:timeout, id})) ||
        Process.send_after(self(), {:timeout, id}, ms)

    %{acc | timers: Map.put(acc.timers, id, ref)}
  end

  defp do_execute({:cancel_timer, id}, acc) do
    if ref = acc.timers[id], do: Process.cancel_timer(ref)
    %{acc | timers: Map.delete(acc.timers, id)}
  end

  defp do_execute({:persist_arrival, floor}, acc) do
    lookup_hardware(acc, :vault, &Elevator.Vault.put_floor(&1, floor))
    acc
  end

  defp do_execute(unknown, acc) do
    :telemetry.execute([:elevator, :controller, :unhandled_action], %{}, %{action: unknown})
    acc
  end

  @spec pulse_and_commit(t(), atom(), map(), {Core.t(), [Core.action()]}) :: {:noreply, t()}
  defp pulse_and_commit(data, event, metadata, {new_state, actions}) do
    :telemetry.execute([:elevator, :controller, :event], %{}, Map.put(metadata, :type, event))

    new_data =
      %{data | state: new_state}
      |> execute_actions(actions)

    broadcast_state(new_data.state)
    {:noreply, new_data}
  end

  @spec broadcast_state(Elevator.Core.t()) :: :ok | {:error, term()}
  defp broadcast_state(state) do
    Phoenix.PubSub.broadcast(Elevator.PubSub, "elevator:status", {:elevator_state, state})
  end

  # Dispatch logic: Priority to explicit deps (Test Way) -> Discovery (Industrial Way)
  # The 'deps' map is a Test Isolation Hook, allowing mocks to be injected
  # during parallel test runs where global names are avoided.
  @spec lookup_hardware(t(), atom(), (pid() | atom() -> term())) :: term()
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
    :telemetry.execute([:elevator, :controller, :hardware_failure], %{}, %{key: key})
    nil
  end
end
