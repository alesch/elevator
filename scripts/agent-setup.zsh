#!/bin/zsh

# Automates the isolation of an AI agent using Git Worktrees.
# One Agent = One Branch = One Directory = One Port.
#
# Usage: ./agent-setup.zsh <agent_name>

set -e

AGENTS_ROOT="agents"
BASE_PORT=4001

# Color codes
CYAN='\e[1;36m'
GREEN='\e[1;32m'
BOLD='\e[1m'
DIM='\e[2m'
RESET='\e[0m'

if [ -z "$1" ]; then
  echo "Usage: ./agent-setup.zsh <agent_name>" >&2
  exit 1
fi

AGENT_NAME="$1"
AGENT_DIR="$AGENTS_ROOT/$AGENT_NAME"
BRANCH="agent/$AGENT_NAME"

echo -e "\n${CYAN}--- 🤖 Setting up Sandbox for Agent: $AGENT_NAME ---${RESET}"

# 1. Create Branch & Worktree
echo "📦 Creating Git Worktree..."

# Ensure agent root exists (but ignore it from git)
mkdir -p "$AGENTS_ROOT"

# Add to .gitignore if not already there
if [ -f .gitignore ]; then
  if ! grep -q "^${AGENTS_ROOT}/\$" .gitignore; then
    echo "" >> .gitignore
    echo "# Multi-Agent Sandboxes" >> .gitignore
    echo "$AGENTS_ROOT/" >> .gitignore
  fi
fi

# Create branch if it doesn't exist
if ! git rev-parse --verify "$BRANCH" > /dev/null 2>&1; then
  git branch "$BRANCH" main
else
  echo "   (Using existing branch: $BRANCH)"
fi

# Add Worktree
if ! git worktree add "$AGENT_DIR" "$BRANCH" 2>&1; then
  echo "Error: Could not create worktree" >&2
  exit 1
fi

# 2. Assign Unique Port
echo "🔢 Assigning Parallel Port..."

# Scan existing agents for ports to avoid collisions
# Using zsh-style array
EXISTING_PORTS=()
for env_file in $AGENTS_ROOT/*/.env(N); do
  if [ -f "$env_file" ]; then
    PORT=$(grep -o 'PORT=\([0-9]*\)' "$env_file" 2>/dev/null | cut -d= -f2)
    if [ -n "$PORT" ]; then
      EXISTING_PORTS+=($PORT)
    fi
  fi
done

if [ ${#EXISTING_PORTS[@]} -eq 0 ]; then
  PORT=$BASE_PORT
else
  # Find max port and increment (zsh sort)
  MAX_PORT=$(print -l ${EXISTING_PORTS[@]} | sort -n | tail -1)
  PORT=$((MAX_PORT + 1))
fi

# Create .env file in agent directory
cat > "$AGENT_DIR/.env" << EOF
export PORT=$PORT
export PHX_HOST=localhost
EOF

# 3. Trust Mise configuration (Parity Protection)
if command -v mise &> /dev/null; then
  echo "🔐 Trusting Mise Configuration..."
  mise trust "$AGENT_DIR"
fi

# 4. Symlink Heavy Dependencies (Parity and Space Protection)
echo "🔗 Symlinking Dependencies (Space Saver)..."
ROOT_DIR=$(pwd)

# Using zsh array syntax
TARGETS=(node_modules priv/plts)

for target in $TARGETS; do
  SOURCE="$ROOT_DIR/$target"
  DESTINATION="$AGENT_DIR/$target"

  if [ -e "$SOURCE" ]; then
    # Remove any existing copy in the worktree
    rm -rf "$DESTINATION"
    ln -s "$SOURCE" "$DESTINATION"
  fi
done

# 5. Final Verification
echo -e "\n${GREEN}✅ Sandbox Ready at: $AGENT_DIR${RESET}"
echo -e "${BOLD}Agent Branch:${RESET} $BRANCH"
echo -e "${BOLD}Parallel Port:${RESET} $PORT"
echo -e "${DIM}(To start the agent's server, run: PORT=$PORT iex -S mix phx.server in that directory)${RESET}\n"
