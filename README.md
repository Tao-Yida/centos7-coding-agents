<img src="assets/album.png" alt="cover" width="50%" style="display: block; margin-left: auto; margin-right: auto;" />

[中文版本](README_Chinese.md) | English

# Running AI Coding Agents on CentOS 7 with Custom glibc 2.28

**Supported Agents:** [OpenCode](https://opencode.ai) · [Cursor CLI](https://www.cursor.com) · [Kimi Code](https://kimi.moonshot.cn) · **[Add yours →](CONTRIBUTING.md)**

---

> 🎉 **Pull Requests are WELCOME!** This project consolidates scripts and tutorials for running modern AI coding agents on old Linux systems (CentOS 7, RHEL 7, etc.) where the default glibc is too old (2.17) to run agents compiled against glibc 2.28+. If you have a new agent method, **send a PR!** See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Table of Contents

- [Supported Agents](#supported-agents)
- [Background](#background)
- [How It Works](#how-it-works)
- [Common Prerequisites: Build GCC + Make + glibc](#common-prerequisites-build-gcc--make--glibc)
  - [Step 1: Installing GCC 9.5.0](#step-1-installing-gcc-9550)
  - [Step 2: Installing Make 4.2](#step-2-installing-make-42)
  - [Step 3: Compiling and Installing glibc 2.28](#step-3-compiling-and-installing-glibc-228)
- [Agent: OpenCode](#agent-opencode)
- [Agent: Cursor CLI](#agent-cursor-cli)
- [Agent: Kimi Code](#agent-kimi-code)
- [How to Add a New Agent](#how-to-add-a-new-agent)
- [Security Enhancement & Defensive Programming](#security-enhancement--defensive-programming)
- [Known Issues](#known-issues)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Contributions](#contributions)

---

## Supported Agents

| Agent | Method | Script | Status |
|---|---|---|---|
| [OpenCode](https://opencode.ai) | `patchelf` interpreter modification | [`scripts/opencode_with_custom_glibc.sh`](scripts/opencode_with_custom_glibc.sh) | ✅ Active |
| [Cursor CLI](https://www.cursor.com) | `ld-linux` direct invocation | [`scripts/cursor_cli_with_custom_glibc.sh`](scripts/cursor_cli_with_custom_glibc.sh) | ✅ Active |
| [Kimi Code](https://kimi.moonshot.cn) | `ld-linux` direct invocation | [`scripts/kimi_with_custom_glibc.sh`](scripts/kimi_with_custom_glibc.sh) | ✅ Active |
| **Your Agent?** | Your method | `scripts/{agent}_with_custom_glibc.sh` | 🔜 [PRs Welcome](CONTRIBUTING.md) |

---

## Background

The default glibc version on CentOS 7 systems is **2.17**, while modern AI coding agents require **glibc 2.28 or higher**. Since glibc is a core system library, directly upgrading the system glibc may cause system instability.

This project compiles a **user-local glibc 2.28** (plus GCC 9.5.0 and Make 4.2) and provides startup scripts for each coding agent — all without root privileges.

Originally focused on [OpenCode](https://github.com/pedropombeiro/opencode-legacy-glibc), this repo now serves as a **universal compatibility layer** for any coding agent targeting modern glibc.

---

## How It Works

Two approaches are used across the supported agents:

### Approach A: `patchelf` (for compiled binaries)
Modify the agent binary's `.interp` section to point to the custom glibc dynamic linker. Used for OpenCode, which is a single compiled binary.

```
patchelf --set-interpreter $HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 <binary>
```

### Approach B: `ld-linux` direct invocation (for Node.js/Python agents)
Directly invoke the agent's runtime (Node.js, Python, etc.) with `ld-linux-x86-64.so.2 --library-path`, specifying the custom glibc path. Used for Cursor CLI and Kimi Code, which are Node.js-based.

```
$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 \
  --library-path $HOME/opt/glibc-2.28/lib:... \
  <node|python> <entry_point>
```

### Key Design Decisions (apply to all scripts)

1. **Do NOT set `LD_LIBRARY_PATH` to custom glibc** — System binaries (bash, ls, etc.) compiled against glibc 2.17 will crash if they inherit custom glibc paths. The custom linker handles this via `--library-path` or `patchelf`.
2. **Only add GCC lib64 path to `LD_LIBRARY_PATH`** — Resolves the `libgcc_s.so.1 must be installed for pthread_cancel to work` error.
3. **Locale is set directly** — Running `locale` under custom glibc can segfault.
4. **Environment is restored on exit** — Original env vars are saved and restored.

---

## Common Prerequisites: Build GCC + Make + glibc

> These three components must be compiled **once** before using any agent script. They are shared across all agents.

### Checking Operating System Version

```bash
cat /etc/redhat-release
# CentOS Linux release 7.9.2009 (Core)
```

### Prerequisites

- CentOS 7 / RHEL 7 system
- ~5GB free disk space in home directory
- Basic compilation tools (gcc, make) — use Conda if not available:
  ```bash
  conda install -c conda-forge gcc_linux-64 make
  ```
- Network connection for downloading source code

**No root privileges required.**

### Quick Reference: Key Paths

| Component | Install Path |
|---|---|
| GCC 9.5.0 | `$HOME/opt/gcc-9.5.0` |
| Make 4.2 | `$HOME/opt/make-4.2` |
| glibc 2.28 | `$HOME/opt/glibc-2.28` |

---

### Step 1: Installing GCC 9.5.0

#### 1.0 Install Compilation Dependencies

GCC compilation requires gmp, mpfr, and libmpc. Use Conda (recommended):

```bash
conda activate your_env_name
conda install -c conda-forge gmp mpfr libmpc zlib
export CPPFLAGS="-I$CONDA_PREFIX/include $CPPFLAGS"
export LDFLAGS="-L$CONDA_PREFIX/lib $LDFLAGS"
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
```

#### 1.1 Download GCC Source Code

```bash
cd ~
mkdir -p ~/opt/src
cd ~/opt/src
wget https://ftp.gnu.org/gnu/gcc/gcc-9.5.0/gcc-9.5.0.tar.xz
tar -xf gcc-9.5.0.tar.xz
cd gcc-9.5.0
```

#### 1.2 Configure and Compile GCC

```bash
mkdir -p ~/opt/src/gcc-9.5.0-build
cd ~/opt/src/gcc-9.5.0-build

../gcc-9.5.0/configure \
    --prefix=$HOME/opt/gcc-9.5.0 \
    --enable-languages=c,c++ \
    --disable-multilib

make -j$(nproc)
make install
```

> ⏱ GCC compilation takes 1-2 hours. Be patient.

#### 1.3 Verify GCC Installation

```bash
export PATH=$HOME/opt/gcc-9.5.0/bin:$PATH
export LD_LIBRARY_PATH=$HOME/opt/gcc-9.5.0/lib64:$LD_LIBRARY_PATH
gcc --version
# Should display: gcc (GCC) 9.5.0
```

---

### Step 2: Installing Make 4.2

**Important**: Use Make 4.2 — versions 4.3 and 4.4 have compatibility issues with glibc 2.28.

```bash
cd ~/opt/src
wget https://ftp.gnu.org/gnu/make/make-4.2.tar.gz
tar -xf make-4.2.tar.gz
cd make-4.2

./configure \
    --prefix=$HOME/opt/make-4.2 \
    CC=$HOME/opt/gcc-9.5.0/bin/gcc \
    CXX=$HOME/opt/gcc-9.5.0/bin/g++

make -j$(nproc)
make install
```

Verify:

```bash
export PATH=$HOME/opt/make-4.2/bin:$PATH
make --version
# Should display: GNU Make 4.2
```

---

### Step 3: Compiling and Installing glibc 2.28

#### 3.1 Download glibc

```bash
cd ~/opt/src
wget https://ftp.gnu.org/gnu/glibc/glibc-2.28.tar.xz
tar -xf glibc-2.28.tar.xz
```

#### 3.2 Configure glibc

```bash
mkdir -p ~/glibc_build/build
cd ~/glibc_build/build

export PATH=$HOME/opt/make-4.2/bin:$HOME/opt/gcc-9.5.0/bin:$PATH
export LD_LIBRARY_PATH=$HOME/opt/gcc-9.5.0/lib64:$LD_LIBRARY_PATH

~/opt/src/glibc-2.28/configure \
    --prefix=$HOME/opt/glibc-2.28 \
    --enable-optimizations \
    --disable-werror \
    --disable-mathvec
```

**Configuration options**:
- `--prefix=$HOME/opt/glibc-2.28`: Install to user directory
- `--disable-mathvec`: Disable math vectorization (avoids toolchain compatibility issues)
- `--disable-werror`: Treat warnings as non-fatal

#### 3.3 Compile and Install glibc

```bash
make -j$(nproc)
make install
```

> ⏱ glibc compilation takes 30-60 minutes.

#### 3.4 Verify glibc Installation

```bash
$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 --version
# Should display: glibc 2.28

# Or compile and run a test program:
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
```

---

## Agent: OpenCode

### Overview

[OpenCode](https://opencode.ai) is an open-source AI coding assistant. OpenCode is a compiled binary requiring glibc 2.28+.

**Method**: `patchelf` — modifies the binary's interpreter to use custom glibc.

### Install OpenCode

```bash
curl -fsSL https://opencode.ai/install | bash
# Or: npm install -g opencode-ai
```

Verify installation:

```bash
which opencode
# Typically ~/.opencode/bin/opencode
```

### Install patchelf

```bash
conda install -c conda-forge patchelf
# Or: pip install patchelf
patchelf --version
```

### Usage

```bash
# Run directly from the repo
./scripts/opencode_with_custom_glibc.sh [arguments]

# Or add an alias to ~/.bashrc
opencode() {
    /path/to/repo/scripts/opencode_with_custom_glibc.sh "$@"
}
```

### Script: `scripts/opencode_with_custom_glibc.sh`

This script:
1. Copies the OpenCode binary to a temp directory
2. Uses `patchelf --set-interpreter` to point to `$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2`
3. Sets `LD_LIBRARY_PATH` to include `$HOME/opt/gcc-9.5.0/lib64` (for `libgcc_s.so.1`)
4. **Does NOT** set `LD_LIBRARY_PATH` to custom glibc (avoids bash subprocess crashes)
5. Restores all environment variables on exit
6. Manages terminal mouse tracking (cleanup on exit)

---

## Agent: Cursor CLI

### Overview

[Cursor CLI](https://www.cursor.com) (cursor-agent) is a Node.js-based AI coding agent requiring glibc 2.28+ for its bundled Node.js runtime. This method was originally published in the [cursorcli-glibc-shim](https://github.com/Tao-Yida/cursorcli-glibc-shim) repository.

**Method**: `ld-linux` direct invocation — launches the agent's internal Node.js binary with the custom glibc dynamic linker.

### Install Cursor CLI

```bash
curl https://cursor.com/install | bash
```

Verify installation:

```bash
which agent
# Typically ~/.local/bin/agent
```

### Usage

```bash
# Run directly from the repo (recommended)
./scripts/cursor_cli_with_custom_glibc.sh [arguments]

# Or add an alias to ~/.bashrc
cursor-cli() {
    /path/to/repo/scripts/cursor_cli_with_custom_glibc.sh "$@"
}
```

### Script: `scripts/cursor_cli_with_custom_glibc.sh`

This script:
1. Locates the agent's internal Node.js binary (`~/.local/bin/node`) and entry point (`index.js`)
2. Launches Node.js with the custom glibc dynamic linker:
   ```
   $HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 \
     --library-path $HOME/opt/glibc-2.28/lib:$HOME/opt/gcc-9.5.0/lib64:/lib64:/usr/lib64 \
     node --use-system-ca index.js [args]
   ```
3. **Does NOT** add glibc-2.28 to `LD_LIBRARY_PATH` (avoids system binary crashes)
4. Restores all environment variables on exit

---

## Agent: Kimi Code

### Overview

[Kimi Code](https://kimi.moonshot.cn) is a Node.js-based AI coding assistant requiring glibc 2.28+.

**Method**: `ld-linux` direct invocation — same approach as Cursor CLI.

### Install Kimi Code

Follow Kimi Code's official installation guide. It is typically installed at `~/.kimi-code/bin/kimi`.

### Usage

```bash
./scripts/kimi_with_custom_glibc.sh [arguments]

# Or add an alias
kimi() {
    /path/to/repo/scripts/kimi_with_custom_glibc.sh "$@"
}
```

### Script: `scripts/kimi_with_custom_glibc.sh`

Same approach as the Cursor CLI script — launches the kimi binary directly with the custom glibc dynamic linker.

---

## How to Add a New Agent

We welcome Pull Requests adding support for new coding agents!

### Quick Start

1. **Copy the template:**
   ```bash
   cp scripts/template_with_custom_glibc.sh scripts/your_agent_with_custom_glibc.sh
   ```
2. **Fill in the TODOs:** Set agent name, binary path, and launch method.
3. **Test your script:** Make sure it runs on a clean CentOS 7 environment.
4. **Update this README:** Add your agent to the [Supported Agents](#supported-agents) table and add a new section.
5. **Submit a PR:** See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

### Architecture Notes

Most modern coding agents fall into two categories:

| Agent Type | Examples | Recommended Method |
|---|---|---|
| Compiled binary (Node.js binary, Go binary) | OpenCode | `patchelf` — modify interpreter |
| Script-based (Node.js/Python wrapper) | Cursor CLI, Kimi Code | `ld-linux` — direct invocation |

The template at [`scripts/template_with_custom_glibc.sh`](scripts/template_with_custom_glibc.sh) supports both methods.

---

## Security Enhancement & Defensive Programming

### 1. Avoid Commands That Cause Segmentation Faults

- **Avoid `locale` and related commands** — They link to system glibc and crash under custom glibc environment.
- **Set locale variables directly** (`LANG=en_US.UTF-8`) instead of running detection commands.

### 2. Environment Isolation

- **Temporary file cleanup**: All scripts create temp copies in `mktemp -d` directories and clean up on exit.
- **`trap` for cleanup**: EXIT/INT/TERM signals are trapped to ensure cleanup.
- **Environment variable restoration**: Original env vars are saved and restored.

### 3. Terminal Control

- Mouse event tracking is disabled before agent launch and re-enabled on exit.

---

## Known Issues

### Mouse Event Encoding

All terminals that have run OpenCode may generate mouse behavior encodings (`[[<35;23;26M`) after running. Close the terminal tab to resolve. Running `reset` may help.

### `libgcc_s.so.1` Dependency

When using custom glibc 2.28, `libpthread` needs `libgcc_s.so.1` for `pthread_cancel`. The startup scripts handle this by adding `$HOME/opt/gcc-9.5.0/lib64` to `LD_LIBRARY_PATH`.

**Error if not configured:**
```
libgcc_s.so.1 must be installed for pthread_cancel to work
Aborted (core dumped)
```

### Bash Subprocess Crash (RESOLVED)

Previously, OpenCode's subprocesses (bash, ls, etc.) would segfault because `LD_LIBRARY_PATH` was set to include custom glibc 2.28, but system binaries are compiled against glibc 2.17.

**Root cause**: `LD_LIBRARY_PATH` inherited by subprocesses forces them to use incompatible glibc.

**Fix**: The scripts now **do not** set `LD_LIBRARY_PATH` to custom glibc. The custom linker is invoked directly or via `patchelf`. Only GCC's lib path is added to `LD_LIBRARY_PATH`.

---

## Troubleshooting

### Common Errors

| Error | Cause | Solution |
|---|---|---|
| `patchelf not found` | patchelf not installed | `conda install -c conda-forge patchelf` |
| `Custom glibc linker not found` | glibc 2.28 not compiled | Follow [Step 3](#step-3-compiling-and-installing-glibc-228) |
| `libgcc_s.so.1 must be installed` | GCC lib path missing | Ensure `$HOME/opt/gcc-9.5.0/lib64` is in `LD_LIBRARY_PATH` |
| Commands return no output | LD_LIBRARY_PATH inherited by bash | Use scripts without setting glibc in LD_LIBRARY_PATH |
| `GLIBC_2.29 not found` | Binary needs newer glibc | Try glibc 2.29+ (compile from source) |
| Terminal display anomalies | Mouse tracking enabled | Run `reset` or close terminal tab |

### Debugging

```bash
# Check if LD_LIBRARY_PATH contains custom glibc (should NOT)
echo $LD_LIBRARY_PATH

# Test bash with custom glibc (should crash if misconfigured)
LD_LIBRARY_PATH="/path/to/custom/glibc/lib:$LD_LIBRARY_PATH" bash -c 'echo test'

# Verify glibc version used by a binary
$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 --version

# Check library dependencies
ldd ~/.opencode/bin/opencode
```

---

## License

This project is licensed under the MIT License — free to use, modify, and distribute.

## Contributions

> **We now accept Pull Requests!** 🎉

This project started as a single-agent solution for OpenCode and has grown into a multi-agent compatibility layer for all coding agents on CentOS 7.

- See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
- Use the [template script](scripts/template_with_custom_glibc.sh) to add new agents.
- Open an Issue if you have problems or suggestions.

**Related Projects:**
- [opencode-legacy-glibc](https://github.com/pedropombeiro/opencode-legacy-glibc) — Simpler method for OpenCode-only users (no glibc upgrade needed)
- [cursorcli-glibc-shim](https://github.com/Tao-Yida/cursorcli-glibc-shim) — Original Cursor CLI glibc shim (now merged into this repo)

---

**Last Updated**: June 13, 2026

**Author**: Yida Tao
