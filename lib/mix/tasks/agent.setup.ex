defmodule Mix.Tasks.Agent.Setup do
  @moduledoc """
  Automates the isolation of an AI agent using Git Worktrees.
  One Agent = One Branch = One Directory = One Port.

  Usage: mix agent.setup <agent_name>
  """
  use Mix.Task
  require Logger

  @agents_root "agents"
  @base_port 4001

  @impl Mix.Task
  def run([name | _]) do
    agent_dir = Path.join(@agents_root, name)
    branch = "agent/#{name}"

    IO.puts("\n\e[1;36m--- 🤖 Setting up Sandbox for Agent: #{name} ---\e[0m")

    # 1. Create Branch & Worktree
    setup_worktree(agent_dir, branch)

    # 2. Assign Unique Port
    port = assign_port(name, agent_dir)

    # 3. Trust Mise configuration (Parity Protection)
    trust_mise(agent_dir)

    # 4. Symlink Heavy Dependencies (Parity and Space Protection)
    symlink_assets(agent_dir)

    # 4. Final Verification
    IO.puts("\n\e[1;32m✅ Sandbox Ready at: #{agent_dir}\e[0m")
    IO.puts("\e[1mAgent Branch:\e[0m #{branch}")
    IO.puts("\e[1mParallel Port:\e[0m #{port}")
    IO.puts("\e[2m(To start the agent's server, run: PORT=#{port} iex -S mix phx.server in that directory)\e[0m\n")
  end

  def run(_) do
    Mix.raise("Usage: mix agent.setup <agent_name>")
  end

  # --- Internal Logic ---

  defp setup_worktree(dir, branch) do
    IO.puts("📦 Creating Git Worktree...")

    # Ensure agent root exists (but ignore it from git)
    File.mkdir_p!(@agents_root)
    ensure_ignored()

    # Create branch if doesn't exist
    case System.cmd("git", ["rev-parse", "--verify", branch], stderr_to_stdout: true) do
      {_, 0} -> IO.puts("   (Using existing branch: #{branch})")
      _ -> System.cmd("git", ["branch", branch, "main"])
    end

    # Add Worktree
    case System.cmd("git", ["worktree", "add", dir, branch]) do
      {_, 0} -> :ok
      {msg, _} -> Mix.raise("Could not create worktree: #{msg}")
    end
  end

  defp assign_port(name, agent_dir) do
    # Scan existing agents for ports to avoid collisions
    existing_ports =
      Path.wildcard("#{@agents_root}/*/.env")
      |> Enum.map(fn path ->
        case File.read(path) do
          {:ok, content} ->
            case Regex.run(~r/PORT=(\d+)/, content) do
              [_, p] -> String.to_integer(p)
              _ -> nil
            end

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    port =
      if Enum.empty?(existing_ports) do
        @base_port
      else
        Enum.max(existing_ports) + 1
      end

    File.write!(Path.join(agent_dir, ".env"), "export PORT=#{port}\nexport PHX_HOST=localhost\n")
    port
  end

  defp trust_mise(dir) do
    if System.find_executable("mise") do
      IO.puts("🔐 Trusting Mise Configuration...")
      System.cmd("mise", ["trust", dir])
    end
  end

  defp symlink_assets(dir) do
    IO.puts("🔗 Symlinking Dependencies (Space Saver)...")
    root = File.cwd!()

    # Heavy folders to share
    targets = [
      "node_modules",
      "priv/plts"
    ]

    for target <- targets do
      source = Path.join(root, target)
      destination = Path.join(dir, target)

      if File.exists?(source) do
        # Remove any existing copy in the worktree
        File.rm_rf!(destination)
        File.ln_s!(source, destination)
      end
    end
  end

  defp ensure_ignored do
    gitignore = ".gitignore"

    if File.exists?(gitignore) do
      content = File.read!(gitignore)

      unless String.contains?(content, "#{@agents_root}/") do
        File.write!(gitignore, "\n# Multi-Agent Sandboxes\n#{@agents_root}/\n", [:append])
      end
    end
  end
end
