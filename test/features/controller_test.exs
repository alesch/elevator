defmodule Elevator.Features.ControllerTest do
  use Cabbage.Feature,
    file: "controller.feature",
    async: false

  alias Elevator.Controller
  alias Elevator.Gherkin.Arguments, as: Args

  # ---------------------------------------------------------------------------
  # Given
  # ---------------------------------------------------------------------------

  # Cold-start: no vault or sensor injected, so the homing-check resolves
  # vault=nil / sensor=nil → Core transitions booting → rehoming and emits the
  # first broadcast.  We subscribe *before* starting so we never miss it.
  defgiven ~r/^the controller is running$/, _vars, context do
    Phoenix.PubSub.subscribe(Elevator.PubSub, "elevator:status")

    {:ok, ctrl} = Controller.start_link(motor: self(), door: self(), name: nil)

    # Cold-start homing_check: vault=nil/sensor=nil → booting → rehoming
    assert_receive {:elevator_state, %{logic: %{phase: :rehoming}}}

    {:ok, Map.put(context, :controller, ctrl)}
  end

  # ---------------------------------------------------------------------------
  # When
  # ---------------------------------------------------------------------------

  # Simulates the hardware sensor firing a floor-arrival event directly at the
  # controller, then waits for the resulting PubSub broadcast.  Because
  # pulse_and_commit/4 calls execute_actions/2 *before* broadcast_state/1, all
  # hardware casts (e.g. stop_now to the motor) are already in our mailbox by
  # the time the broadcast arrives.
  defwhen ~r/^the floor sensor reads floor (?<floor>.+)$/, %{floor: floor_str}, context do
    floor = Args.parse_floor(floor_str)
    send(context.controller, {:floor_arrival, floor})

    # Sync barrier only — get_state/1 is a call, so it returns only after the
    # floor_arrival message has been fully processed (actions dispatched, state broadcast).
    Controller.get_state(context.controller)

    {:ok, context}
  end

  # ---------------------------------------------------------------------------
  # Then
  # ---------------------------------------------------------------------------

  defthen ~r/^a state update is broadcast on elevator:status$/, _vars, context do
    assert_receive {:elevator_state, %{logic: %{phase: :arriving}}}

    {:ok, context}
  end

  defthen ~r/^the motor receives a stop command$/, _vars, context do
    # Hardware.Motor.stop/1 calls GenServer.cast(motor_pid, :stop_now).
    # Because motor: self() was injected, the cast lands in our mailbox as
    # {:"$gen_cast", :stop_now}.  assert_received is non-blocking and safe
    # here because the When step already synchronised on the PubSub broadcast,
    # which is sent after execute_actions/2 has already dispatched the cast.
    assert_received {:"$gen_cast", :stop_now},
                    "Expected the motor to receive a :stop_now cast but it did not"

    {:ok, context}
  end
end
