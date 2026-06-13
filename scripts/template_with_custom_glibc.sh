#!/bin/bash
# ============================================================================
# TEMPLATE: New Coding Agent - Custom glibc 2.28 Wrapper
# ============================================================================
# This is a TEMPLATE for adding support for a NEW coding agent.
# Follow the instructions below and adapt for your agent.
#
# Two common approaches exist (choose ONE):
#
# Approach A: ld-linux direct invocation (RECOMMENDED)
#   Use when the agent runs on Node.js/Python and you can find the entry point.
#   See scripts/cursor_cli_with_custom_glibc.sh or scripts/kimi_with_custom_glibc.sh
#
# Approach B: patchelf binary modification
#   Use when the agent is a single compiled binary.
#   See scripts/opencode_with_custom_glibc.sh
#
# Author: Your Name
# License: MIT
# ============================================================================

set -euo pipefail

echo "Starting YOUR_AGENT with custom glibc 2.28..."

# ---------------------------------------------------------------------------
# [TODO] Set your agent's binary/entry point paths here
# ---------------------------------------------------------------------------
# Replace these with your agent's actual paths:
AGENT_NAME="YOUR_AGENT_NAME"
AGENT_BIN_PATH="$HOME/.your-agent/bin/your-agent"   # Binary or entry point
# AGENT_NODE_PATH="$HOME/.your-agent/bin/node"       # Node.js binary (if applicable)
# AGENT_INDEX_JS="$HOME/.your-agent/bin/index.js"    # JS entry (if applicable)

# ---------------------------------------------------------------------------
# [TODO] Choose your launch method below
# ---------------------------------------------------------------------------
# Option A: ld-linux direct invocation (for Node.js/Python agents)
# Option B: patchelf (for single compiled binary agents)

# ---------------------------------------------------------------------------
# Validation (shared)
# ---------------------------------------------------------------------------
GLIBC_LINKER="$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2"
if [ ! -x "$GLIBC_LINKER" ]; then
  echo "Error: Custom glibc linker not found: $GLIBC_LINKER" >&2
  echo "Please compile and install glibc 2.28 first (see README.md)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Save original environment variables
# ---------------------------------------------------------------------------
ORIGINAL_LD_LIBRARY_PATH="${LD_LIBRARY_PATH-}"
ORIGINAL_LANG="${LANG-}"
ORIGINAL_LC_ALL="${LC_ALL-}"
ORIGINAL_LOCPATH="${LOCPATH-}"
ORIGINAL_TERM="${TERM-}"

# ---------------------------------------------------------------------------
# Minimal environment setup (shared for all agents)
# ---------------------------------------------------------------------------
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

if [ -d "$HOME/opt/glibc-2.28/lib/locale" ]; then
    export LOCPATH="$HOME/opt/glibc-2.28/lib/locale"
fi

# Only add GCC lib path for libgcc_s.so.1 (pthread_cancel support)
# Do NOT add glibc-2.28 path to LD_LIBRARY_PATH to avoid system program crashes
export LD_LIBRARY_PATH="$HOME/opt/gcc-9.5.0/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ---------------------------------------------------------------------------
# LAUNCH METHOD A: ld-linux direct invocation
# ---------------------------------------------------------------------------
# Use this for agents that run on Node.js/Python.
# The agent's script typically finds its own runtime and launches it.
#
# Adapt the command below to match your agent's actual startup command.
#
# GLIBC_LIB_PATH="$HOME/opt/glibc-2.28/lib:$HOME/opt/gcc-9.5.0/lib64:/lib64:/usr/lib64"
# "$GLIBC_LINKER" \
#   --library-path "$GLIBC_LIB_PATH" \
#   $AGENT_NODE_PATH --use-system-ca $AGENT_INDEX_JS "$@"

# ---------------------------------------------------------------------------
# LAUNCH METHOD B: patchelf modification
# ---------------------------------------------------------------------------
# Use this for single compiled binary agents.
# Requires patchelf to be installed.
#
# TEMP_DIR=$(mktemp -d)
# MODIFIED_BIN="$TEMP_DIR/${AGENT_NAME}_modified"
# cp "$AGENT_BIN_PATH" "$MODIFIED_BIN"
# patchelf --set-interpreter "$GLIBC_LINKER" "$MODIFIED_BIN"
# "$MODIFIED_BIN" "$@"
# rm -rf "$TEMP_DIR"

# ---------------------------------------------------------------------------
# [TODO] Replace this placeholder with the actual launch command
# ---------------------------------------------------------------------------
echo "Error: This is a template. Please implement the launch command for $AGENT_NAME." >&2
exit 1

RETURN_CODE=$?

# ---------------------------------------------------------------------------
# Restore environment variables
# ---------------------------------------------------------------------------
export LD_LIBRARY_PATH="$ORIGINAL_LD_LIBRARY_PATH"
[ -n "$ORIGINAL_LANG" ] && export LANG="$ORIGINAL_LANG"
if [ -n "$ORIGINAL_LC_ALL" ]; then
    export LC_ALL="$ORIGINAL_LC_ALL"
else
    unset LC_ALL || true
fi
if [ -n "$ORIGINAL_LOCPATH" ]; then
    export LOCPATH="$ORIGINAL_LOCPATH"
else
    unset LOCPATH || true
fi
[ -n "$ORIGINAL_TERM" ] && export TERM="$ORIGINAL_TERM"

exit $RETURN_CODE
