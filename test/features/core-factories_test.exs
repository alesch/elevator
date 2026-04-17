defmodule Elevator.Features.CoreFactoriesTest do
  use Cabbage.Feature,
    file: "core-factories.feature",
    async: false

  alias Elevator.Core
  alias Elevator.Gherkin.Arguments, as: Args

  import_steps(Elevator.Gherkin.CoreSteps)
end
