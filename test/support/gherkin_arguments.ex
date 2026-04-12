defmodule Elevator.Gherkin.Arguments do
  @moduledoc """
  Robust parsing and validation of Gherkin step arguments.
  Translates human-readable test vectors (e.g., "ground", "up") into Elixir data types.
  """

  @doc """
  Parses a floor argument from Gherkin text to an integer.
  Supports: "ground", "base", "F[n]", and numeric strings.
  Raises `ArgumentError` with a helpful message on failure.
  """
  def parse_floor(val) when is_integer(val), do: val

  def parse_floor(val) when val in [":unknown", "unknown", "UNKNOWN"], do: :unknown
  def parse_floor(val) when val in [nil, ""],
    do: raise(ArgumentError, "Floor argument is missing or empty.")
  def parse_floor(val) when val in ["GROUND", "Ground", "ground", ":ground "], do: 0
  def parse_floor(val) when val in ["BASE", "Base", "base", ":base"], do: 0
  def parse_floor("F" <> n), do: String.to_integer(n)

  def parse_floor(n) when is_binary(n) do
    case Integer.parse(n) do
      {num, _} ->
        num

      :error ->
        raise ArgumentError,
              "Invalid floor format: #{inspect(n)}. Expected 'ground', 'base', 'F<n>', or a numeric string (e.g., '3')."
    end
  end

  @doc """
  Parses a heading argument from Gherkin text to an atom.
  Supports: "up", "down", "idle".
  Raises `ArgumentError` on failure.
  """
  def parse_heading(val) when val in ["up", "UP", "Up", ":up"], do: :up
  def parse_heading(val) when val in ["down", "DOWN", "Down", ":down"], do: :down
  def parse_heading(val) when val in ["idle", "IDLE", "Idle", ":idle"], do: :idle

  def parse_heading(val) do
    raise ArgumentError,
          "Invalid heading: #{inspect(val)}. Expected 'up', 'down', or 'idle'."
  end

  @valid_phases [:booting, :idle, :moving, :arriving, :docked, :leaving, :rehoming]

  @doc """
  Parses a phase argument from Gherkin text to an atom.
  Validates against the allowed FICS core phases.
  Supports leading colons (e.g., ":booting", "booting").
  """
  def parse_phase(val) when is_binary(val) do
    phase = val |> String.trim_leading(":") |> String.downcase() |> String.to_atom()
    if phase in @valid_phases do
      phase
    else
      raise ArgumentError, "Invalid phase: #{inspect(val)}. Expected one of: #{inspect(@valid_phases)}"
    end
  end

  @doc """
  Parses a generic event argument from Gherkin text to an atom.
  """
  def parse_event(val) when is_binary(val) do
    val |> String.trim_leading(":") |> String.downcase() |> String.to_atom()
  end

  @valid_motor_statuses [:stopped, :running, :stopping, :crawling]

  @doc """
  Parses a motor status argument from Gherkin text to an atom.
  """
  def parse_motor_status(val) when is_binary(val) do
    status = val |> String.trim_leading(":") |> String.downcase() |> String.to_atom()
    if status in @valid_motor_statuses do
      status
    else
      raise ArgumentError, "Invalid motor status: #{inspect(val)}. Expected one of: #{inspect(@valid_motor_statuses)}"
    end
  end

  @valid_door_statuses [:closed, :opening, :open, :closing, :obstructed]

  @doc """
  Parses a door status argument from Gherkin text to an atom.
  """
  def parse_door_status(val) when is_binary(val) do
    status = val |> String.trim_leading(":") |> String.downcase() |> String.to_atom()
    if status in @valid_door_statuses do
      status
    else
      raise ArgumentError, "Invalid door status: #{inspect(val)}. Expected one of: #{inspect(@valid_door_statuses)}"
    end
  end

  @doc """
  Parses a button argument from Gherkin text to an atom.
  Supports leading colons (e.g., ":door_open", "door_open").
  """
  def parse_button(val) when is_binary(val) do
    val |> String.trim_leading(":") |> String.to_atom()
  end

  @doc """
  Parses a request source from Gherkin text to an atom.
  Supports: "car", "hall".
  Raises `ArgumentError` on failure.
  """
  def parse_source(val) when val in ["car", "CAR", "Car", ":car"], do: :car
  def parse_source(val) when val in ["hall", "HALL", "Hall", ":hall"], do: :hall

  def parse_source(val) do
    raise ArgumentError,
          "Invalid source: #{inspect(val)}. Expected 'car' or 'hall'."
  end

  @doc """
  Parses a comma-separated list of values using the provided parser function.
  Example: parse_list("1, 2, 3", &parse_floor/1) -> [1, 2, 3]
  """
  def parse_list(val, _parser_fn) when val in ["empty", "EMPTY", "Empty"], do: []

  def parse_list(val, parser_fn) when is_binary(val) do
    val
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(parser_fn)
  end
end
