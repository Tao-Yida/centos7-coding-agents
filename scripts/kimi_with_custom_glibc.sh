#!/bin/bash
#
# Run Kimi Code with custom glibc 2.28 on CentOS 7
#
# This script launches Kimi Code using the custom glibc 2.28 dynamic linker
# without modifying the kimi script or binary itself.
#
# Prerequisites:
#   - glibc 2.28 installed at $HOME/opt/glibc-2.28
#   - GCC 9.5.0 installed at $HOME/opt/gcc-9.5.0
#   - Kimi Code installed (typically at ~/.kimi-code/bin/kimi)
#
# How it works:
#   Uses ld-linux-x86-64.so.2 --library-path to launch kimi with custom glibc.
#   Same approach as cursor_cli_with_custom_glibc.sh since both are Node.js-based.
#

set -euo pipefail

echo "[kimi] Starting Kimi Code with custom glibc 2.28..."

# ─── Locate Kimi binary ─────────────────────────────────────────────────────

KIMI_PATH="${HOME}/.kimi-code/bin/kimi"

if [ ! -x "${KIMI_PATH}" ]; then
  echo "[kimi] ERROR: Kimi Code not found at: ${KIMI_PATH}" >&2
  echo "[kimi] Please install Kimi Code first." >&2
  exit 1
fi

# ─── Locate custom glibc ─────────────────────────────────────────────────────

GLIBC_LINKER="${HOME}/opt/glibc-2.28/lib/ld-linux-x86-64.so.2"
GLIBC_LIB_PATH="${HOME}/opt/glibc-2.28/lib:${HOME}/opt/gcc-9.5.0/lib64:/lib64:/usr/lib64"

if [ ! -x "${GLIBC_LINKER}" ]; then
  echo "[kimi] ERROR: Custom glibc linker not found at: ${GLIBC_LINKER}" >&2
  echo "[kimi] Please compile and install glibc 2.28 first." >&2
  exit 1
fi

# ─── Save original environment ───────────────────────────────────────────────

ORIGINAL_LD_LIBRARY_PATH="${LD_LIBRARY_PATH-}"
ORIGINAL_LANG="${LANG-}"
ORIGINAL_LC_ALL="${LC_ALL-}"
ORIGINAL_LOCPATH="${LOCPATH-}"
ORIGINAL_TERM="${TERM-}"

# ─── Set safe runtime environment ────────────────────────────────────────────
#
# IMPORTANT: Do NOT add glibc-2.28 to LD_LIBRARY_PATH — system programs
# compiled against glibc 2.17 will crash (segfault) if they inherit it.
# Only GCC lib64 path is added for libgcc_s.so.1 (pthread_cancel support).
#
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

if [ -d "${HOME}/opt/glibc-2.28/lib/locale" ]; then
    export LOCPATH="${HOME}/opt/glibc-2.28/lib/locale"
fi

export LD_LIBRARY_PATH="${HOME}/opt/gcc-9.5.0/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ─── Launch kimi with custom glibc ───────────────────────────────────────────

"${GLIBC_LINKER}" \
  --library-path "${GLIBC_LIB_PATH}" \
  "${KIMI_PATH}" "$@"

RETURN_CODE=$?

# ─── Restore original environment ────────────────────────────────────────────

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

exit ${RETURN_CODE}