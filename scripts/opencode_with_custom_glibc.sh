#!/bin/bash
#
# Run OpenCode with custom glibc 2.28 on CentOS 7
#
# This script uses patchelf to modify the OpenCode binary's interpreter path
# to point to a custom glibc 2.28 compiled in user's $HOME directory.
#
# Prerequisites:
#   - glibc 2.28 installed at $HOME/opt/glibc-2.28
#   - GCC 9.5.0 installed at $HOME/opt/gcc-9.5.0
#   - patchelf installed (conda, pip, or compiled from source)
#   - OpenCode installed (typically at ~/.opencode/bin/opencode)
#
# Key design decisions:
#   - Uses patchelf to modify interpreter (NOT set LD_LIBRARY_PATH)
#   - Only GCC lib64 path added to LD_LIBRARY_PATH for libgcc_s.so.1
#   - Terminal mouse tracking disabled/enabled for clean state
#

set -euo pipefail

echo "[opencode] Starting OpenCode with custom glibc 2.28..."

# ─── Configuration ───────────────────────────────────────────────────────────

OPENCODE_BIN="${HOME}/.opencode/bin/opencode"
GLIBC_LINKER="${HOME}/opt/glibc-2.28/lib/ld-linux-x86-64.so.2"

# ─── Validation ──────────────────────────────────────────────────────────────

if [ ! -f "${OPENCODE_BIN}" ]; then
  echo "[opencode] ERROR: OpenCode binary not found: ${OPENCODE_BIN}" >&2
  echo "[opencode] Please install OpenCode first: curl -fsSL https://opencode.ai/install | bash" >&2
  exit 1
fi

if [ ! -x "${GLIBC_LINKER}" ]; then
  echo "[opencode] ERROR: Custom glibc not found at: ${GLIBC_LINKER}" >&2
  echo "[opencode] Please compile glibc 2.28 first (see README.md)." >&2
  exit 1
fi

if ! command -v patchelf >/dev/null 2>&1; then
  echo "[opencode] ERROR: patchelf not found." >&2
  echo "[opencode] Install it: conda install -c conda-forge patchelf" >&2
  echo "[opencode]          or: pip install patchelf" >&2
  exit 1
fi

# ─── Terminal cleanup trap ───────────────────────────────────────────────────

cleanup_terminal() {
    echo -e '\033[?1000h\033[?1002h\033[?1003h' 2>/dev/null || true
}
trap cleanup_terminal EXIT INT TERM

# Disable mouse tracking
echo -e '\033[?1000l\033[?1002l\033[?1003l\033[?1005l\033[?1006l' 2>/dev/null || true

# ─── Patch interpreter via patchelf ──────────────────────────────────────────
# Create a temp copy so the original binary stays unmodified

TEMP_DIR=$(mktemp -d)
MODIFIED_BIN="${TEMP_DIR}/opencode_modified"
cp "${OPENCODE_BIN}" "${MODIFIED_BIN}"
patchelf --set-interpreter "${GLIBC_LINKER}" "${MODIFIED_BIN}"

# ─── Save original environment ───────────────────────────────────────────────

ORIGINAL_LD_LIBRARY_PATH="${LD_LIBRARY_PATH-}"
ORIGINAL_LANG="${LANG-}"
ORIGINAL_LC_ALL="${LC_ALL-}"
ORIGINAL_LOCPATH="${LOCPATH-}"
ORIGINAL_TERM="${TERM-}"

# ─── Set safe runtime environment ────────────────────────────────────────────
#
# IMPORTANT: Do NOT add glibc-2.28 to LD_LIBRARY_PATH!
# OpenCode uses patchelf-modified interpreter to find custom glibc 2.28.
# Setting LD_LIBRARY_PATH with custom glibc causes bash subprocesses (which
# are compiled against system glibc 2.17) to segfault.
#
# Only GCC lib64 path is added for libgcc_s.so.1 (pthread_cancel support).
#
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

if [ -d "${HOME}/opt/glibc-2.28/lib/locale" ]; then
    export LOCPATH="${HOME}/opt/glibc-2.28/lib/locale"
fi

# Add GCC lib64 path so the patchelf'd binary can find libgcc_s.so.1
export LD_LIBRARY_PATH="${HOME}/opt/gcc-9.5.0/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ─── Launch OpenCode ─────────────────────────────────────────────────────────

"${MODIFIED_BIN}" "$@"
RETURN_CODE=$?

# ─── Restore environment ─────────────────────────────────────────────────────

export LD_LIBRARY_PATH="${ORIGINAL_LD_LIBRARY_PATH}"
[ -n "${ORIGINAL_LANG}" ] && export LANG="${ORIGINAL_LANG}"
if [ -n "${ORIGINAL_LC_ALL}" ]; then
    export LC_ALL="${ORIGINAL_LC_ALL}"
else
    unset LC_ALL || true
fi
if [ -n "${ORIGINAL_LOCPATH}" ]; then
    export LOCPATH="${ORIGINAL_LOCPATH}"
else
    unset LOCPATH || true
fi
[ -n "${ORIGINAL_TERM}" ] && export TERM="${ORIGINAL_TERM}"

# Clean up temp files asynchronously
( sleep 0.2; rm -rf "${TEMP_DIR}" ) &

echo "[opencode] OpenCode has exited, environment restored."
exit ${RETURN_CODE}