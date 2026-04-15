defmodule Elevator.Features.ManualControlTest do
  use Cabbage.Feature,
    file: "manual_control.feature",
    async: false

  alias Elevator.Core
  alias Elevator.Gherkin.Arguments, as: Args
  alias Elevator.Gherkin.CoreSteps

  import_steps(Elevator.Gherkin.CoreSteps)
end
