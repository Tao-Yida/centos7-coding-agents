<img src="assets/album.png" alt="cover" width="50%" style="display: block; margin-left: auto; margin-right: auto;" />

[中文版本](README_Chinese.md) | English

# Running AI Coding Agents on CentOS 7 with Custom glibc 2.28

**Supported Agents:** [OpenCode](https://opencode.ai) · [Cursor CLI](https://www.cursor.com) · [Kimi Code](https://kimi.moonshot.cn) · [ZCode](https://zcode.net) (Remote SSH) · **[Add yours →](CONTRIBUTING.md)**

---

> 🎉 **Pull Requests are WELCOME!** This project consolidates scripts and tutorials for running modern AI coding agents on old Linux systems (CentOS 7, RHEL 7, etc.) where the default glibc is too old (2.17) to run agents compiled against glibc 2.28+. If you have a new agent method, **send a PR!** See [CONTRIBUTING.md](CONTRIBUTING.md).

> 💡 **For OpenCode-only users**: [@pedropombeiro/opencode-legacy-glibc](https://github.com/pedropombeiro/opencode-legacy-glibc) provides a **simpler, no-compilation-needed** approach specifically for OpenCode. It's a different solution by another developer — if you only need OpenCode and want to avoid compiling glibc, check that repo first. This repository's approach is more general (supports multiple agents) but requires more setup.

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
- [Agent: ZCode (Remote SSH)](#agent-zcode-remote-ssh)
- [Agent: Codex CLI & opencodex (Provider Switching)](#agent-codex-cli--opencodex-provider-switching)
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
| [ZCode](https://zcode.z.ai) (Remote SSH) | `ld-linux` binary replacement | [`scripts/node`](scripts/node) | ✅ Active |
| [Codex CLI](https://github.com/openai/codex) (provider switching via [opencodex](https://github.com/lidge-jun/opencodex)) | `ld-linux` direct invocation (bun wrapper) | — (see [guides](#agent-codex-cli--opencodex-provider-switching)) | ✅ Active |
| **Your Agent?** | Your method | `scripts/{agent}_with_custom_glibc.sh` | 🔜 [PRs Welcome](CONTRIBUTING.md) |

---

## Background

The default glibc version on CentOS 7 systems is **2.17**, while modern AI coding agents require **glibc 2.28 or higher**. Since glibc is a core system library, directly upgrading the system glibc may cause system instability.

This project compiles a **user-local glibc 2.28** (plus GCC 9.5.0 and Make 4.2) and provides startup scripts for each coding agent — all without root privileges.

This repository was originally created for OpenCode on CentOS 7, and has since expanded to support multiple coding agents (Cursor CLI, Kimi Code, etc.) with the same underlying glibc 2.28 approach.

> **Note about [opencode-legacy-glibc](https://github.com/pedropombeiro/opencode-legacy-glibc)**: That repository by [@pedropombeiro](https://github.com/pedropombeiro) provides a separate, simpler approach specifically for OpenCode — using Docker to build a compatible version without compiling glibc. If you only need OpenCode and want to avoid the compilation steps, we recommend checking that project first. This repository takes a more general approach (compile glibc once, support multiple agents) at the cost of more initial setup.

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

> 💡 **Simpler alternative**: If you only need OpenCode and prefer to avoid compiling glibc, check out [@pedropombeiro/opencode-legacy-glibc](https://github.com/pedropombeiro/opencode-legacy-glibc). It uses Docker to build a legacy-glibc-compatible OpenCode binary — less setup, but OpenCode-only. This repo's approach supports more agents at the cost of more initial setup.

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

## Agent: ZCode (Remote SSH)

### Overview

[ZCode](https://zcode.z.ai) is a Codex-like Agentic Development Environment (ADE) that enables AI agents to complete longer, multi-step development tasks end-to-end. Its remote SSH feature deploys a Node.js runtime (`~/.zcode/server/node`) on the remote Linux server and executes it directly via SSH — not through a shell alias or `.bashrc`.

**Method**: Binary replacement — replaces `~/.zcode/server/node` with a wrapper script that proxies to the original binary (renamed to `node.real`) via the custom glibc dynamic linker.

### Why This Is Different

Unlike OpenCode (local binary, `patchelf` approach) or Cursor CLI / Kimi Code (local CLI, bash alias approach), ZCode's remote server is triggered by the Windows client via SSH:

```
Windows ZCode client
  → SSH ~/.zcode/server/node        ← direct SSH execution
  → This script intercepts via ld-linux-x86-64.so.2
  → Launches original node.real with custom glibc 2.28
```

Since the SSH command executes the file directly, it **does not** go through aliases or `.bashrc` functions. The node binary itself must be replaced.

### Installation

On your remote CentOS 7 server, after completing the [Common Prerequisites](#common-prerequisites-build-gcc--make--glibc):

```bash
# 1. Navigate to ZCode's server directory
cd ~/.zcode/server

# 2. Back up the original node binary
cp node node.real

# 3. Deploy the wrapper script (from this repo)
cp /path/to/centos7-coding-agents/scripts/node ~/.zcode/server/node

# 4. Make it executable
chmod +x ~/.zcode/server/node
```

That's it. No `.bashrc` changes needed.

### Verification

```bash
# Verify node version
~/.zcode/server/node --version
# Should output: v22.16.0 (or your installed version)

# Verify ZCode server handshake
~/.zcode/server/node ~/.zcode/server/zcode-server.cjs
# Should output: {"type":"zcode-hello","version":"...","platform":"linux","arch":"x64",...}
```

Once verified, reconnect from your ZCode Windows client — the remote server should connect successfully.

### Important Notes

- **ZCode version upgrades**: If ZCode updates its Node.js runtime version, it may re-upload the `node` binary, overwriting the wrapper. You'll need to re-apply the steps above.
- **Runtime version detection**: ZCode checks `~/.zcode/server/.asset-components/node-runtime.json` to decide whether to re-deploy Node. If the version matches, it won't re-upload, so the wrapper usually persists across minor updates.
- **Agent integration**: `~/.zcode/server/agents/glm/zcode-agent` also calls `$runtime_root/node`, so the wrapper covers both the server and internal agents automatically — no additional configuration needed.

### Script: `scripts/node`

This script is a drop-in replacement for `~/.zcode/server/node`. It:
1. Locates the original binary (`node.real`) next to itself
2. Launches it via `ld-linux-x86-64.so.2 --library-path ...`
3. Sets `LD_LIBRARY_PATH` for GCC libs only (not glibc)
4. Restores all environment variables on exit

---

## Agent: Codex CLI & opencodex (Provider Switching)

### Overview

[Codex CLI](https://github.com/openai/codex) **installs and runs on CentOS 7 without any glibc workaround** — the problem only appears when you want to **switch service providers**. The [opencodex](https://github.com/lidge-jun/opencodex) proxy used for provider switching requires Node ≥ 18 and a bundled Bun runtime, both of which need glibc 2.18–2.28 — unavailable on CentOS 7's default glibc 2.17 (the `GLIBC_2.2x not found` error).

**Method**: `ld-linux` direct invocation — the same approach used by Cursor CLI and Kimi Code. A bash wrapper (`~/.local/bin/bun`) launches Bun via the custom glibc 2.28 loader (`$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 --library-path ...`), and the opencodex proxy runs from source with that wrapper.

**Verified on**: CentOS 7 (glibc 2.17) · codex-cli 0.147.0 · opencodex 2.11.1 · OpenCode Go provider · 2026-08-09

### Guides

Two bilingual handbooks document the complete, tested procedure (environment baseline, source install, proxy startup, provider/model routing, guardian approval fixes, session history recovery, and the full list of pitfalls):

| Topic | Chinese | English |
|---|---|---|
| opencodex deployment on CentOS 7 (source-mode install via the glibc-2.28 bun wrapper, proxy startup, provider & model routing, 12 verified pitfalls, session migration) | [opencodex-centos7-handbook.md](opencodex-centos7-handbook.md) | [opencodex-centos7-handbook-EN.md](opencodex-centos7-handbook-EN.md) |
| Codex provider switching (deepseek → Opencode Go) & session history recovery (label migration) | [Codex提供商切换与历史记录恢复.md](Codex提供商切换与历史记录恢复.md) | [Codex-Provider-Switching-and-History-Recovery-EN.md](Codex-Provider-Switching-and-History-Recovery-EN.md) |

### Key Takeaways

- **Installing Codex CLI itself is fine on CentOS 7** — no glibc adaptation needed.
- **Switching providers requires opencodex**, whose Node/Bun stack cannot run on glibc 2.17. Fix: run it via the glibc-2.28 loader wrapper. **Never** `export LD_LIBRARY_PATH` to the custom glibc — mixing glibc 2.28 with system 2.17 segfaults (exit 139).
- **No user-level systemd on CentOS 7** — `ocx service install` / `ocx restore back` always fail (`systemctl --user` → `Failed to get D-Bus connection`); use the direct-call injection script and a `crontab @reboot` entry instead.
- **Do not use `ocx codex-shim install` on CentOS 7** — its ensure step spawns bare Bun, fails on glibc, and rolls back the config injection while stopping the proxy.
- **History recovery**: Codex filters the resume list exactly by `model_provider` (openai/codex issue [#15494](https://github.com/openai/codex)); rollout JSONL files are never lost. Rewrite the `model_provider` label in both the JSONL first line (regex, no JSON round-trip) and `state_5.sqlite`, then restart app-server in the right order (DB first, then restart) — otherwise the app-server's cached tags get written back.

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

- **Problem Description**: All terminals that have run the opencode command may continuously generate mouse behavior encodings (such as `[[<35;23;26M`, etc.) after running, as opencode enables terminal mouse event tracking functionality.
- **Solution**: There is no direct solution at present, but this issue can be resolved by closing the current terminal window or tab. This issue does not affect the normal use of opencode.
- **Temporary Relief**: Executing the `reset` command in the terminal may help, but is not guaranteed to completely solve the issue.
- **Preventive Measures**: If this issue affects your workflow, consider using a dedicated terminal window for opencode.

### `libgcc_s.so.1` Dependency

When using custom glibc 2.28, `libpthread` needs `libgcc_s.so.1` for `pthread_cancel`. The startup scripts handle this by adding `$HOME/opt/gcc-9.5.0/lib64` to `LD_LIBRARY_PATH`.

**Error if not configured:**
```
libgcc_s.so.1 must be installed for pthread_cancel to work
Aborted (core dumped)
```

**Verification:**
```bash
ls -la ~/opt/gcc-9.5.0/lib64/libgcc_s.so.1
```

### Bash Subprocess Crash (RESOLVED)

- **Problem Description**: Previously, there was a severe environment isolation issue when running OpenCode with custom glibc 2.28. OpenCode could write files but could not read files or execute commands. Basic commands such as `ls`, `pwd`, `whoami`, etc., returned empty results or no output, or caused segmentation faults.
- **Root Cause**: The issue was caused by `LD_LIBRARY_PATH` being set to include custom glibc 2.28 libraries. This environment variable was inherited by opencode's subprocesses (e.g., bash). However, the system's bash is compiled with system glibc 2.17, and attempting to use custom glibc 2.28 libraries causes bash to crash with a segmentation fault.
- **Solution**:
  1. **In all startup scripts**: Do NOT set `LD_LIBRARY_PATH` to custom glibc. Since agents use a patchelf-modified interpreter or `ld-linux --library-path`, they will automatically find the correct libraries without needing `LD_LIBRARY_PATH`.
  2. **In `~/.bashrc`**: Add a check for `CURSOR_AGENT` environment variable and clear `LD_LIBRARY_PATH` when it's set. This ensures bash subprocesses use the system default glibc.
  3. **Terminal Type**: Use `TERM=xterm-256color` instead of `TERM=dumb` to ensure proper command output.
- **Status**: **RESOLVED** - The issue has been fixed. All agents can now read files and execute commands normally.
- **Debugging Method**: If you encounter similar issues (commands returning no output or segmentation faults):
  1. Check if `LD_LIBRARY_PATH` contains custom glibc paths: `echo $LD_LIBRARY_PATH`
  2. Test bash with custom glibc: `LD_LIBRARY_PATH="/path/to/custom/glibc/lib:$LD_LIBRARY_PATH" bash -c 'echo test'` — this should crash
  3. Verify the fix: Ensure startup scripts do NOT set `LD_LIBRARY_PATH` to custom glibc
  4. Verify `.bashrc`: Ensure it clears `LD_LIBRARY_PATH` when `CURSOR_AGENT` is set
  5. Check agent logs for bash command execution

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
- [opencode-legacy-glibc](https://github.com/pedropombeiro/opencode-legacy-glibc) (by @pedropombeiro) — Simpler, OpenCode-only solution using Docker-built binaries (no glibc compilation needed)
- [cursorcli-glibc-shim](https://github.com/Tao-Yida/cursorcli-glibc-shim) — Original Cursor CLI glibc shim (now merged into this repo)

---

**Last Updated**: August 9, 2026

**Author**: Yida Tao
