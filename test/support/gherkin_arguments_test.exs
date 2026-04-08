defmodule Elevator.Gherkin.ArgumentsTest do
  use ExUnit.Case, async: true
  alias Elevator.Gherkin.Arguments

  describe "parse_floor/1" do
    test "parses numeric strings" do
      assert Arguments.parse_floor("3") == 3
      assert Arguments.parse_floor("0") == 0
    end

    test "parses 'ground' and 'base' as 0" do
      assert Arguments.parse_floor("ground") == 0
      assert Arguments.parse_floor("base") == 0
    end

    test "raises error for nil or empty string" do
      assert_raise ArgumentError, ~r/Floor argument is missing/, fn ->
        Arguments.parse_floor(nil)
      end

      assert_raise ArgumentError, ~r/Floor argument is missing/, fn ->
        Arguments.parse_floor("")
      end
    end

    test "parses 'F[n]' format" do
      assert Arguments.parse_floor("F5") == 5
      assert Arguments.parse_floor("F10") == 10
    end

    test "raises ArgumentError for invalid formats" do
      assert_raise ArgumentError, ~r/Invalid floor format/, fn ->
        Arguments.parse_floor("attic")
      end
    end
  end

  describe "parse_heading/1" do
    test "parses standard headings" do
      assert Arguments.parse_heading("up") == :up
      assert Arguments.parse_heading("down") == :down
      assert Arguments.parse_heading("idle") == :idle
    end

    test "is case-insensitive and supports atoms" do
      assert Arguments.parse_heading("UP") == :up
      assert Arguments.parse_heading(":down") == :down
    end

    test "raises error for unknown headings" do
      assert_raise ArgumentError, ~r/Invalid heading/, fn ->
        Arguments.parse_heading("sideways")
      end
    end
  end

  describe "parse_source/1" do
    test "parses 'car' and 'hall'" do
      assert Arguments.parse_source("car") == :car
      assert Arguments.parse_source("hall") == :hall
    end

    test "raises ArgumentError for invalid sources" do
      assert_raise ArgumentError, ~r/Invalid source/, fn ->
        Arguments.parse_source("outside")
      end
    end
  end

  describe "parse_list/2" do
    test "parses a CSV list of floors" do
      assert Arguments.parse_list("1, 2, 3", &Arguments.parse_floor/1) == [1, 2, 3]
    end

    test "handles extra whitespace" do
      assert Arguments.parse_list("  5,  2 , 4  ", &Arguments.parse_floor/1) == [5, 2, 4]
    end

    test "handles empty strings or leading/trailing commas" do
      assert Arguments.parse_list("1, , 3", &Arguments.parse_floor/1) == [1, 3]
      assert Arguments.parse_list("", &Arguments.parse_floor/1) == []
    end
  end
end
