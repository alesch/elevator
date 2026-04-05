#!/usr/bin/env nu

# Automates the isolation of an AI agent using Git Worktrees.
# One Agent = One Branch = One Directory = One Port.
#
# Usage: ./agent-setup.nu <agent_name>

def main [agent_name: string] {
  let agents_root = "agents"
  let base_port = 4001

  # Color codes
  let cyan = "\e[1;36m"
  let green = "\e[1;32m"
  let bold = "\e[1m"
  let dim = "\e[2m"
  let reset = "\e[0m"

  let agent_dir = $"($agents_root)/($agent_name)"
  let branch = $"agent/($agent_name)"

  print $"\n($cyan)--- 🤖 Setting up Sandbox for Agent: ($agent_name) ---($reset)"

  # 1. Create Branch & Worktree
  print "📦 Creating Git Worktree..."

  # Ensure agent root exists
  mkdir -p $agents_root

  # Add to .gitignore if not already there
  if ($".gitignore" | path exists) {
    let gitignore_content = open .gitignore
    if not ($gitignore_content | str contains $"($agents_root)/") {
      echo "" | append $".gitignore"
      echo "# Multi-Agent Sandboxes" | append $".gitignore"
      echo $agents_root | append $".gitignore"
    }
  }

  # Create branch if it doesn't exist
  let branch_exists = (^git rev-parse --verify $branch 2> /dev/null | complete).exit_code == 0

  if not $branch_exists {
    ^git branch $branch main
  } else {
    print $"   (Using existing branch: ($branch))"
  }

  # Add Worktree
  let worktree_result = (^git worktree add $agent_dir $branch 2>&1 | complete)
  if $worktree_result.exit_code != 0 {
    error $"Could not create worktree: ($worktree_result.stdout)"
  }

  # 2. Assign Unique Port
  print "🔢 Assigning Parallel Port..."

  # Scan existing agents for ports to avoid collisions
  let existing_ports = (
    glob $"($agents_root)/*/.env"
    | each { |env_file|
      try {
        open $env_file
        | lines
        | find "PORT="
        | parse "PORT={port}"
        | get port.0
        | into int
      } catch {
        null
      }
    }
    | compact
  )

  let port = if ($existing_ports | is-empty) {
    $base_port
  } else {
    ($existing_ports | sort | last) + 1
  }

  # Create .env file in agent directory
  $"export PORT=($port)
export PHX_HOST=localhost"
  | save $"($agent_dir)/.env"

  # 3. Trust Mise configuration
  if (which mise | is-not-empty) {
    print "🔐 Trusting Mise Configuration..."
    ^mise trust $agent_dir
  }

  # 4. Symlink Heavy Dependencies
  print "🔗 Symlinking Dependencies (Space Saver)..."
  let root_dir = (pwd)

  let targets = ["node_modules" "priv/plts"]

  for target in $targets {
    let source = $"($root_dir)/($target)"
    let destination = $"($agent_dir)/($target)"

    if ($source | path exists) {
      # Remove any existing copy in the worktree
      rm -rf $destination
      ^ln -s $source $destination
    }
  }

  # 5. Final Verification
  print $"\n($green)✅ Sandbox Ready at: ($agent_dir)($reset)"
  print $"($bold)Agent Branch:($reset) ($branch)"
  print $"($bold)Parallel Port:($reset) ($port)"
  print $"($dim)(To start the agent's server, run: PORT=($port) iex -S mix phx.server in that directory)($reset)\n"
}
