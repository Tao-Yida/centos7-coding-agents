#!/bin/bash
# ============================================================================
# Cursor CLI Agent - Custom glibc 2.28 Wrapper
# ============================================================================
# Description: Run Cursor CLI Agent with custom glibc 2.28 on CentOS 7
#              (or any old Linux with glibc < 2.28)
#
# Prerequisites:
#   - glibc 2.28 installed at $HOME/opt/glibc-2.28
#   - GCC 9.5.0 installed at $HOME/opt/gcc-9.5.0
#   - Cursor CLI Agent installed (typically ~/.local/bin/agent)
#
# How it works:
#   Instead of modifying the agent script, this launches the agent's internal
#   Node.js binary directly with the custom glibc dynamic linker.
#
# Reference:
#   The original agent script (~/.local/bin/agent) does:
#     NODE_BIN="$SCRIPT_DIR/node"
#     exec -a "$0" "$NODE_BIN" --use-system-ca "$SCRIPT_DIR/index.js" "$@"
#
# Author: Yida Tao
# License: MIT
# ============================================================================

set -euo pipefail

echo "Starting Cursor CLI Agent with custom glibc 2.28..."

# ---------------------------------------------------------------------------
# Find the agent's internal runtime directory
# ---------------------------------------------------------------------------
AGENT_PATH="$HOME/.local/bin/agent"
if command -v realpath >/dev/null 2>&1; then
  SCRIPT_DIR="$(dirname "$(realpath "$AGENT_PATH")")"
else
  SCRIPT_DIR="$(dirname "$AGENT_PATH")"
fi

NODE_BIN="$SCRIPT_DIR/node"
INDEX_JS="$SCRIPT_DIR/index.js"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [ ! -x "$NODE_BIN" ]; then
  echo "Error: Cursor CLI Agent not found or node not executable." >&2
  echo "Expected: $NODE_BIN" >&2
  echo "Please install Cursor CLI first: curl https://cursor.com/install | bash" >&2
  exit 1
fi

if [ ! -f "$INDEX_JS" ]; then
  echo "Error: Agent entry point not found: $INDEX_JS" >&2
  exit 1
fi

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
# Set up minimal environment for custom glibc
# ---------------------------------------------------------------------------
# IMPORTANT: Do NOT add glibc-2.28 to LD_LIBRARY_PATH!
# Adding it would cause system programs (like bash) compiled against system
# glibc 2.17 to crash (segfault). The agent uses its own bundled node binary,
# so we use ld-linux-x86-64.so.2 --library-path to specify the custom glibc.

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

if [ -d "$HOME/opt/glibc-2.28/lib/locale" ]; then
    export LOCPATH="$HOME/opt/glibc-2.28/lib/locale"
fi

# Only add GCC lib path for libgcc_s.so.1 (pthread_cancel support)
# NOT the glibc path
export LD_LIBRARY_PATH="$HOME/opt/gcc-9.5.0/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ---------------------------------------------------------------------------
# Launch agent with custom glibc dynamic linker
# ---------------------------------------------------------------------------
GLIBC_LIB_PATH="$HOME/opt/glibc-2.28/lib:$HOME/opt/gcc-9.5.0/lib64:/lib64:/usr/lib64"

"$GLIBC_LINKER" \
  --library-path "$GLIBC_LIB_PATH" \
  "$NODE_BIN" --use-system-ca "$INDEX_JS" "$@"

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
