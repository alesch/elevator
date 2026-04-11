defmodule Elevator.Features.HomingTest do
  use Cabbage.Feature,
    file: "homing.feature"

  alias Elevator.Core
  alias Elevator.Gherkin.Arguments, as: Args
  import ExUnit.Assertions

  setup do
    {:ok, %{state: Core.init(), actions: [], vault: nil, sensor: nil}}
  end

  # --- Given steps (State Initialization) ---

  defgiven ~r/^the Elevator Vault is empty$/, _vars, context do
    {:ok, %{context | vault: nil}}
  end

  defgiven ~r/^the Elevator Vault stores "Floor (?<floor>.+)"$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    {:ok, %{context | vault: floor}}
  end

  defgiven ~r/^the Elevator Sensor is currently at "Floor (?<floor>.+)"$/,
           %{floor: floor_str},
           context do
    floor = Args.parse_floor(floor_str)
    {:ok, %{context | sensor: floor}}
  end

  defgiven ~r/^the Elevator Sensor is ":unknown" or mismatches$/, _vars, context do
    # Set it to something that clearly won't match Vault floor (usually 3 in the feature)
    {:ok, %{context | sensor: 99}}
  end

  defgiven ~r/^the elevator has started rehoming$/, _vars, context do
    # Natural transition to rehoming via startup check failure
    {state, _} = Core.handle_event(Core.init(), :startup_check, %{vault: nil, sensor: nil})
    # Emulate hardware starting to crawl in response to the :crawl action
    state = put_in(state.hardware.motor_status, :crawling)
    {:ok, %{context | state: state}}
  end

  defgiven ~r/^the elevator is in rehoming phase$/, _vars, context do
    # Natural transition to rehoming via startup check failure
    {state, _} = Core.handle_event(Core.init(), :startup_check, %{vault: nil, sensor: nil})
    {:ok, %{context | state: state}}
  end

  defgiven ~r/^"door_status" is ":closed"$/, _vars, context do
    # Assuming it's already closed in Core.init()
    assert Core.door_status(context.state) == :closed
    {:ok, context}
  end

  # --- When steps (Actions) ---

  defwhen ~r/^the system (starts|reboots)$/, _vars, context do
    # This is the "Decision Point" being refactored from Controller to Core
    {new_state, actions} =
      Core.handle_event(context.state, :startup_check, %{
        vault: context.vault,
        sensor: context.sensor
      })

    {:ok, %{context | state: new_state, actions: actions}}
  end

  defwhen ~r/^the Core receives its very first ":floor_arrival" event$/, _vars, context do
    # We choose a floor (e.g., 0)
    {new_state, actions} = Core.process_arrival(context.state, 0)
    {:ok, %{context | state: new_state, actions: actions}}
  end

  defwhen ~r/^the ":motor_stopped" confirmation is received after homing arrival$/,
          _vars,
          context do
    {new_state, actions} = Core.handle_event(context.state, :motor_stopped)
    {:ok, %{context | state: new_state, actions: actions}}
  end

  defwhen ~r/^any floor request is received$/, _vars, context do
    {new_state, actions} = Core.request_floor(context.state, :car, 2)
    {:ok, %{context | state: new_state, actions: actions}}
  end

  # --- Then Steps ---

  defthen ~r/^(the )?"?phase"? is "(?<value>.+)"$/, %{value: val_str}, context do
    expected = Args.parse_phase(val_str)
    assert Core.phase(context.state) == expected
    {:ok, context}
  end

  defthen ~r/^(the )?"?motor_status"? is "(?<value>.+)"$/, %{value: val_str}, context do
    expected = Args.parse_motor_status(val_str)
    case {expected, context.actions} do
      {:stopping, actions} when actions != [] -> assert {:stop_motor} in actions
      _ -> assert Core.motor_status(context.state) == expected
    end
    {:ok, context}
  end

  defthen ~r/^(the )?"?door_status"? is "(?<value>.+)"$/, %{value: val_str}, context do
    expected = Args.parse_door_status(val_str)
    case {expected, context.actions} do
      {:opening, actions} when actions != [] -> assert {:open_door} in actions
      _ -> assert Core.door_status(context.state) == expected
    end
    {:ok, context}
  end

  defthen ~r/^(the )?"?(?<field>[^"]+)"? is "(?<value>[^"]+)"$/, %{field: field, value: val}, context do
    case field do
      "phase" -> assert Core.phase(context.state) == Args.parse_phase(val)
      "heading" -> 
         expected = Args.parse_heading(val)
         case {expected, context.actions} do
           {:idle, actions} when actions != [] -> assert {:stop_motor} in actions
           _ -> assert Core.heading(context.state) == expected
         end
      "motor_speed" ->
         # motor_speed is a property of the crawl/move action in FICS
         if String.contains?(val, "crawling") do
            assert Enum.any?(context.actions, fn {:crawl, _} -> true; _ -> false end)
         end
      "current_floor" ->
         case val do
           ":unknown" -> assert Core.current_floor(context.state) == :unknown
           _ -> assert Core.current_floor(context.state) == Args.parse_floor(val)
         end
      "door_status" ->
         expected = Args.parse_door_status(val)
         assert Core.door_status(context.state) == expected
      "motor_status" ->
         expected = Args.parse_motor_status(val)
         case {expected, context.actions} do
           {:stopping, actions} when actions != [] -> assert {:stop_motor} in actions
           _ -> assert Core.motor_status(context.state) == expected
         end
    end
    {:ok, context}
  end

  defthen ~r/^no motor movement should be triggered$/, _vars, context do
    refute Enum.any?(context.actions, fn a -> match?({:move, _}, a) or match?({:crawl, _}, a) end)
    {:ok, context}
  end

  defthen ~r/^the elevator should move until the first physical sensor confirms arrival$/,
          _vars,
          context do
    assert {:crawl, :down} in context.actions
    {:ok, context}
  end

  defthen ~r/^the Vault is updated with the current floor$/, _vars, context do
    # Check for the persistence intent returned by FICS Core
    assert Enum.any?(context.actions, fn 
      {:persist_arrival, _} -> true
      _ -> false
    end)
    {:ok, context}
  end

  defthen ~r/^no "(?<cmd>.+)" command is issued$/, %{cmd: cmd_str}, context do
    cmd = String.trim_leading(cmd_str, ":") |> String.to_atom()
    refute Enum.any?(context.actions, fn
      {^cmd} -> true
      {^cmd, _} -> true
      _ -> false
    end)
    {:ok, context}
  end

  defthen ~r/^the "phase" should transition to ":idle"$/, _vars, context do
    assert Core.phase(context.state) == :idle
    {:ok, context}
  end

  defthen ~r/^"door_status" should remain ":closed"$/, _vars, context do
    assert Core.door_status(context.state) == :closed
    {:ok, context}
  end

  defthen ~r/^no ":open_door" command should be issued$/, _vars, context do
    refute {:open_door} in context.actions
    {:ok, context}
  end

  defthen ~r/^the "(?<attr>.+)" should immediately become "(?<val>.+)"$/,
          %{attr: attr_str, val: val_str},
          context do
    expected = val_str |> String.trim_leading(":") |> String.to_atom()

    case attr_str do
      "heading" -> assert Core.heading(context.state) == expected
      "motor_status" -> 
        case expected do
          :running -> assert Enum.any?(context.actions, &match?({:move, _}, &1))
          :crawling -> assert Enum.any?(context.actions, &match?({:crawl, _}, &1))
          :stopping -> assert {:stop_motor} in context.actions
          :stopped -> assert Core.motor_status(context.state) == :stopped
        end
    end

    {:ok, context}
  end

  defthen ~r/^"(?<attr>.+)" should become "(?<val>.+)"$/,
          %{attr: attr_str, val: val_str},
          context do
    expected = val_str |> String.trim_leading(":") |> String.to_atom()
    case attr_str do
      "motor_status" -> 
        case expected do
          :stopping -> assert {:stop_motor} in context.actions
        end
    end
    {:ok, context}
  end

  defthen ~r/^the request should be ignored and NOT added to the queue$/, _vars, context do
    # During rehoming, we expect only the virtual F0 request
    assert Core.requests(context.state) == [{:car, 0}]
    {:ok, context}
  end
end
