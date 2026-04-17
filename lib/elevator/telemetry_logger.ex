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
        Logger.debug("🔍: #{inspect(%{event: name, data: metadata})}")
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
      [:elevator, :controller, :idle],
      [:elevator, :controller, :decision],
      [:elevator, :hardware, :motor, :move],
      [:elevator, :hardware, :motor, :stop],
      [:elevator, :hardware, :motor, :pulse],
      [:elevator, :hardware, :door, :open],
      [:elevator, :hardware, :door, :close],
      [:elevator, :hardware, :door, :state_change],
      [:elevator, :hardware, :door, :transit_complete],
      [:elevator, :hardware, :door, :obstruction],
      [:elevator, :hardware, :door, :unexpected_message],
      [:elevator, :hardware, :sensor, :arrival],
      [:elevator, :vault, :update]
    ]
  end

  @doc false
  def handle_event([:elevator, :controller, :request], _measurements, metadata, _config) do
    floor = Map.get(metadata, :floor, "???")
    log_and_broadcast("🧠", "Controller: Floor #{floor} requested")
  end

  def handle_event([:elevator, :controller, :arrival], _measurements, metadata, _config) do
    floor = Map.get(metadata, :floor, "???")
    suffix = if Map.get(metadata, :was_rehoming), do: " (Rehoming Complete)", else: ""
    log_and_broadcast("🧠", "Controller: Arrived at Floor #{floor}#{suffix}")
  end

  def handle_event([:elevator, :controller, :rehoming], _measurements, _metadata, _config) do
    log_and_broadcast("🧠", "Controller: REHOMING")
  end

  def handle_event([:elevator, :controller, :idle], _measurements, metadata, _config) do
    if floor = Map.get(metadata, :floor) do
      log_and_broadcast("🧠", "Controller: Recovery at Floor #{floor}")
    else
      log_and_broadcast("🧠", "Controller: IDLE")
    end
  end

  def handle_event([:elevator, :controller, :decision], _measurements, metadata, _config) do
    target = Map.get(metadata, :target, :unknown)
    status = Map.get(metadata, :status, :unknown)
    reason = Map.get(metadata, :reason)

    msg =
      case {target, status, reason} do
        {:door, :closed, :waiting_for_stop} ->
          "Controller: Holding Doors CLOSED (Waiting for Motor Stop)"

        {:motor, :stopped, :waiting_for_door} ->
          "Controller: Holding Motor STOPPED (Waiting for Doors to Close)"

        {:motor, :stopping, _} ->
          "Controller: Motor STOP requested"

        {:motor, :running, _} ->
          "Controller: Motor START requested"

        {:door, :opening, _} ->
          "Controller: Door OPEN requested"

        {:door, :closing, _} ->
          "Controller: Door CLOSE requested"

        _ ->
          "Controller: #{inspect(target)} -> #{inspect(status)}"
      end

    log_and_broadcast("🧠", msg)
  end

  def handle_event([:elevator, :hardware, :motor, :move], _measurements, metadata, _config) do
    direction = Map.get(metadata, :direction, :unknown)
    speed = Map.get(metadata, :speed, :running)
    log_and_broadcast("⚙️", "Motor: Moving #{direction} at #{speed} speed.")
  end

  def handle_event([:elevator, :hardware, :motor, :stop], _measurements, metadata, _config) do
    if Map.get(metadata, :redundant) do
      status = Map.get(metadata, :status, :unknown)
      log_and_broadcast("⚙️", "Motor: Redundant Stop ignored (already #{status})")
    else
      log_and_broadcast("⚙️", "Motor: Stopped.")
    end
  end

  def handle_event([:elevator, :hardware, :motor, :pulse], _measurements, _metadata, _config) do
    # Usually silent, but useful for deep hardware debugging
    :ok
  end

  def handle_event([:elevator, :hardware, :door, :open], _measurements, metadata, _config) do
    if Map.get(metadata, :redundant) do
      status = Map.get(metadata, :status, :unknown)
      log_and_broadcast("🚪", "Door: Redundant Open ignored (already #{status})")
    else
      log_and_broadcast("🚪", "Door: Opening...")
    end
  end

  def handle_event([:elevator, :hardware, :door, :close], _measurements, metadata, _config) do
    if Map.get(metadata, :redundant) do
      status = Map.get(metadata, :status, :unknown)
      log_and_broadcast("🚪", "Door: Redundant Close ignored (already #{status})")
    else
      log_and_broadcast("🚪", "Door: Closing...")
    end
  end

  def handle_event([:elevator, :hardware, :door, :state_change], _measurements, metadata, _config) do
    case Map.get(metadata, :status) do
      :obstructed -> log_and_broadcast("🚪", "Door: OBSTRUCTED (Safety Interrupt)")
      _ -> :ok
    end
  end

  def handle_event(
        [:elevator, :hardware, :door, :transit_complete],
        _measurements,
        metadata,
        _config
      ) do
    result = Map.get(metadata, :result, :unknown)
    log_and_broadcast("🚪", "Door: Fully #{result}.")
  end

  def handle_event([:elevator, :hardware, :door, :obstruction], _measurements, _metadata, _config) do
    log_and_broadcast("🚪", "Door: Obstruction Detected!")
  end

  def handle_event(
        [:elevator, :hardware, :door, :unexpected_message],
        _measurements,
        metadata,
        _config
      ) do
    msg = Map.get(metadata, :message)
    log_and_broadcast("🚪", "Door: Unexpected Message: #{inspect(msg)}")
  end

  def handle_event([:elevator, :hardware, :sensor, :arrival], _measurements, metadata, _config) do
    floor = Map.get(metadata, :floor, "???")
    log_and_broadcast("👁️", "Sensor: at Floor #{floor}")
  end

  def handle_event([:elevator, :vault, :update], _measurements, _metadata, _config) do
    # Internal persistence log
    :ok
  end

  defp log_and_broadcast(actor, msg) do
    timestamp = current_time()
    Logger.info(msg)

    # Broadcast to Visual Dashboard
    Phoenix.PubSub.broadcast(
      Elevator.PubSub,
      "elevator:telemetry",
      {:telemetry_event,
       %{
         actor: actor,
         time: timestamp,
         msg: msg
       }}
    )
  end

  defp current_time do
    Time.utc_now() |> Time.to_string() |> String.slice(0, 8)
  end
end
