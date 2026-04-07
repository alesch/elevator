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
  def parse_floor("ground"), do: 0
  def parse_floor("base"), do: 0
  def parse_floor("F" <> n), do: String.to_integer(n)

  def parse_floor(n) when is_binary(n) do
    case Integer.parse(n) do
      {num, _} -> num
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
  def parse_heading(val) when val in ["up", "UP", ":up"], do: :up
  def parse_heading(val) when val in ["down", "DOWN", ":down"], do: :down
  def parse_heading(val) when val in ["idle", "IDLE", ":idle"], do: :idle

  def parse_heading(val) do
    raise ArgumentError,
          "Invalid heading: #{inspect(val)}. Expected 'up', 'down', or 'idle'."
  end
end
