<img src="assets/album.png" alt="cover" width="50%" style="display: block; margin-left: auto; margin-right: auto;" />

[中文版本](README_Chinese.md) | English

# Running OpenCode with Custom glibc 2.28 on CentOS 7

**Note:** If you only need to install OpenCode without upgrading glibc or gcc, the simpler method in `https://github.com/pedropombeiro/opencode-legacy-glibc` is recommended. This repository’s custom glibc approach remains useful for Cursor CLI Agent installation on CentOS 7; see `https://github.com/Tao-Yida/cursorcli-glibc-shim`.

## Table of Contents

- [Background](#background)
- [Important Notes](#important-notes)
- [Prerequisites](#prerequisites)
- [Quick Reference](#quick-reference)
- [Step 1: Installing GCC 9.5.0](#step-1-installing-gcc-9550)
- [Step 2: Installing Make 4.2](#step-2-installing-make-42)
- [Step 3: Compiling and Installing glibc 2.28](#step-3-compiling-and-installing-glibc-228)
- [Step 4: Installing OpenCode](#step-4-installing-opencode)
- [Step 5: Configuring OpenCode to Use Custom glibc](#step-5-configuring-opencode-to-use-custom-glibc)
- [Step 6: Using OpenCode](#step-6-using-opencode)
- [Security Enhancement and Defensive Programming](#security-enhancement-and-defensive-programming)
- [Known Issues](#known-issues)
- [Troubleshooting](#troubleshooting)
- [Important Tips](#important-tips)
- [Summary](#summary)

## Background

The default glibc version on CentOS 7 systems is 2.17, while modern applications like OpenCode require glibc 2.28 or higher. Since glibc is a core system library, directly upgrading the system glibc may cause system instability. This guide describes how to compile and install glibc 2.28 in a user directory and use it to run OpenCode, all without requiring root privileges.

## Important Notes

1. **Project Development Method**: This project is 100% vibe coding product. The author does not have extensive knowledge of Linux kernel, glibc libraries, etc., and is unfamiliar with the Pull Request mechanism, so PR requests are temporarily not accepted. However, users are encouraged to submit Issues to report problems.

2. **Usage Risk Warning**: Since this project is developed using vibe coding approach, there may be potential errors and unstable factors. There are certain risks when using it. Please evaluate thoroughly before use and operate cautiously.

3. **Script Location**: The main script `opencode_with_custom_glibc.sh` is located in the root directory of the project for direct usage. While the project repository contains a `scripts` subdirectory, the operational script is placed in the root directory to avoid confusion. When using this project, please ensure you are using the script from the root directory.

## Prerequisites

### Checking Operating System Version

Before starting, please confirm that you are using a CentOS 7 system. You can check this using the following command:

```bash
cat /etc/redhat-release
```

**Sample Output**:
```
CentOS Linux release 7.9.2009 (Core)
```

Or use:

```bash
hostnamectl
```

**Sample Output**:
```
   Static hostname: localhost.localdomain
         Icon name: computer-vm
           Chassis: vm
        Machine ID: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
           Boot ID: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    Virtualization: kvm
  Operating System: CentOS Linux 7 (Core)
       CPE OS Name: cpe:/o:centos:centos:7
            Kernel: Linux 3.10.0-1160.119.1.el7.x86_64
      Architecture: x86-64
```

### Other Prerequisites

- CentOS 7 system
- Sufficient disk space in the user home directory (at least 5GB recommended)
- Basic compilation tools (gcc, make) - usually pre-installed on CentOS 7 systems. If not available, you can:
  - Use Conda to install: `conda install -c conda-forge gcc_linux-64 make`
  - Or contact the system administrator to install basic development tools
- Network connection (for downloading source code)

**Important**: This guide can be completed entirely without root privileges. All software is installed in user directories.

## Quick Reference

### Key Paths

- GCC 9.5.0 Installation Path: `$HOME/opt/gcc-9.5.0`
- Make 4.2 Installation Path: `$HOME/opt/make-4.2`
- glibc 2.28 Installation Path: `$HOME/opt/glibc-2.28`
- OpenCode Binary Path: `$HOME/.opencode/bin/opencode`
- OpenCode Startup Script: `$HOME/opencode_with_custom_glibc.sh`

### Key Environment Variables

```bash
# Used during compilation
export PATH=$HOME/opt/make-4.2/bin:$HOME/opt/gcc-9.5.0/bin:$PATH
export LD_LIBRARY_PATH=$HOME/opt/gcc-9.5.0/lib64:$LD_LIBRARY_PATH

# Note: When running OpenCode, LD_LIBRARY_PATH is NOT set by the startup script
# OpenCode uses patchelf-modified interpreter to automatically find custom glibc 2.28
# This avoids bash subprocess crashes (see "Known Issues" section for details)
```

### Verification Commands

```bash
# Verify GCC
$HOME/opt/gcc-9.5.0/bin/gcc --version

# Verify Make
$HOME/opt/make-4.2/bin/make --version

# Verify glibc
$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 --version

# Verify OpenCode
opencode --version
```

## Step 1: Installing GCC 9.5.0

### 1.0 Install Compilation Dependencies (Important)

**Important Note**: This guide can be completed entirely without root privileges. For GCC compilation dependencies (gmp, mpfr, libmpc), we recommend using Conda.

**Recommended Method: Use Conda to Install Dependencies**

If you have Conda installed, you can use it to install these dependencies:

```bash
# Activate conda environment (if you have one)
conda activate your_env_name  # or create new: conda create -n gcc-build

# Install GCC compilation dependencies
conda install -c conda-forge gmp mpfr libmpc zlib
```

Then configure environment variables so GCC compilation can find these libraries:

```bash
export CPPFLAGS="-I$CONDA_PREFIX/include $CPPFLAGS"
export LDFLAGS="-L$CONDA_PREFIX/lib $LDFLAGS"
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
```



### 1.1 Download GCC Source Code

```bash
cd ~
mkdir -p ~/opt/src
cd ~/opt/src

# Download GCC 9.5.0 source code
wget https://ftp.gnu.org/gnu/gcc/gcc-9.5.0/gcc-9.5.0.tar.xz
tar -xf gcc-9.5.0.tar.xz
cd gcc-9.5.0
```

### 1.2 Prepare GCC Compilation Environment

If you installed dependency libraries using Conda (recommended method), ensure that environment variables are correctly set (see Step 1.0).

**Note**: If you used other methods (GCC's built-in download script or compiled from source), GCC's configure script will automatically detect and use these dependency libraries.

### 1.3 Configure and Compile GCC

```bash
# Create build directory
mkdir -p ~/opt/src/gcc-9.5.0-build
cd ~/opt/src/gcc-9.5.0-build

# Configure GCC (install to user directory)
../gcc-9.5.0/configure \
    --prefix=$HOME/opt/gcc-9.5.0 \
    --enable-languages=c,c++ \
    --disable-multilib

# Compile (use multicore acceleration, adjust according to CPU core count)
make -j$(nproc)

# Install
make install
```

**Note**: GCC compilation takes a long time, possibly 1-2 hours. Please be patient.

### 1.4 Verify GCC Installation

```bash
export PATH=$HOME/opt/gcc-9.5.0/bin:$PATH
export LD_LIBRARY_PATH=$HOME/opt/gcc-9.5.0/lib64:$LD_LIBRARY_PATH

gcc --version
# Should display gcc (GCC) 9.5.0

# Test compiling a simple program
echo 'int main(){return 0;}' > /tmp/test.c
$HOME/opt/gcc-9.5.0/bin/gcc /tmp/test.c -o /tmp/test
/tmp/test && echo "GCC compilation test successful" || echo "GCC compilation test failed"
rm /tmp/test /tmp/test.c
```

## Step 2: Installing Make 4.2

### 2.1 Download Make Source Code

**Important**: You must use Make 4.2 version, as Make 4.3 and 4.4 have compatibility issues with glibc 2.28.

```bash
cd ~/opt/src
wget https://ftp.gnu.org/gnu/make/make-4.2.tar.gz
tar -xf make-4.2.tar.gz
cd make-4.2
```

### 2.2 Configure and Compile Make

```bash
# Configure Make (using newly installed GCC)
# Note: Should be in make-4.2 directory now
./configure \
    --prefix=$HOME/opt/make-4.2 \
    CC=$HOME/opt/gcc-9.5.0/bin/gcc \
    CXX=$HOME/opt/gcc-9.5.0/bin/g++

# Compile and install
make -j$(nproc)
make install
```

### 2.3 Verify Make Installation

```bash
export PATH=$HOME/opt/make-4.2/bin:$PATH
make --version
# Should display GNU Make 4.2

# Verify make path
which make
# Should display $HOME/opt/make-4.2/bin/make
```

## Step 3: Compiling and Installing glibc 2.28

### 3.1 Download glibc Source Code

```bash
cd ~/opt/src
wget https://ftp.gnu.org/gnu/glibc/glibc-2.28.tar.xz
tar -xf glibc-2.28.tar.xz
```

### 3.2 Create Build Directory

```bash
mkdir -p ~/glibc_build/build
cd ~/glibc_build/build
```

### 3.3 Configure glibc

```bash
# Set compilation environment
export PATH=$HOME/opt/make-4.2/bin:$HOME/opt/gcc-9.5.0/bin:$PATH
export LD_LIBRARY_PATH=$HOME/opt/gcc-9.5.0/lib64:$LD_LIBRARY_PATH

# Configure glibc (install to user directory)
~/opt/src/glibc-2.28/configure \
    --prefix=$HOME/opt/glibc-2.28 \
    --enable-optimizations \
    --disable-werror \
    --disable-mathvec
```

**Configuration options explanation**:
- `--prefix=$HOME/opt/glibc-2.28`: Install to user directory
- `--enable-optimizations`: Enable optimizations
- `--disable-werror`: Treat warnings as non-fatal errors
- `--disable-mathvec`: Disable math vectorization (avoid compatibility issues). In glibc 2.28, the math vectorization feature (mathvec) uses SIMD instructions to accelerate mathematical functions. However, on certain platforms, especially when using older toolchains, this can cause compilation errors or runtime issues. Therefore, it's strongly recommended to disable this feature when compiling glibc 2.28.

### 3.4 Compile glibc

```bash
# Compile (use multicore acceleration)
make -j$(nproc)
```

**Note**: glibc compilation takes a long time, possibly 30-60 minutes.

#### Using Build Script (Optional)

To simplify the build process, you can create a build script `~/glibc_build/build_glibc.sh`:

```bash
#!/bin/bash
# glibc compilation environment setup script

# Set environment variables
# Use Make 4.2 because 4.3 and 4.4 have compatibility issues with glibc 2.28
export PATH=$HOME/opt/make-4.2/bin:$HOME/opt/gcc-9.5.0/bin:$PATH
export LD_LIBRARY_PATH=$HOME/opt/gcc-9.5.0/lib64

# Switch to build directory
cd ~/glibc_build/build || exit 1

# Verify make version
echo "Current make version:"
make --version | head -2
echo ""

# Check if already configured
if [ ! -f Makefile ]; then
    echo "Running configure..."
    $HOME/opt/src/glibc-2.28/configure \
        --prefix=$HOME/opt/glibc-2.28 \
        --enable-optimizations \
        --disable-werror \
        --disable-mathvec
fi

# Perform compilation
echo "Starting compilation..."
make -j$(nproc)
```

After setting execute permissions, you can run directly:

```bash
chmod +x ~/glibc_build/build_glibc.sh
~/glibc_build/build_glibc.sh
```

### 3.5 Install glibc

```bash
make install
```

### 3.6 Verify glibc Installation

```bash
# Check installed glibc version
$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 --version
# Should display glibc 2.28

# Check if key files exist
ls -lh $HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2
ls -lh $HOME/opt/glibc-2.28/lib/libc.so.6

# Test using custom glibc to run program
cat > /tmp/test_glibc.c << 'EOF'
#include <stdio.h>
#include <gnu/libc-version.h>
int main() {
    printf("GNU libc version: %s\n", gnu_get_libc_version());
    return 0;
}
EOF

$HOME/opt/gcc-9.5.0/bin/gcc /tmp/test_glibc.c -o /tmp/test_glibc
$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 \
    --library-path $HOME/opt/glibc-2.28/lib:$HOME/opt/gcc-9.5.0/lib64 \
    /tmp/test_glibc
# Should output: GNU libc version: 2.28

rm /tmp/test_glibc.c /tmp/test_glibc
```

## Step 4: Installing OpenCode

### 4.1 Install OpenCode

Using the official installation script:

```bash
curl -fsSL https://opencode.ai/install | bash
```

Or using npm/bun/pnpm/yarn:

```bash
# Using npm
npm install -g opencode-ai

# Or using bun
bun install -g opencode-ai

# Or using pnpm
pnpm install -g opencode-ai

# Or using yarn
yarn global add opencode-ai
```

### 4.2 Verify OpenCode Installation

```bash
# Check OpenCode binary location
which opencode
# Usually located at ~/.opencode/bin/opencode or ~/.local/bin/opencode
```

## Step 5: Configuring OpenCode to Use Custom glibc

### 5.1 Install patchelf

patchelf is used to modify the dynamic linker path of binary files. There are multiple installation methods:

**Method 1: Using conda (recommended)**

```bash
# Activate conda environment (if available)
conda activate your_env_name  # Replace with your actual environment name

# Install patchelf
conda install -c conda-forge patchelf
```

**Method 2: Using pip**

```bash
# In conda environment or virtual environment
pip install patchelf
```

**Method 3: Compiling from source**

If the above methods are unavailable, you can compile from source:

```bash
cd ~/opt/src
wget https://github.com/NixOS/patchelf/releases/download/0.18.0/patchelf-0.18.0.tar.bz2
tar -xf patchelf-0.18.0.tar.bz2
cd patchelf-0.18.0
./configure --prefix=$HOME/.local
make
make install
```

**Verify installation:**

```bash
patchelf --version
# Should display patchelf version number
```

### 5.2 Create OpenCode Startup Script

Create script `~/opencode_with_custom_glibc.sh`:

```bash
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

# Check if OpenCode exists
if [ ! -f "$OPENCODE_PATH" ]; then
    echo "Error: OpenCode binary not found: $OPENCODE_PATH"
    echo "Please install OpenCode first: curl -fsSL https://opencode.ai/install | bash"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Check if patchelf is available
if ! command -v patchelf >/dev/null 2>&1; then
    echo "Error: patchelf command not found"
    echo "Please install patchelf first: conda install -c conda-forge patchelf"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Check if custom glibc exists
if [ ! -f "$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2" ]; then
    echo "Error: Custom glibc not found: $HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2"
    echo "Please compile and install glibc 2.28 according to the documentation first"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Activate conda environment to ensure access to patchelf (if using conda)
# Note: Modify the environment name below according to your actual conda environment name
# source $HOME/miniconda3/etc/profile.d/conda.sh
# conda activate your_env_name  # Replace with your conda environment name, e.g.: torch113pip

echo "Starting opencode with custom glibc 2.28..."

# Copy opencode to temporary location
cp "$OPENCODE_PATH" "$MODIFIED_OPENCODE"

# Use patchelf to modify interpreter to our custom glibc
if ! patchelf --set-interpreter "$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2" "$MODIFIED_OPENCODE"; then
    echo "Error: patchelf modification failed"
    rm -rf "$TEMP_DIR"
    exit 1
fi

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
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Set terminal type to one that supports output properly
# Use xterm-256color instead of dumb to ensure command output works correctly
export TERM=xterm-256color

# If the system has localized gconv modules, specify LOCPATH as well
if [ -d "$HOME/opt/glibc-2.28/lib/locale" ]; then
    export LOCPATH="$HOME/opt/glibc-2.28/lib/locale"
fi

# Run the modified opencode and capture exit code
# Note: Without setting LD_LIBRARY_PATH, opencode will automatically find custom glibc via patchelf-modified interpreter
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
```

### 5.3 Set Script Permissions

```bash
chmod +x ~/opencode_with_custom_glibc.sh
```

### 5.4 Configure Shell Alias and .bashrc

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# opencode command alias, using custom glibc 2.28
opencode() {
    $HOME/opencode_with_custom_glibc.sh "$@"
}

# Ensure opencode is in PATH
export PATH=$HOME/.opencode/bin:$PATH
```

**Important**: Also add the following to `~/.bashrc` to ensure bash subprocesses work correctly:

```bash
if [[ -n "$CURSOR_AGENT" ]]; then
    # Agent runtime uses simplified configuration
    PS1='\u@\h \W \$ '
    # Only keep necessary PATH settings
    export PATH=$HOME/.local/bin:$HOME/bin:$HOME/.opencode/bin:$PATH
    export PATH="$HOME/miniconda3/bin:$PATH"
    export HF_ENDPOINT=https://hf-mirror.com
    # Ensure output is not buffered
    export PYTHONUNBUFFERED=1
    # Ensure UTF-8 encoding
    export LANG=${LANG:-en_US.UTF-8}
    export LC_ALL=${LC_ALL:-en_US.UTF-8}
    # CRITICAL FIX: Clear LD_LIBRARY_PATH to avoid bash crashes
    # opencode uses custom glibc 2.28 via patchelf, doesn't need LD_LIBRARY_PATH
    # But system bash is compiled with system glibc 2.17, inheriting custom glibc LD_LIBRARY_PATH will crash
    # After clearing, bash will use system default glibc, while opencode still uses custom glibc (via patchelf)
    unset LD_LIBRARY_PATH
    # Don't load conda environment, NVM, etc. to avoid interfering with Agent
    return
fi
```

Then reload the configuration:

```bash
source ~/.bashrc
```

## Step 6: Using OpenCode

**Note**: There was previously an environment isolation issue, but it has been fixed in the latest version. OpenCode can now read files and execute commands normally. See the "Known Issues" section for details.

### 6.1 Configure OpenCode (Optional, can be completed on the graphical page)

First-time use requires configuring API keys:

```bash
opencode auth login
```

Select your preferred LLM provider (recommended: Anthropic).

### 6.2 Initialize Project

**Note**: There was previously an environment isolation issue, but it has been fixed. You can now initialize projects normally.

Go to your project directory:

```bash
cd /path/to/your/project
opencode
```

Run in the opencode interface:

```
/init
```

This will analyze the project and create an `AGENTS.md` file.

### 6.3 Start Using

Now you can use OpenCode normally! In the opencode interface:

- Enter natural language instructions to write code
- Use `/share` to create session sharing links
- Check the OpenCode documentation for more features

## Security Enhancement and Defensive Programming

When using a custom high-version glibc to run OpenCode, pay attention to the following security enhancement measures and defensive programming practices:

### 1. Avoid Commands That May Cause Segmentation Faults

In a custom glibc environment, some system commands may crash due to library incompatibilities. Specifically:

- **Avoid using** `locale` command: When using a custom high-version glibc runtime environment, avoid calling `locale` and related commands (such as `locale -a`). Such commands may cause segmentation faults (core dumps) because they link to the system's lower version of glibc.
- **Correct approach**: Directly set widely supported locale variables (such as `LANG=en_US.UTF-8`) instead of relying on runtime command detection to improve the security and stability of scripts.

### 2. Segmentation Fault (Core Dump) Problem Handling

When segmentation faults occur, it's usually because of library version incompatibilities or commands trying to access non-existent library functions. Solutions include:

- **Don't run system commands directly**: In a custom glibc environment, avoid running commands that may link to system libraries directly
- **Use static variables**: For locale settings, use predefined values rather than dynamic detection
- **Exception handling**: Add error handling logic to scripts to ensure environment recovery even if segmentation faults occur

### 3. Environment Isolation

- **Temporary file cleanup**: Ensure all temporary files are cleaned up when the script exits, whether exiting normally or abnormally
- **Use trap command**: Use trap to catch exit signals and ensure cleanup operations are performed before script ends
- **Environment variable restoration**: Save original environment variables and restore them when the script ends

### 4. Terminal Control Sequence Processing

- **Disable mouse event tracking**: Send `\033[?1000l\033[?1002l\033[?1003l\033[?1005l\033[?1006l` to turn off various XTerm-compatible mouse reporting modes
- **Set safe terminal type**: Temporarily set `TERM=dumb` to ensure the terminal emulator doesn't parse any control sequences
- **Restore state on exit**: Use trap to catch exit signals and send `\033[?1000h\033[?1002h\033[?1003h` to restore mouse functionality before script ends

## Known Issues

### Mouse Event Encoding Problem

- **Problem Description**: All terminals that have run the opencode command may continuously generate mouse behavior encodings (such as `[[<35;23;26M`, etc.) after running, as opencode enables terminal mouse event tracking functionality.
- **Solution**: There is no direct solution at present, but this issue can be resolved by closing the current terminal window or tab. This issue does not affect the normal use of opencode.
- **Temporary Relief**: Executing the `reset` command in the terminal may help, but is not guaranteed to completely solve the issue.
- **Preventive Measures**: If this issue affects your workflow, consider using a dedicated terminal window for opencode.

### Severe Environment Isolation Issue (RESOLVED)

- **Problem Description**: Previously, there was a severe environment isolation issue when running OpenCode with custom glibc 2.28. OpenCode could write files but could not read files or execute commands. Basic commands such as `ls`, `pwd`, `whoami`, etc., returned empty results or no output, or caused segmentation faults.
- **Root Cause**: The issue was caused by `LD_LIBRARY_PATH` being set to include custom glibc 2.28 libraries. This environment variable was inherited by opencode's subprocesses (e.g., bash). However, the system's bash is compiled with system glibc 2.17, and attempting to use custom glibc 2.28 libraries causes bash to crash with a segmentation fault.
- **Solution**: 
  1. **In `opencode_with_custom_glibc.sh`**: Do NOT set `LD_LIBRARY_PATH`. Since opencode uses a patchelf-modified interpreter that points to custom glibc 2.28, it will automatically find the correct libraries without needing `LD_LIBRARY_PATH`.
  2. **In `~/.bashrc`**: Add a check for `CURSOR_AGENT` environment variable and clear `LD_LIBRARY_PATH` when it's set. This ensures bash subprocesses use the system default glibc.
  3. **Terminal Type**: Changed from `TERM=dumb` to `TERM=xterm-256color` to ensure proper command output.
- **Status**: **RESOLVED** - The issue has been fixed. OpenCode can now read files and execute commands normally.
- **Debugging Method**: If you encounter similar issues (commands returning no output or segmentation faults):
  1. Check if `LD_LIBRARY_PATH` contains custom glibc paths: `echo $LD_LIBRARY_PATH`
  2. Test bash with custom glibc: `LD_LIBRARY_PATH="/path/to/custom/glibc/lib:$LD_LIBRARY_PATH" bash -c 'echo test'` - this should crash
  3. Verify the fix: Ensure `opencode_with_custom_glibc.sh` does NOT set `LD_LIBRARY_PATH`
  4. Verify `.bashrc`: Ensure it clears `LD_LIBRARY_PATH` when `CURSOR_AGENT` is set
  5. Check opencode logs: `tail -f ~/.local/share/opencode/log/*.log` to see if bash commands are executing

## Troubleshooting

### Problem 1: Errors when compiling GCC

**Common errors and solutions**:

1. **Missing dependency library errors**
   
   If you encounter errors about missing gmp, mpfr, libmpc, or other dependency libraries, we recommend using Conda:
   
   ```bash
   conda install -c conda-forge gmp mpfr libmpc zlib
   export CPPFLAGS="-I$CONDA_PREFIX/include $CPPFLAGS"
   export LDFLAGS="-L$CONDA_PREFIX/lib $LDFLAGS"
   export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
   ```
   
   Other optional methods:
   - Use GCC's built-in `./contrib/download_prerequisites` script
   - Compile dependency libraries from source (refer to Step 1.0 for details)

2. **Insufficient disk space**
   - Check disk space: `df -h ~`
   - Clean temporary files: `rm -rf ~/opt/src/gcc-9.5.0-build`
   - Ensure at least 5GB of free space

3. **Compilation failure**
   - Try single-core compilation: `make` (without `-j` option)
   - View detailed error messages: `make 2>&1 | tee build.log`
   - Check if system memory is sufficient: `free -h`

4. **Configure failure**
   - Ensure all dependencies are installed
   - Check system glibc version: `ldd --version`
   - Check configure log: `config.log`

### Problem 2: Errors when compiling glibc

**Solutions**:
- Ensure Make 4.2 is used (not 4.3 or 4.4)
- Check if GCC version is correct (should be 9.5.0)
- Ensure environment variables are set correctly
- If encountering errors related to mathvec, ensure the `--disable-mathvec` option was used during configuration

### Problem 3: OpenCode runtime unable to find libraries

**Solutions**:
- Check if `LD_LIBRARY_PATH` is set correctly
- Verify glibc installation path is correct
- Use `ldd` to check dependencies of the binary:
  ```bash
  ldd ~/.opencode/bin/opencode
  ```

### Problem 4: patchelf command not found

**Solutions**:
- If using conda: `conda install -c conda-forge patchelf`
- If using pip: `pip install patchelf`
- Or compile and install patchelf from source

### Problem 5: Terminal display anomalies

**Solutions**:
- Terminal reset logic is already included in the script
- If still having issues, you can manually execute:
  ```bash
  reset
  ```

### Problem 6: Segmentation fault (core dump) problem

**Solutions**:
- Avoid running `locale` command in custom glibc environment
- Set fixed locale environment variables directly, such as `LANG=en_US.UTF-8`
- Ensure the script has appropriate error handling and environment recovery logic

### Problem 7: libgcc_s.so.1 library dependency issue

**Error message**:
```
libgcc_s.so.1 must be installed for pthread_cancel to work
Aborted (core dumped)
```

**Problem cause**:
When OpenCode uses custom glibc 2.28, `libpthread` requires `libgcc_s.so.1` to support the `pthread_cancel` function.
Especially when performing complex tasks like file searching and parallel processing, if this library cannot be found, it will cause process crashes.

**Solutions**:
The startup script `opencode_with_custom_glibc.sh` automatically handles this issue:
- Sets `LD_LIBRARY_PATH` to include the lib64 path of GCC 9.5.0
- Ensures only GCC library paths are added, not custom glibc paths, to avoid bash subprocess crashes
- This allows OpenCode to find `libgcc_s.so.1`, while system commands still use system glibc

**Verification method**:
```bash
# Check if libgcc_s.so.1 exists
ls -la ~/opt/gcc-9.5.0/lib64/libgcc_s.so.1
```

## Summary

Through this guide, you successfully did the following on CentOS 7:

1. ✅ Compiled and installed GCC 9.5.0
2. ✅ Compiled and installed Make 4.2
3. ✅ Compiled and installed glibc 2.28 (installed in user directory)
4. ✅ Installed and configured OpenCode
5. ✅ Configured OpenCode to run with custom glibc

The entire process requires no root privileges, with all software installed in user directories without affecting system stability.

## Important Tips

### Environment Variable Persistence

To automatically set environment variables on each login, add to `~/.bashrc`:

```bash
# GCC 9.5.0 environment variables (optional, only when needed)
# export PATH=$HOME/opt/gcc-9.5.0/bin:$PATH
# export LD_LIBRARY_PATH=$HOME/opt/gcc-9.5.0/lib64:$LD_LIBRARY_PATH

# Make 4.2 environment variables (optional, only when needed)
# export PATH=$HOME/opt/make-4.2/bin:$PATH
```

**Note**: Usually no need to permanently set these environment variables in `.bashrc`, as the OpenCode startup script handles them automatically.


## License

This guide is licensed under the MIT License, free to use and modify.

## Contributions

Welcome to fork and submit Issues to improve this guide, but PR Reviews are currently not possible, apologies for this.

---

**Last Updated**: January 16, 2026

**Author**: Yida Tao