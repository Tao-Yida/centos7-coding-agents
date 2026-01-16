#!/bin/bash

# Define cleanup function
cleanup_terminal() {
    # Reset terminal to original state, enable mouse event tracking
    echo -e '\033[?1000h\033[?1002h\033[?1003h' 2>/dev/null || true
    echo "Terminal reset to original state"
}

# Set trap to ensure cleanup is performed when script exits
trap cleanup_terminal EXIT INT TERM

# Reset terminal state, disable mouse tracking
echo -e '\033[?1000l\033[?1002l\033[?1003l\033[?1005l\033[?1006l' 2>/dev/null || true

# Create a temporary directory to store the modified opencode
TEMP_DIR=$(mktemp -d)
OPENCODE_PATH="$HOME/.opencode/bin/opencode"
MODIFIED_OPENCODE="$TEMP_DIR/opencode_modified"

# Activate torch113pip environment to ensure access to patchelf
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate torch113pip

echo "Starting opencode with custom glibc 2.28..."

# Copy opencode to temporary location
cp "$OPENCODE_PATH" "$MODIFIED_OPENCODE"

# Use patchelf to modify the interpreter to our custom glibc
patchelf --set-interpreter "$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2" "$MODIFIED_OPENCODE"

# Save original environment variables
ORIGINAL_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
ORIGINAL_LANG="$LANG"
ORIGINAL_LOCPATH="$LOCPATH"
ORIGINAL_TERM="$TERM"
ORIGINAL_TERMCAP="$TERMCAP"

# IMPORTANT: opencode uses custom glibc 2.28 through patchelf-modified interpreter
# Therefore, we should NOT set LD_LIBRARY_PATH to avoid bash subprocess crashes
# If LD_LIBRARY_PATH is set, it will be inherited by opencode's subprocesses (e.g., bash)
# However, the system's bash is compiled with system glibc 2.17, using custom glibc will crash
# Without setting LD_LIBRARY_PATH, opencode can still run normally (via patchelf interpreter)
# And bash subprocesses will use the system default glibc, avoiding crashes

# Set safe locale to avoid encoding issues
# Directly set widely supported locale instead of running locale commands in custom glibc environment
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Set terminal type to one that supports output properly
# Use xterm-256color instead of dumb to ensure command output works correctly
# The dumb terminal type may cause some commands to fail to output properly
export TERM=xterm-256color

# If the system has localized gconv modules, specify LOCPATH as well
if [ -d "$HOME/opt/glibc-2.28/lib/locale" ]; then
    export LOCPATH="$HOME/opt/glibc-2.28/lib/locale"
fi

# Set temporary LD_LIBRARY_PATH to include gcc lib path, to support pthread_cancel
# Note: This setting will be inherited by opencode's subprocesses, but we only add gcc paths, not glibc paths
# So bash subprocesses will still use system glibc, avoiding crashes
#
# IMPORTANT DISCOVERY: When opencode uses custom glibc 2.28, libpthread needs libgcc_s.so.1 to support pthread_cancel
# If this path is not set, "libgcc_s.so.1 must be installed for pthread_cancel to work" error will occur
# Especially when performing complex tasks like file searching that require parallel processing
export LD_LIBRARY_PATH="$HOME/opt/gcc-9.5.0/lib64:$LD_LIBRARY_PATH"

# Run the modified opencode and capture exit code
"$MODIFIED_OPENCODE" "$@"

# Save return code
RETURN_CODE=$?

# Restore original environment variables
export LD_LIBRARY_PATH="$ORIGINAL_LD_LIBRARY_PATH"
export LANG="$ORIGINAL_LANG"
export LOCPATH="$ORIGINAL_LOCPATH"
if [ -n "$ORIGINAL_LOCPATH" ]; then
    export LOCPATH="$ORIGINAL_LOCPATH"
else
    unset LOCPATH
fi
export TERM="$ORIGINAL_TERM"

# Clean up temporary files, but not in current process, using subshell instead
( sleep 0.2; rm -rf "$TEMP_DIR" ) &

echo "opencode has exited, environment variables restored"
# Note: Terminal cleanup will be automatically executed when trap catches EXIT signal
exit $RETURN_CODE