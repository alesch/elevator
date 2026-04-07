defmodule Elevator.Gherkin.ArgumentsTest do
  use ExUnit.Case, async: true
  alias Elevator.Gherkin.Arguments

  describe "parse_floor/1" do
    test "parses 'ground' as 0" do
      assert Arguments.parse_floor("ground") == 0
    end

    test "parses 'base' as 0" do
      assert Arguments.parse_floor("base") == 0
    end

    test "parses 'F' prefix numeric strings" do
      assert Arguments.parse_floor("F3") == 3
      assert Arguments.parse_floor("F0") == 0
    end

    test "parses numeric strings" do
      assert Arguments.parse_floor("3") == 3
      assert Arguments.parse_floor("10") == 10
    end

    test "raises ArgumentError for invalid formats" do
      assert_raise ArgumentError, ~r/Invalid floor format/, fn ->
        Arguments.parse_floor("invalid")
      end
    end
  end

  describe "parse_heading/1" do
    test "parses 'up' variations" do
      assert Arguments.parse_heading("up") == :up
      assert Arguments.parse_heading("UP") == :up
    end

    test "parses 'down' variations" do
      assert Arguments.parse_heading("down") == :down
    end

    test "parses 'idle' variations" do
      assert Arguments.parse_heading("idle") == :idle
    end

    test "raises ArgumentError for unknown headings" do
      assert_raise ArgumentError, ~r/Invalid heading/, fn ->
        Arguments.parse_heading("sideways")
      end
    end
  end
end
