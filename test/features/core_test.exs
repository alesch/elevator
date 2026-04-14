defmodule Elevator.Features.CoreTest do
  use Cabbage.Feature,
    file: "core.feature",
    async: false

  alias Elevator.Core
  alias Elevator.Gherkin.Arguments, as: Args
  alias Elevator.Gherkin.CoreSteps

  import_steps(Elevator.Gherkin.CoreSteps)
end
