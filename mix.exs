defmodule Elevator.MixProject do
  use Mix.Project

  def project do
    [
      app: :elevator,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [ci: :test]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Elevator.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.10"},
      {:phoenix_live_view, "~> 0.20.2"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:cabbage, "~> 0.4.1", only: :test}
    ]
  end

  defp aliases do
    [
      "test-gui": ["cmd npx playwright test"],
      glossary: ["cmd sh -c 'tools/extract_steps.py test/features > features/glossary.md'"],
      ci: [
        "cmd echo '\n\e[1;36m--- ✨ Checking Formatting --- \e[0m\e[2m(mix format)\e[0m'",
        "format --check-formatted",
        "cmd echo '\n\e[1;36m--- 🔍 Running Linter (Credo) --- \e[0m\e[2m(mix credo --strict)\e[0m'",
        "credo --strict",
        "cmd echo '\n\e[1;36m--- 🛡️  Auditing Dependencies --- \e[0m\e[2m(mix deps.audit)\e[0m'",
        "deps.audit",
        "cmd echo '\n\e[1;36m--- 🕵️‍♂️ Running Security Scan (Sobelow) --- \e[0m\e[2m(mix sobelow --config)\e[0m'",
        "sobelow --config",
        "cmd echo '\n\e[1;36m--- 🔨 Compiling Projct (Strict) --- \e[0m\e[2m(mix compile --warnings-as-errors)\e[0m'",
        "compile --warnings-as-errors",
        "cmd echo '\n\e[1;36m--- 🔬 Running Static Analysis (Dialyzer) --- \e[0m\e[2m(mix dialyzer)\e[0m'",
        "dialyzer",
        "cmd echo '\n\e[1;36m--- 🧪 Running Automated Tests --- \e[0m\e[2m(mix test)\e[0m'",
        "test"
      ]
    ]
  end
end
