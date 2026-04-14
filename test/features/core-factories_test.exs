defmodule Elevator.Features.CoreFactoriesTest do
  use Cabbage.Feature,
    file: "core-factories.feature",
    async: false

  import_steps(Elevator.Gherkin.CoreSteps)
end
