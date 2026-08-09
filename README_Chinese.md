<img src="assets/album.png" alt="cover" width="50%" style="display: block; margin-left: auto; margin-right: auto;" />

中文版本 | [English](README.md)

# 在 CentOS 7 上使用自定义 glibc 2.28 运行 AI 编程 Agent

**支持的 Agent：** [OpenCode](https://opencode.ai) · [Cursor CLI](https://www.cursor.com) · [Kimi Code](https://kimi.moonshot.cn) · [ZCode](https://zcode.z.ai)（远程 SSH）· **[添加你的 →](CONTRIBUTING.md)**

---

> 🎉 **现在接受 Pull Request！** 该项目整合了在旧版 Linux 系统（CentOS 7、RHEL 7 等）上运行现代 AI 编程 Agent 的脚本和教程。这些系统的默认 glibc 版本过低（2.17），无法运行需要 glibc 2.28+ 的 Agent。如果你有新的 Agent 方法，**请提交 PR！** 详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

> 💡 **仅需 OpenCode 的用户请注意**：[@pedropombeiro/opencode-legacy-glibc](https://github.com/pedropombeiro/opencode-legacy-glibc) 提供了另一种**无需编译 glibc** 的 OpenCode 专用方案。该仓库是另一位开发者维护的，如果你只使用 OpenCode 且想避免编译步骤，建议先看看那个仓库。本仓库的方案更通用（支持多个 Agent），但初始设置更多。

---

## 目录

- [支持的 Agent](#支持的-agent)
- [背景介绍](#背景介绍)
- [工作原理](#工作原理)
- [公共前置条件：编译 GCC + Make + glibc](#公共前置条件编译-gcc--make--glibc)
  - [步骤一：安装 GCC 9.5.0](#步骤一安装-gcc-9550)
  - [步骤二：安装 Make 4.2](#步骤二安装-make-42)
  - [步骤三：编译安装 glibc 2.28](#步骤三编译安装-glibc-228)
- [Agent：OpenCode](#agentopencode)
- [Agent：Cursor CLI](#agentcursor-cli)
- [Agent：Kimi Code](#agentkimi-code)
- [Agent：ZCode（远程 SSH）](#agentzcode远程-ssh)
- [Agent：Codex CLI 与 opencodex（提供商切换）](#agentcodex-cli-与-opencodex提供商切换)
- [如何添加新的 Agent](#如何添加新的-agent)
- [安全增强与防御性编程](#安全增强与防御性编程)
- [已知问题](#已知问题)
- [故障排除](#故障排除)
- [许可证](#许可证)
- [贡献](#贡献)

---

## 支持的 Agent

| Agent | 方法 | 脚本 | 状态 |
|---|---|---|---|
| [OpenCode](https://opencode.ai) | `patchelf` 解释器修改 | [`scripts/opencode_with_custom_glibc.sh`](scripts/opencode_with_custom_glibc.sh) | ✅ 维护中 |
| [Cursor CLI](https://www.cursor.com) | `ld-linux` 直接调用 | [`scripts/cursor_cli_with_custom_glibc.sh`](scripts/cursor_cli_with_custom_glibc.sh) | ✅ 维护中 |
| [Kimi Code](https://kimi.moonshot.cn) | `ld-linux` 直接调用 | [`scripts/kimi_with_custom_glibc.sh`](scripts/kimi_with_custom_glibc.sh) | ✅ 维护中 |
| [ZCode](https://zcode.z.ai)（远程 SSH） | `ld-linux` 二进制替换 | [`scripts/node`](scripts/node) | ✅ 维护中 |
| [Codex CLI](https://github.com/openai/codex)（通过 [opencodex](https://github.com/lidge-jun/opencodex) 切换提供商） | `ld-linux` 直接调用（bun 包装脚本） | —（详见[指南](#agentcodex-cli-与-opencodex提供商切换)） | ✅ 维护中 |
| **你的 Agent？** | 你的方法 | `scripts/{agent}_with_custom_glibc.sh` | 🔜 [欢迎 PR](CONTRIBUTING.md) |

---

## 背景介绍

CentOS 7 系统默认的 glibc 版本为 **2.17**，而现代 AI 编程 Agent 需要 **glibc 2.28 或更高版本**。由于 glibc 是系统核心库，直接升级系统 glibc 可能导致系统不稳定。

本项目在用户目录下编译**用户本地的 glibc 2.28**（以及 GCC 9.5.0 和 Make 4.2），并为每个编程 Agent 提供启动脚本——整个过程无需 root 权限。

本仓库最初只支持 OpenCode，现已扩展为支持多个编程 Agent（Cursor CLI、Kimi Code 等）的统一方案。

> **关于 [opencode-legacy-glibc](https://github.com/pedropombeiro/opencode-legacy-glibc)**：该仓库由 [@pedropombeiro](https://github.com/pedropombeiro) 维护，提供了另一种仅针对 OpenCode 的简化方案——使用 Docker 构建兼容版本，无需编译 glibc。如果你只需要 OpenCode 且想避免编译步骤，建议先看看那个仓库。本仓库的方案更通用（编译一次 glibc 可支持多个 Agent），但初始工作量更大。

---

## 工作原理

本项目使用两种方法：

### 方法 A：`patchelf`（适用于编译型二进制文件）
修改 Agent 二进制文件的 `.interp` 段，使其指向自定义 glibc 动态链接器。适用于 OpenCode 这种单个编译型二进制文件的 Agent。

```
patchelf --set-interpreter $HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 <binary>
```

### 方法 B：`ld-linux` 直接调用（适用于 Node.js/Python 型 Agent）
直接用 `ld-linux-x86-64.so.2 --library-path` 调用 Agent 的运行时（Node.js、Python 等），指定自定义 glibc 路径。适用于 Cursor CLI 和 Kimi Code 这类基于 Node.js 的 Agent。

```
$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 \
  --library-path $HOME/opt/glibc-2.28/lib:... \
  <node|python> <entry_point>
```

### 关键设计原则（适用于所有脚本）

1. **不要将自定义 glibc 加入 `LD_LIBRARY_PATH`** —— 系统二进制文件（bash、ls 等）使用 glibc 2.17 编译，如果继承自定义 glibc 路径会崩溃。
2. **只将 GCC lib64 路径加入 `LD_LIBRARY_PATH`** —— 解决 `libgcc_s.so.1 must be installed for pthread_cancel to work` 错误。
3. **直接设置 locale** —— 在自定义 glibc 环境下运行 `locale` 命令可能触发段错误。
4. **退出时恢复环境变量** —— 原始环境变量会被保存并在退出时恢复。

---

## 公共前置条件：编译 GCC + Make + glibc

> 在使用任何 Agent 脚本之前，只需**一次性**编译这三个组件。它们被所有 Agent 共享。

### 检查操作系统版本

```bash
cat /etc/redhat-release
# CentOS Linux release 7.9.2009 (Core)
```

### 前置条件

- CentOS 7 / RHEL 7 系统
- 用户主目录约 5GB 可用空间
- 基础编译工具（gcc、make）——如果没有，可使用 Conda 安装：
  ```bash
  conda install -c conda-forge gcc_linux-64 make
  ```
- 网络连接（用于下载源码）

**无需 root 权限。**

### 关键路径速查

| 组件 | 安装路径 |
|---|---|
| GCC 9.5.0 | `$HOME/opt/gcc-9.5.0` |
| Make 4.2 | `$HOME/opt/make-4.2` |
| glibc 2.28 | `$HOME/opt/glibc-2.28` |

---

### 步骤一：安装 GCC 9.5.0

#### 1.0 安装编译依赖

GCC 编译需要 gmp、mpfr 和 libmpc。推荐使用 Conda 安装：

```bash
conda activate your_env_name
conda install -c conda-forge gmp mpfr libmpc zlib
export CPPFLAGS="-I$CONDA_PREFIX/include $CPPFLAGS"
export LDFLAGS="-L$CONDA_PREFIX/lib $LDFLAGS"
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
```

#### 1.1 下载 GCC 源码

```bash
cd ~
mkdir -p ~/opt/src
cd ~/opt/src
wget https://ftp.gnu.org/gnu/gcc/gcc-9.5.0/gcc-9.5.0.tar.xz
tar -xf gcc-9.5.0.tar.xz
cd gcc-9.5.0
```

#### 1.2 配置和编译 GCC

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

> ⏱ GCC 编译需要 1-2 小时，请耐心等待。

#### 1.3 验证 GCC 安装

```bash
export PATH=$HOME/opt/gcc-9.5.0/bin:$PATH
export LD_LIBRARY_PATH=$HOME/opt/gcc-9.5.0/lib64:$LD_LIBRARY_PATH
gcc --version
# 应显示：gcc (GCC) 9.5.0
```

---

### 步骤二：安装 Make 4.2

**重要**：必须使用 Make **4.2** 版本，因为 4.3 和 4.4 与 glibc 2.28 存在兼容性问题。

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

验证：

```bash
export PATH=$HOME/opt/make-4.2/bin:$PATH
make --version
# 应显示：GNU Make 4.2
```

---

### 步骤三：编译安装 glibc 2.28

#### 3.1 下载 glibc

```bash
cd ~/opt/src
wget https://ftp.gnu.org/gnu/glibc/glibc-2.28.tar.xz
tar -xf glibc-2.28.tar.xz
```

#### 3.2 配置 glibc

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

**配置选项说明**：
- `--prefix=$HOME/opt/glibc-2.28`：安装到用户目录
- `--disable-mathvec`：禁用数学向量化（避免与旧工具链的兼容性问题）
- `--disable-werror`：将警告视为非致命错误

#### 3.3 编译和安装 glibc

```bash
make -j$(nproc)
make install
```

> ⏱ glibc 编译需要 30-60 分钟。

#### 3.4 验证 glibc 安装

```bash
$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 --version
# 应显示：glibc 2.28

# 或者编译运行测试程序：
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
# 应输出：GNU libc version: 2.28
```

---

## Agent：OpenCode

### 概述

[OpenCode](https://opencode.ai) 是一个开源 AI 编程助手。它是编译型二进制文件，需要 glibc 2.28+。

**方法**：`patchelf` — 修改二进制文件的解释器路径，使其使用自定义 glibc。

> 💡 **更简单的替代方案**：如果你只需要 OpenCode 且想避免编译 glibc，请查看 [@pedropombeiro/opencode-legacy-glibc](https://github.com/pedropombeiro/opencode-legacy-glibc)。它使用 Docker 构建兼容旧版 glibc 的 OpenCode 二进制文件——设置更简单，但只支持 OpenCode。本仓库的方案设置更多，但支持多个 Agent。

### 安装 OpenCode

```bash
curl -fsSL https://opencode.ai/install | bash
# 或：npm install -g opencode-ai
```

验证安装：

```bash
which opencode
# 通常在 ~/.opencode/bin/opencode
```

### 安装 patchelf

```bash
conda install -c conda-forge patchelf
# 或：pip install patchelf
patchelf --version
```

### 使用方法

```bash
# 直接从仓库运行
./scripts/opencode_with_custom_glibc.sh [参数]

# 或在 ~/.bashrc 中添加别名
opencode() {
    /path/to/repo/scripts/opencode_with_custom_glibc.sh "$@"
}
```

### 脚本：`scripts/opencode_with_custom_glibc.sh`

该脚本：
1. 将 OpenCode 二进制文件复制到临时目录
2. 使用 `patchelf --set-interpreter` 指向自定义 glibc 2.28
3. 设置 `LD_LIBRARY_PATH` 包含 GCC lib64 路径（用于 `libgcc_s.so.1`）
4. **不**将自定义 glibc 加入 `LD_LIBRARY_PATH`（避免 bash 子进程崩溃）
5. 退出时恢复所有环境变量
6. 管理终端鼠标追踪（退出时清理）

---

## Agent：Cursor CLI

### 概述

[Cursor CLI](https://www.cursor.com)（cursor-agent）是基于 Node.js 的 AI 编程 Agent，其内置的 Node.js 运行时需要 glibc 2.28+。该方法最初发布在 [cursorcli-glibc-shim](https://github.com/Tao-Yida/cursorcli-glibc-shim) 仓库中。

**方法**：`ld-linux` 直接调用 — 用自定义 glibc 动态链接器启动 Agent 内置的 Node.js 二进制文件。

### 安装 Cursor CLI

```bash
curl https://cursor.com/install | bash
```

验证安装：

```bash
which agent
# 通常在 ~/.local/bin/agent
```

### 使用方法

```bash
# 直接从仓库运行
./scripts/cursor_cli_with_custom_glibc.sh [参数]

# 或在 ~/.bashrc 中添加别名
cursor-cli() {
    /path/to/repo/scripts/cursor_cli_with_custom_glibc.sh "$@"
}
```

### 脚本：`scripts/cursor_cli_with_custom_glibc.sh`

该脚本：
1. 定位 Agent 内置的 Node.js 二进制文件（`~/.local/bin/node`）和入口文件（`index.js`）
2. 用自定义 glibc 动态链接器启动 Node.js：
   ```
   $HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 \
     --library-path $HOME/opt/glibc-2.28/lib:$HOME/opt/gcc-9.5.0/lib64:/lib64:/usr/lib64 \
     node --use-system-ca index.js [参数]
   ```
3. **不**将 glibc-2.28 加入 `LD_LIBRARY_PATH`（避免系统二进制文件崩溃）
4. 退出时恢复所有环境变量

---

## Agent：Kimi Code

### 概述

[Kimi Code](https://kimi.moonshot.cn) 是基于 Node.js 的 AI 编程助手，需要 glibc 2.28+。

**方法**：`ld-linux` 直接调用 — 与 Cursor CLI 相同的方法。

### 安装 Kimi Code

参考 Kimi Code 的官方安装指南。通常安装在 `~/.kimi-code/bin/kimi`。

### 使用方法

```bash
./scripts/kimi_with_custom_glibc.sh [参数]

# 或在 ~/.bashrc 中添加别名
kimi() {
    /path/to/repo/scripts/kimi_with_custom_glibc.sh "$@"
}
```

### 脚本：`scripts/kimi_with_custom_glibc.sh`

与 Cursor CLI 脚本相同的方法——直接用自定义 glibc 动态链接器启动 kimi 二进制文件。

---

## Agent：ZCode（远程 SSH）

### 概述

[ZCode](https://zcode.z.ai) 是一个类似 Codex 的全功能 Agentic Development Environment (ADE)，用于让 AI Agent 端到端、稳定可控地完成跨度更长、步骤更多的开发任务。其远程 SSH 功能会在远程 Linux 服务器上部署 Node.js 运行时（`~/.zcode/server/node`），并通过 SSH 直接执行——不经过 shell 别名或 `.bashrc`。

**方法**：二进制替换——将 `~/.zcode/server/node` 替换为一个包装脚本，该脚本通过自定义 glibc 动态链接器代理到原始二进制文件（重命名为 `node.real`）。

### 与其他方案的区别

OpenCode（本地二进制，`patchelf` 方案）和 Cursor CLI / Kimi Code（本地命令行，bash 别名方案）都是在本地 shell 中调用的。而 ZCode 的远程服务器是由 Windows 客户端通过 SSH 直接触发的：

```
Windows ZCode 客户端
  → SSH ~/.zcode/server/node        ← 直接 SSH 执行
  → 本脚本通过 ld-linux-x86-64.so.2 拦截
  → 用自定义 glibc 2.28 启动原始 node.real
```

由于 SSH 命令直接执行文件，**不经过**别名或 `.bashrc` 函数，必须直接替换 node 二进制文件本身。

### 安装方法

在远程 CentOS 7 服务器上，完成[公共前置条件](#公共前置条件编译-gcc--make--glibc)后：

```bash
# 1. 进入 ZCode 服务器目录
cd ~/.zcode/server

# 2. 备份原始 node 二进制
cp node node.real

# 3. 部署包装脚本（来自本仓库）
cp /path/to/centos7-coding-agents/scripts/node ~/.zcode/server/node

# 4. 赋予执行权限
chmod +x ~/.zcode/server/node
```

完成。**无需修改 `.bashrc`。**

### 验证

```bash
# 验证 node 版本
~/.zcode/server/node --version
# 应输出：v22.16.0（或你安装的版本）

# 验证 ZCode 服务端握手
~/.zcode/server/node ~/.zcode/server/zcode-server.cjs
# 应输出：{"type":"zcode-hello","version":"...","platform":"linux","arch":"x64",...}
```

验证通过后，从 Windows ZCode 客户端重新连接——远程服务器应能正常握手。

### 重要注意事项

- **ZCode 版本升级**：如果 ZCode 更新了 Node.js 运行时版本，可能会重新上传 `node` 文件覆盖包装脚本，需要重新执行上述步骤。
- **运行时版本检测**：ZCode 通过 `~/.zcode/server/.asset-components/node-runtime.json` 判断是否需要重新部署 Node。如果版本匹配则不会重新上传，因此包装脚本通常能在小版本升级后保留。
- **Agent 自动覆盖**：`~/.zcode/server/agents/glm/zcode-agent` 内部也会调用 `$runtime_root/node`，因此包装脚本同时覆盖了服务端和内部 Agent，无需额外配置。

### 脚本：`scripts/node`

该脚本是 `~/.zcode/server/node` 的即插即用替代品。它：
1. 在同目录下查找原始二进制文件（`node.real`）
2. 通过 `ld-linux-x86-64.so.2 --library-path ...` 启动它
3. 设置 `LD_LIBRARY_PATH` 仅包含 GCC 库路径（不包含 glibc）
4. 退出时恢复所有环境变量

---

## Agent：Codex CLI 与 opencodex（提供商切换）

### 概述

[Codex CLI](https://github.com/openai/codex) 在 CentOS 7 上**安装本身没有问题**，无需任何 glibc 适配。兼容性问题出现在**切换服务提供商**时：用于提供商切换的 [opencodex](https://github.com/lidge-jun/opencodex) 代理要求 Node ≥ 18 并内置 Bun 运行时，两者都需要 glibc 2.18–2.28——而 CentOS 7 默认 glibc 只有 2.17（报 `GLIBC_2.2x not found`）。

**方法**：`ld-linux` 直接调用——与 Cursor CLI、Kimi Code 所用方案相同。用 bash 包装脚本（`~/.local/bin/bun`）通过自定义 glibc 2.28 加载器（`$HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 --library-path ...`）启动 Bun，opencodex 代理以源码模式运行。

**已验证环境**：CentOS 7（glibc 2.17）· codex-cli 0.147.0 · opencodex 2.11.1 · OpenCode Go provider · 2026-08-09

### 指南文档

两份双语手册记录了完整且经过实测的操作流程（环境基线、源码安装、代理启动、提供商/模型路由、guardian 审批修复、历史会话恢复及全部已踩坑清单）：

| 主题 | 中文 | 英文 |
|---|---|---|
| opencodex 在 CentOS 7 上的部署（glibc-2.28 bun 包装脚本源码安装、代理启动、提供商与模型路由、12 个已踩坑、会话迁移） | [opencodex-centos7-handbook.md](opencodex-centos7-handbook.md) | [opencodex-centos7-handbook-EN.md](opencodex-centos7-handbook-EN.md) |
| Codex 提供商切换（deepseek → Opencode Go）与历史会话恢复（标签迁移） | [Codex提供商切换与历史记录恢复.md](Codex提供商切换与历史记录恢复.md) | [Codex-Provider-Switching-and-History-Recovery-EN.md](Codex-Provider-Switching-and-History-Recovery-EN.md) |

### 要点总结

- **Codex CLI 本身在 CentOS 7 上安装无问题**——不需要 glibc 适配。
- **切换提供商需要 opencodex**，其 Node/Bun 技术栈在 glibc 2.17 上无法运行。解决：通过 glibc-2.28 加载器包装脚本运行。**绝不能** `export LD_LIBRARY_PATH` 指向自定义 glibc——glibc 2.28 与系统 2.17 混载会段错误崩溃（exit 139）。
- **CentOS 7 无用户级 systemd**——`ocx service install` / `ocx restore back` 必然失败（`systemctl --user` → `Failed to get D-Bus connection`）；改用直接调用注入脚本 + `crontab @reboot` 开机自启。
- **CentOS 7 上不要使用 `ocx codex-shim install`**——其 ensure 步骤会 spawn 裸 Bun，在 glibc 上失败并回滚配置注入、关闭代理。
- **历史会话恢复**：Codex 按 `model_provider` 精确过滤恢复列表（openai/codex issue [#15494](https://github.com/openai/codex)）；rollout JSONL 文件从未丢失。需按正确顺序重写 JSONL 首行（正则替换，禁止 JSON round-trip）与 `state_5.sqlite` 中的 `model_provider` 标签，再重启 app-server（先改库、后重启）——否则 app-server 缓存的旧标签会被写回。

---

## 如何添加新的 Agent

我们欢迎提交 Pull Request 来添加新的编程 Agent！

### 快速开始

1. **复制模板：**
   ```bash
   cp scripts/template_with_custom_glibc.sh scripts/your_agent_with_custom_glibc.sh
   ```
2. **填写 TODO：** 设置 Agent 名称、二进制文件路径和启动方法。
3. **测试脚本：** 确保在干净的 CentOS 7 环境中运行正常。
4. **更新此 README：** 在[支持的 Agent](#支持的-agent) 表格中添加你的 Agent，并新增章节。
5. **提交 PR：** 详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

### 架构说明

大多数现代编程 Agent 分为两类：

| Agent 类型 | 示例 | 推荐方法 |
|---|---|---|
| 编译型二进制文件（Node.js 二进制、Go 二进制） | OpenCode | `patchelf` — 修改解释器 |
| 脚本型（Node.js/Python 封装） | Cursor CLI, Kimi Code | `ld-linux` — 直接调用 |

[`scripts/template_with_custom_glibc.sh`](scripts/template_with_custom_glibc.sh) 模板支持这两种方法。

---

## 安全增强与防御性编程

### 1. 避免使用可能导致段错误的命令

- **避免 `locale` 及其相关命令** — 它们链接到系统 glibc，在自定义 glibc 环境下会崩溃。
- **直接设置语言环境变量**（如 `LANG=en_US.UTF-8`），而不是运行检测命令。

### 2. 环境隔离

- **临时文件清理**：所有脚本在 `mktemp -d` 目录中创建临时文件，退出时清理。
- **`trap` 用于清理**：捕获 EXIT/INT/TERM 信号确保清理。
- **环境变量恢复**：保存原始环境变量，退出时恢复。

### 3. 终端控制

- 启动 Agent 前禁用鼠标事件追踪，退出时恢复。

---

## 已知问题

### 鼠标事件编码

- **问题描述**：所有运行过 opencode 命令的终端在运行后可能会持续生成鼠标行为的编码（如 `[[<35;23;26M` 等），这是由于 opencode 启用了终端的鼠标事件追踪功能。
- **解决方案**：暂时没有直接的解决方案，但可以通过关闭当前终端窗口或标签页来解决此问题。此问题不影响 opencode 的正常使用。
- **临时缓解**：在终端中执行 `reset` 命令可能会有所帮助，但不保证完全解决。
- **预防措施**：如果此问题影响您的工作流程，建议为 opencode 使用专用的终端窗口。

### `libgcc_s.so.1` 依赖

当使用自定义 glibc 2.28 时，`libpthread` 需要 `libgcc_s.so.1` 来支持 `pthread_cancel` 功能。启动脚本通过将 `$HOME/opt/gcc-9.5.0/lib64` 添加到 `LD_LIBRARY_PATH` 来处理此问题。

**未配置时的错误信息：**
```
libgcc_s.so.1 must be installed for pthread_cancel to work
Aborted (core dumped)
```

**验证方法：**
```bash
ls -la ~/opt/gcc-9.5.0/lib64/libgcc_s.so.1
```

### Bash 子进程崩溃（已解决）

- **问题描述**：之前，使用自定义 glibc 2.28 运行 OpenCode 时存在严重的环境隔离问题。OpenCode 能够写入文件，但无法读取文件或执行命令。基础命令如 `ls`、`pwd`、`whoami` 等返回空结果或不返回任何输出，或导致段错误。
- **根本原因**：问题是由于设置了包含自定义 glibc 2.28 库的 `LD_LIBRARY_PATH` 环境变量。这个环境变量会被 opencode 的子进程（如 bash）继承。但是，系统的 bash 是用系统 glibc 2.17 编译的，尝试使用自定义 glibc 2.28 库会导致 bash 崩溃（段错误）。
- **解决方案**：
  1. **所有启动脚本中**：不设置 `LD_LIBRARY_PATH` 指向自定义 glibc。由于 Agent 使用 patchelf 修改的解释器或 `ld-linux --library-path`，它们会自动找到正确的库。
  2. **在 `~/.bashrc` 中**：添加对 `CURSOR_AGENT` 环境变量的检查，当它被设置时清除 `LD_LIBRARY_PATH`。这确保 bash 子进程使用系统默认的 glibc。
  3. **终端类型**：使用 `TERM=xterm-256color` 而不是 `TERM=dumb`，以确保命令输出正常工作。
- **状态**：**已解决** - 问题已修复。所有 Agent 现在可以正常读取文件和执行命令。
- **调试方法**：如果遇到类似问题（命令无输出或段错误）：
  1. 检查 `LD_LIBRARY_PATH` 是否包含自定义 glibc 路径：`echo $LD_LIBRARY_PATH`
  2. 测试 bash 使用自定义 glibc：`LD_LIBRARY_PATH="/path/to/custom/glibc/lib:$LD_LIBRARY_PATH" bash -c 'echo test'` — 这应该会崩溃
  3. 验证修复：确保启动脚本没有将自定义 glibc 加入 `LD_LIBRARY_PATH`
  4. 验证 `.bashrc`：确保它在 `CURSOR_AGENT` 设置时清除 `LD_LIBRARY_PATH`
  5. 检查 Agent 日志，查看 bash 命令是否正在执行

---

## 故障排除

### 常见错误

| 错误 | 原因 | 解决方案 |
|---|---|---|
| `patchelf not found` | 未安装 patchelf | `conda install -c conda-forge patchelf` |
| `Custom glibc linker not found` | 未编译 glibc 2.28 | 参照[步骤三](#步骤三编译安装-glibc-228) |
| `libgcc_s.so.1 must be installed` | GCC 库路径缺失 | 确保 `$HOME/opt/gcc-9.5.0/lib64` 在 `LD_LIBRARY_PATH` 中 |
| 命令无输出 | LD_LIBRARY_PATH 被 bash 继承 | 使用不设置 glibc 路径的脚本 |
| `GLIBC_2.29 not found` | 二进制文件需要更新版本 | 尝试编译 glibc 2.29+ |
| 终端显示异常 | 鼠标追踪已启用 | 执行 `reset` 或关闭终端标签页 |

---

## 许可证

本项目采用 MIT 许可证，可自由使用和修改。

## 贡献

> **我们现在接受 Pull Request！** 🎉

本项目从一个只支持 OpenCode 的单 Agent 方案，发展成了支持多种 Agent 的通用兼容层。

- 详见 [CONTRIBUTING.md](CONTRIBUTING.md) 贡献指南。
- 使用[模板脚本](scripts/template_with_custom_glibc.sh)添加新的 Agent。
- 有问题或建议请提交 Issue。

**相关项目：**
- [opencode-legacy-glibc](https://github.com/pedropombeiro/opencode-legacy-glibc)（作者 @pedropombeiro）— OpenCode 专用简化方案，使用 Docker 构建兼容版本（无需编译 glibc）
- [cursorcli-glibc-shim](https://github.com/Tao-Yida/cursorcli-glibc-shim) — 原始 Cursor CLI glibc 封装（已合并到本仓库）

---

**最后更新**：2026年8月9日

**作者**：Yida Tao
