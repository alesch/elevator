defmodule Elevator.TelemetryLogger do
  @moduledoc """
  The 'Voice' of the system.
  Listens for standardized :telemetry events and translates them into 
  professional, auditable console logs.
  """
  require Logger

  # ---------------------------------------------------------------------------
  # ## Public API
  # ---------------------------------------------------------------------------

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc "Attaches the telemetry handlers."
  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(_opts) do
    attach_handlers()
    # We return a dummy PID as this is a tracer, not a long-running process
    # but we want it in the supervision tree for lifecycle management.
    Task.start_link(fn -> Process.sleep(:infinity) end)
  end

  @doc """
  Shorthand for iex. Starts a live 'trace' of all elevator events, 
  printing raw metadata to STDOUT for high-fidelity debugging.
  """
  @spec trace() :: :ok
  def trace do
    :telemetry.attach_many(
      "iex-tracer",
      all_events(),
      fn name, _measurements, metadata, _config ->
        IO.inspect(%{event: name, data: metadata}, label: "🔍")
      end,
      nil
    )
  end

  @doc "Stops the live trace of elevator events."
  @spec untrace() :: :ok
  def untrace do
    :telemetry.detach("iex-tracer")
  end

  # ---------------------------------------------------------------------------
  # ## Internal Logic
  # ---------------------------------------------------------------------------

  defp attach_handlers do
    :telemetry.attach_many("elevator-logger", all_events(), &__MODULE__.handle_event/4, nil)
  end

  defp all_events do
    [
      [:elevator, :controller, :request],
      [:elevator, :controller, :arrival],
      [:elevator, :controller, :rehoming],
      [:elevator, :controller, :recovery],
      [:elevator, :hardware, :motor, :move],
      [:elevator, :hardware, :motor, :stop],
      [:elevator, :hardware, :motor, :pulse],
      [:elevator, :hardware, :safety, :door],
      [:elevator, :hardware, :sensor, :arrival],
      [:elevator, :vault, :update]
    ]
  end

  @doc false
  def handle_event([:elevator, :controller, :request], _measurements, metadata, _config) do
    floor = Map.get(metadata, :floor, "???")
    source = Map.get(metadata, :source, :unknown)
    log_and_broadcast("🧠", "Controller: [Request] Floor #{floor} from #{inspect(source)}")
  end

  def handle_event([:elevator, :controller, :arrival], _measurements, metadata, _config) do
    floor = Map.get(metadata, :floor, "???")
    suffix = if Map.get(metadata, :was_rehoming), do: " (Rehoming Complete)", else: ""
    log_and_broadcast("🧠", "Controller: [Arrival] Detected at Floor #{floor}#{suffix}")
  end

  def handle_event([:elevator, :controller, :rehoming], _measurements, metadata, _config) do
    direction = Map.get(metadata, :direction, :unknown)
    speed = Map.get(metadata, :speed, :normal)
    log_and_broadcast("🧠", "Controller: [Lifecycle] Entering REHOMING. Moving #{direction} at #{speed} speed.")
  end

  def handle_event([:elevator, :controller, :recovery], _measurements, metadata, _config) do
    floor = Map.get(metadata, :floor, "???")
    log_and_broadcast("🧠", "Controller: [Lifecycle] Standard Recovery at Floor #{floor}")
  end

  def handle_event([:elevator, :hardware, :motor, :move], _measurements, metadata, _config) do
    direction = Map.get(metadata, :direction, :unknown)
    speed = Map.get(metadata, :speed, :normal)
    log_and_broadcast("⚙️", "Motor: [Action] Moving #{direction} at #{speed} speed.")
  end

  def handle_event([:elevator, :hardware, :motor, :stop], _measurements, _metadata, _config) do
    log_and_broadcast("⚙️", "Motor: [Action] Stopping Now.")
  end

  def handle_event([:elevator, :hardware, :motor, :pulse], _measurements, _metadata, _config) do
    # Usually silent, but useful for deep hardware debugging
    :ok
  end

  def handle_event([:elevator, :hardware, :safety, :door], _measurements, metadata, _config) do
    status = Map.get(metadata, :status, :unknown)
    log_and_broadcast("🚪", "Door: [State Change] Transitioned to #{status}")
  end

  def handle_event([:elevator, :hardware, :sensor, :arrival], _measurements, metadata, _config) do
    floor = Map.get(metadata, :floor, "???")
    log_and_broadcast("👁️", "Sensor: [Box Arrival] Detected at Floor #{floor}")
  end

  def handle_event([:elevator, :vault, :update], _measurements, _metadata, _config) do
    # Internal persistence log
    :ok
  end

  defp log_and_broadcast(actor, msg) do
    timestamp = current_time()
    Logger.info(msg)

    # Broadcast to Visual Dashboard
    Phoenix.PubSub.broadcast(Elevator.PubSub, "elevator:telemetry", {:telemetry_event, %{
      actor: actor,
      time: timestamp,
      msg: msg
    }})
  end

  defp current_time do
    Time.utc_now() |> Time.to_string() |> String.slice(0, 8)
  end
end
