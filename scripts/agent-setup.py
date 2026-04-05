#!/usr/bin/env python3

"""
Automates the isolation of an AI agent using Git Worktrees.
One Agent = One Branch = One Directory = One Port.

Usage: ./agent-setup.py <agent_name>
"""

import sys
import subprocess
import os
import re
from pathlib import Path
from typing import List, Optional

# Constants
AGENTS_ROOT = "agents"
BASE_PORT = 4001

# Color codes
CYAN = "\033[1;36m"
GREEN = "\033[1;32m"
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"


def run_command(cmd: List[str], check: bool = True) -> subprocess.CompletedProcess:
    """Run a shell command and return the result."""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if check and result.returncode != 0:
            raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{result.stderr}")
        return result
    except FileNotFoundError as e:
        raise RuntimeError(f"Command not found: {cmd[0]}") from e


def setup_worktree(agent_dir: str, branch: str) -> None:
    """Create git branch and worktree."""
    print("📦 Creating Git Worktree...")

    # Ensure agent root exists
    Path(AGENTS_ROOT).mkdir(parents=True, exist_ok=True)

    # Add to .gitignore if not already there
    gitignore_path = Path(".gitignore")
    if gitignore_path.exists():
        content = gitignore_path.read_text()
        if f"{AGENTS_ROOT}/" not in content:
            with open(gitignore_path, "a") as f:
                f.write(f"\n# Multi-Agent Sandboxes\n{AGENTS_ROOT}/\n")

    # Create branch if it doesn't exist
    result = run_command(["git", "rev-parse", "--verify", branch], check=False)
    if result.returncode != 0:
        run_command(["git", "branch", branch, "main"])
    else:
        print(f"   (Using existing branch: {branch})")

    # Add worktree
    result = run_command(["git", "worktree", "add", agent_dir, branch], check=False)
    if result.returncode != 0:
        raise RuntimeError(f"Could not create worktree: {result.stderr}")


def assign_port(agent_dir: str) -> int:
    """Assign a unique port by scanning existing agents."""
    print("🔢 Assigning Parallel Port...")

    existing_ports = []
    agents_path = Path(AGENTS_ROOT)

    # Scan existing agents for ports
    if agents_path.exists():
        for env_file in agents_path.glob("*/.env"):
            try:
                content = env_file.read_text()
                match = re.search(r"PORT=(\d+)", content)
                if match:
                    existing_ports.append(int(match.group(1)))
            except Exception:
                pass

    port = BASE_PORT if not existing_ports else max(existing_ports) + 1

    # Create .env file
    env_path = Path(agent_dir) / ".env"
    env_path.write_text(f"export PORT={port}\nexport PHX_HOST=localhost\n")

    return port


def trust_mise(agent_dir: str) -> None:
    """Trust mise configuration if available."""
    result = run_command(["which", "mise"], check=False)
    if result.returncode == 0:
        print("🔐 Trusting Mise Configuration...")
        run_command(["mise", "trust", agent_dir])


def symlink_assets(agent_dir: str) -> None:
    """Create symlinks to heavy dependencies."""
    print("🔗 Symlinking Dependencies (Space Saver)...")

    root_dir = Path.cwd()
    targets = ["node_modules", "priv/plts"]

    for target in targets:
        source = root_dir / target
        destination = Path(agent_dir) / target

        if source.exists():
            # Remove any existing copy in the worktree
            if destination.exists() or destination.is_symlink():
                if destination.is_dir() and not destination.is_symlink():
                    import shutil
                    shutil.rmtree(destination)
                else:
                    destination.unlink()

            # Create symlink
            destination.symlink_to(source)


def main() -> None:
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: ./agent-setup.py <agent_name>", file=sys.stderr)
        sys.exit(1)

    agent_name = sys.argv[1]
    agent_dir = f"{AGENTS_ROOT}/{agent_name}"
    branch = f"agent/{agent_name}"

    print(f"\n{CYAN}--- 🤖 Setting up Sandbox for Agent: {agent_name} ---{RESET}")

    try:
        # 1. Create Branch & Worktree
        setup_worktree(agent_dir, branch)

        # 2. Assign Unique Port
        port = assign_port(agent_dir)

        # 3. Trust Mise configuration
        trust_mise(agent_dir)

        # 4. Symlink Heavy Dependencies
        symlink_assets(agent_dir)

        # 5. Final Verification
        print(f"\n{GREEN}✅ Sandbox Ready at: {agent_dir}{RESET}")
        print(f"{BOLD}Agent Branch:{RESET} {branch}")
        print(f"{BOLD}Parallel Port:{RESET} {port}")
        print(
            f"{DIM}(To start the agent's server, run: PORT={port} iex -S mix phx.server in that directory){RESET}\n"
        )

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
