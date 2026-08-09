# opencodex 在 CentOS 7 上的部署与问题处理手册

> 适用环境：CentOS 7 (glibc 2.17) / x86_64 / 无用户级 systemd
> 工具版本：codex-cli 0.147.0 + opencodex 2.11.1（源码模式，GitHub `lidge-jun/opencodex`）
> 编写日期：2026-08-09
> 目的：完整记录 opencodex 在 CentOS 7 上的安装、启动、模型路由、历史恢复，以及全部已知坑与解法，供后续复用。

---

## 1. 环境基线（CentOS 7 的特殊性）

| 项目 | 值 | 影响 |
|---|---|---|
| 操作系统 | CentOS 7 (glibc **2.17**) | **一切兼容性问题的根源** |
| 架构 | x86_64 | 正常 |
| Node | 默认 PATH v16.20.2（nvm 有 v18.17.0/v22.21.1/v24.12.0） | Node 18+ 官方二进制需 glibc 2.25-2.28，**直接跑报 GLIBC_2.2x not found** |
| glibc 兼容层 | `~/opt/glibc-2.28/` + `~/opt/gcc-9.5.0/` | 已手工编译，是**绕过 glibc 限制的唯一可靠方案** |
| Bun | 1.3.11（`~/.bun/bin/bun`，ELF 需 glibc 2.18+） | 必须通过 wrapper（`~/.local/bin/bun`）运行 |
| 用户级 systemd | ❌ 不可用（`systemctl --user` → `Failed to get D-Bus connection`） | opencodex 的 `ocx service` 模式**全部失效** |
| 显示器 DISPLAY | 无 | GUI 仪表盘需 SSH 端口转发 |
| 系统 sqlite3 | 3.7.17（太旧） | 需用 `$HOME/miniconda3/bin/sqlite3`（3.51.1） |
| 内核 user namespaces | 不支持 | bwrap 沙箱不可用 |

---

## 2. 安装 opencodex（源码模式，绕过 npm 的 Node 18 限制）

### 2.1 为什么不用 npm 官方安装
opencodex 的 npm bin 是 Node shim（`bin/ocx.mjs`，需 Node ≥18），它 exec bundled Bun（1.3.14）跑 TS 源码。本机默认 Node 16 不满足，且 bundled Bun ELF 同样需要 glibc 2.28 —— **npm 路径全链路被 glibc 卡死**。

### 2.2 源码模式步骤（已验证可行）

```bash
# 1. 解压源码包
mkdir -p /tmp/opencodex-src && tar xzf opencodex-main.tar.gz -C /tmp/opencodex-src/

# 2. 用用户 bun wrapper 装依赖（bun 1.3.11 已通过 glibc-2.28 wrapper 工作）
cd /tmp/opencodex-src/opencodex-main
export http_proxy=http://127.0.0.1:10809
export https_proxy=http://127.0.0.1:10809
~/.local/bin/bun install

# 3. 验证 CLI 能加载
~/.local/bin/bun run src/cli/index.ts --help
```

**关键：必须用 `~/.local/bin/bun`（wrapper），不能用 `bun` 或 `~/.bun/bin/bun`。**

### 2.3 glibc wrapper 原理（本机独有方案）

`~/.local/bin/bun` 是一个 bash 脚本，用 glibc-2.28 的 loader 显式加载真 bun：

```bash
#!/bin/bash
exec $HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 \
  --library-path "$HOME/opt/glibc-2.28/lib:$HOME/opt/gcc-9.5.0/lib64:/lib64:/usr/lib64" \
  $HOME/.bun/bin/bun "$@"
```

同理可用此 loader 跑 Node 18/22（nvm 装的，但直接跑报 GLIBC_2.27/GLIBCXX 缺失）：

```bash
LD="~/opt/glibc-2.28/lib/ld-linux-x86-64.so.2"
LP="$HOME/opt/glibc-2.28/lib:$HOME/opt/gcc-9.5.0/lib64:/lib64:/usr/lib64"
$LD --library-path "$LP" ~/.nvm/versions/node/v18.17.0/bin/node --version   # → v18.17.0 ✅
```

### 2.4 ⚠️ 铁律：禁止 LD_LIBRARY_PATH 混用

```bash
export LD_LIBRARY_PATH="$HOME/opt/glibc-2.28/lib:..."   # ❌ 段错误 (139)
```
glibc 2.28 库与系统 2.17 混载会**段错误崩溃**。必须用 loader 的 `--library-path` 参数，**绝不能 export LD_LIBRARY_PATH**。

---

## 3. 启动代理（核心操作）

### 3.1 封装启动脚本 `~/.local/bin/ocx-start`（已验证）

```bash
~/.local/bin/ocx-start              # 启动
~/.local/bin/ocx-start status       # 状态
~/.local/bin/ocx-start stop         # 停止
~/.local/bin/ocx-start restart      # 重启
```

脚本核心（内部用 glibc wrapper 跑源码）：

```bash
nohup ~/.local/bin/bun run src/cli/index.ts start --port 10100 \
  > $HOME/.opencodex-logs/proxy.log 2>&1 &
```

### 3.2 开机自启（替代 systemd）

用户级 systemd 不可用，`ocx service install` 必然失败。用 crontab `@reboot`：

```bash
crontab -l > /tmp/cron.bak
echo '@reboot sleep 15 && $HOME/.local/bin/ocx-start start >> $HOME/.opencodex-logs/crontab.log 2>&1' >> /tmp/cron.bak
crontab /tmp/cron.bak
```

### 3.3 仪表盘访问（无 DISPLAY）

```bash
# 本地电脑执行
ssh -L 10100:localhost:10100 <user>@<server>
# 浏览器打开 http://localhost:10100
```

---

## 4. 配置 Provider 与模型路由

### 4.1 添加 opencode-go provider（registry 原生，API key 模式）

```bash
~/.local/bin/bun run src/cli/index.ts provider add opencode-go \
  --api-key sk-xxx \
  --default-model deepseek-v4-flash \
  --set-default \
  --sync
```

**坑**：provider 名必须是 registry 原生的 `opencode-go`（`openai-chat` adapter），**不能自建 `opencodego` + `openai-responses` adapter** —— 后者会被误判为 Codex 账户池（`codexAccountMode: pool`），请求报 `OpenAI account pool has no usable account credential`。

### 4.2 注入 Codex 配置（Design B）

```bash
~/.local/bin/bun run src/cli/index.ts restore back   # ⚠️ 此命令因 systemd 失败
```

**坑**：`ocx sync` / `ocx restore back` 内部走 `admitCodexWrite`，它用 `systemctl --user` 证明配置所有权 → **CentOS 7 必然失败**（`Refusing to write because ownership could not be proven: systemctl show exited 1`）。

**绕过方法**：直接调注入函数（已验证可行）：

```bash
cat > /tmp/reinject.mjs <<'EOF'
import { injectCodexConfig } from "/tmp/opencodex-src/opencodex-main/src/codex/inject.ts";
const result = await injectCodexConfig(10100, undefined, {});
console.log("success:", result.success);
EOF
~/.local/bin/bun /tmp/reinject.mjs
```

### 4.3 生成模型目录（catalog）

```bash
cat > /tmp/gencatalog.mjs <<'EOF'
import { syncCatalogModels } from "/tmp/opencodex-src/opencodex-main/src/codex/catalog/sync.ts";
import { loadConfig } from "/tmp/opencodex-src/opencodex-main/src/config.ts";
const result = await syncCatalogModels(loadConfig());
console.log("added:", result.added, "| path:", result.path);
EOF
~/.local/bin/bun /tmp/gencatalog.mjs
```

### 4.4 注入后的 config.toml 形态（Design B，loopback 默认）

```toml
model = "gpt-5.6-luna"          # 默认模型（可改）
openai_base_url = "http://127.0.0.1:10100/v1"      # ← opencodex 注入
model_catalog_json = "$HOME/.codex/opencodex-catalog.json"  # ← opencodex 注入
```

Design B 的 `openai_base_url` 方案让 codex 保留原生 `openai` provider id，**ChatGPT 登录 + 线程历史不重映射**。

### 4.5 模型切换（codex 中使用）

```bash
codex exec -m "opencode-go/deepseek-v4-flash" "任务"
codex exec -m "opencode-go/kimi-k3" "任务"
codex exec -m "gpt-5.6-luna" "任务"        # 原生 OpenAI 模型
```

### 4.6 ⚠️ 设置默认模型（防回弹关键）

**正确写法**：root `model` 用**裸模型名**（不含 provider 前缀）：
```toml
model = "deepseek-v4-flash"     # ✅ 正确
# model = "opencode-go/deepseek-v4-flash"  # ❌ 会被 opencodex 剥离
```
**原因**：opencodex 的 `stripRootRoutedModel`（inject.ts）会在 restore/stop 时删除**任何含 `/` 的 root `model` 行**。裸名 `deepseek-v4-flash` 不含 `/`，不会被剥离；且 codex 通过 opencodex 代理请求时，无前缀模型会匹配 `opencode-go` 的 `defaultModel`（`deepseek-v4-flash`）正确路由。

**修改命令**：
```bash
sed -i 's/^model\s*=.*/model = "deepseek-v4-flash"/' ~/.codex/config.toml
```
**已验证**：注入（reinject）、app-server 重启、`ocx stop` 均不会覆盖该行。端到端 `codex exec` 默认走 deepseek-v4-flash（DS_DEFAULT/FINAL 实测通过）。

---

## 5. 已踩坑清单（完整）

### 5.1 裸 Bun 段错误 / GLIBC 缺失（最高频）
**现象**：代理启动失败、`ocx ensure` 报 `Proxy did not become healthy`。
**根因**：opencodex 内部 `spawn(process.execPath, startArgv(...))` 用裸 bun ELF（需 glibc 2.18+），CentOS 7 直接报 `GLIBC_2.18/2.24/2.25 not found`。
**解决**：手动用 `ocx-start`（wrapper）启动代理，不要依赖 ocx 自动拉起。

### 5.2 `ocx service install` 失败
**现象**：仪表盘"启动保护 AT RISK / 无法读取启动保护状态"。
**根因**：用户级 systemd 不可用（D-Bus 连不上）。
**影响**：重启后代理不会自动拉起（用 crontab 替代）。
**定性**：**环境限制，非配置错误**。代理本身、注入、路由全部正常。

### 5.3 `ocx codex-shim install` 破坏性副作用（重要）
**现象**：shim 安装后，跑 codex 触发 ensure 失败，且**把 config.toml 注入移除 + 关闭代理**。
**根因**：shim 的 ensure 内部 spawn 裸 bun 失败 → `syncCleanup` 恢复原生 config。
**结论**：**CentOS 7 上不要用 shim**。已实测并卸载。

### 5.4 自定义 provider 名导致账户池误判
**现象**：`provider add opencodego`（自建名）后请求报 `OpenAI account pool has no usable account credential`。
**根因**：`openai-responses` adapter + 非 registry 名 → `providerCodexAccountMode` 查 registry 赋 `pool`。
**解决**：用 registry 原生 `opencode-go`（`openai-chat` adapter，API key 认证）。

### 5.5 token_revoked / 登录状态诡异
**现象**：TUI 报 `token_revoked`、`codex login status` 时好时坏。
**根因**：**app-server 进程缓存了失效的旧 ChatGPT token**（启动时读取，登录刷新后未重启）。
**解决**：重启 app-server（`kill <pid>` + 手动拉起），让它重新读 auth.json。

### 5.6 426 Upgrade Required 警告（正常现象）
**现象**：codex 启动日志报 `HTTP error: 426 Upgrade Required, url: ws://127.0.0.1:10100/v1/responses`。
**真相**：codex 内置 openai provider 硬编码先试 WebSocket，opencodex 关闭 websocket 时返回 426 让 codex **干净回退 HTTP**（`WebsocketStreamOutcome::FallbackToHttp`）。**非错误**，功能完全正常。

### 5.7 GUI 构建需 Node 20+（不是 18）
**现象**：gui 依赖（vite 8、eslint 10）要求 Node `^20.19.0 || ^22.13.0`。
**解决**：用 glibc-2.28 loader 跑 **Node 22.21.1**（nvm 已有）+ npm 装 gui 依赖 + vite build。

### 5.8 fd 限制（bun install 失败）
**现象**：`bun install` 报 `low max file descriptors (Unexpected), Current limit: 4096`。
**根因**：系统硬限制 4096，无法提升（非特权用户）。
**解决**：gui 依赖改用 **npm**（Node 22 loader 跑）而非 bun install。

### 5.9 ⚠️ `ocx stop` / `ocx-start stop` 会恢复原生 Codex 配置（最隐蔽）
**现象**：停止代理后，`config.toml` 的 `openai_base_url`/`model_catalog_json` 注入被移除，`opencodex-catalog.json` 退化回 9 个原生 OpenAI 模型（opencode 模型全部消失）。
**根因**：opencodex 的设计行为 —— 代理收到 SIGTERM 时执行 `syncCleanup()`，**自动把 Codex 配置恢复为原生**（"停止并恢复原生 Codex"）。这是 `ocx stop` 的既定语义，不是 bug。
**影响**：任何"停代理 → 改配置 → 重启代理"的操作（如历史会话迁移）都会连带清掉注入。
**解决**：停止代理后需**重新注入 + 强制重建 catalog**：
```bash
# 1. 重新注入 (Design B)
~/.local/bin/bun /tmp/reinject.mjs

# 2. 强制重建 catalog (必须先删除, 否则 sync 判定"无需更新" added:0)
rm -f ~/.codex/opencodex-catalog.json
~/.local/bin/bun /tmp/gencatalog.mjs    # 期望 added: 22+
```
**判定标准**：重建后 `python3 -c "import json; d=json.load(open('~/.codex/opencodex-catalog.json')); print(len(d['models']))"` 应为 29（22 opencode + 7 原生）。
**预防**：迁移会话等操作时，若不需要代理，可跳过 `ocx-start stop`，只停 app-server（app-server 的停止不会触发 opencodex 的 syncCleanup）。

### 5.10 ⚠️ guardian 审批失败（response_format 不支持 + 修复方案）
**现象**：`Automatic approval review failed: Provider error 400: This response_format type is unavailable now`。
**根因链**（已实测）：
1. codex guardian 审批请求带 `text.format.json_schema`（结构化输出）
2. opencodex 的 `opencode-go` provider 用 `adapter=openai-chat` → 转发成 chat 的 `response_format.json_schema`
3. **Console Go（DeepSeek chat）上游拒绝 json_schema** → 400 → 审批 fail-closed
4. 而 **opencode.ai `/responses` 端点原生支持 json_schema**（已验证 HTTP 200）

**验证**：
```bash
# chat-completions 路径 (opencodex 用的) → 400
curl -sS -x http://127.0.0.1:10809 https://opencode.ai/zen/go/v1/chat/completions \
  -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"review"}],
       "response_format":{"type":"json_schema","json_schema":{"name":"r","schema":{"type":"object"}}}}'
# → 400 This response_format type is unavailable now

# /responses 路径 (直连) → 200
curl -sS -x http://127.0.0.1:10809 https://opencode.ai/zen/go/v1/responses \
  -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-flash","input":"review",
       "text":{"format":{"type":"json_schema","name":"r","schema":{"type":"object","properties":{"outcome":{"type":"string"}}}}}}'
# → 200 合法 JSON
```

**修复方案（11000 本地代理按特征分流）**：`$HOME/opt/deepseek-proxy/proxy.js`
- **审批请求**（模型=`codex-auto-review` 或 带 `json_schema`）→ **直连 opencode `/responses`**（原生支持）
- **主对话请求**（无 json_schema）→ 转发 opencodex（10100）
- 关键实现：
  ```js
  const hasJsonSchema = !!(parsed.text?.format?.type === 'json_schema' || parsed.response_format?.type === 'json_schema');
  const isReview = parsedModel.includes('codex-auto-review') || hasJsonSchema;
  // 直连时: 模型名去掉 opencode-go/ 前缀 + URL 去掉重复 /v1
  parsed.model = 'deepseek-v4-flash';  // 直连 opencode 只认裸名
  const upstreamPath = req.url.replace(/^\/v1/, '');  // OPENCODE_DIRECT 已含 /v1
  ```

**验证结果**（2026-08-09 实测）：
| 请求 | 路径 | 结果 |
|---|---|---|
| deepseek-v4-flash + json_schema | `[review-direct]` opencode | ✅ 200 |
| 顶层 response_format.json_schema | `[review-direct]` opencode | ✅ 200 |
| 流式审批 (stream) | `[review-direct]` opencode | ✅ 200 |
| 主对话 (无 json_schema) | opencodex 10100 | ✅ 200 |
| **真实审批（端到端）** | `[review-direct]` opencode | ✅ **200 放行** |

**⚠️ 不要做的**：把整个 config 切回 `model_provider=opencodego` 直连 —— 这会让**所有**模型改道，且会话历史（按 provider 过滤）全部消失。**只有审批模型**应走直连，主对话保持 opencodex。

### 5.11 ✅ 审批最终修复（2026-08-09 端到端验证通过）

**完整根因链**（从 5.10 延伸到最终解决）：
1. **zstd 压缩**：codex 0.147 的 `enable_request_compression` feature 默认 ON → 审批请求 body 被 zstd 压缩（熵≈8）→ 11000 代理解析不了（`parse-error: Unexpected token (`）
2. **模型名前缀**：审批模型带 `opencode-go/` 前缀，opencode /responses 只认裸名 → 401 `Model opencode-go/deepseek-v4-flash is not supported`
3. **最终修复**（proxy.js 三个关键点）：
   ```js
   // 1. 关闭 codex 压缩 (config.toml [features])
   [features]
   enable_request_compression = false   // ← 审批 body 变明文 JSON

   // 2. 代理识别审批 (isReview) + 剥前缀
   const isReviewRequest = m === 'codex-auto-review' || m.endsWith('/codex-auto-review')
     || !!(parsed.text?.format?.type === 'json_schema')
     || !!(parsed.response_format?.type === 'json_schema');
   if (isReviewRequest) {
     parsed.model = m.includes('/') ? m.slice(m.indexOf('/') + 1) : m;  // 剥 opencode-go/
   }
   ```

**端到端真实审批证据**（11000 代理日志，2026-08-09 22:00）：
```
[13:59:52.331Z] req model=opencode-go/deepseek-v4-flash isReview=true textFormat=json_schema
  body="You are judging one planned coding-agent action... derive outcome from the security policy"
[14:00:07.062Z] POST /v1/responses -> 200 rewrote=3 [review-direct]
```
- ✅ `enc=-`（明文，压缩已关）
- ✅ `[review-direct]`（直连 opencode /responses）
- ✅ `rewrote=3`（剥前缀 + json_object + json 提示词）
- ✅ HTTP 200 → 命令成功执行（exit 0）

**opencodex 官方 issue 关联**（已查证 lidge-jun/opencodex）：
- **#1338**（closed by bot）：2.11.x 结构化输出 400 回归，**尚未官方修复**
- **#1225**（open）：自定义 auto-review 模型配置功能请求，未实现
- **#637/#816/#833**：codex-auto-review 路由 pin 到 canonical openai provider
- **#985/#1137**：引入无条件转发 response_format 的源头

**本机方案本质**：不依赖 opencodex 修复，用本地 11000 代理把**审批请求**（特征 = json_schema）分流直连 opencode /responses（原生支持），主对话保持 opencodex。此方案对任何 opencodex 版本都有效。

### 5.12 ✅ 审批模型 override 方案（更优，Codex 框架层钉死）

**问题**：5.11 方案依赖代理层改写模型名，但当**主模型本身流式响应有缺陷**（如 mimo-v2.5 只推 `response.output_text.delta` + 空 `response.completed`，guardian 解析不到最终文本）时，即使代理正确处理也会空输出 fail-closed。

**更优方案**：用 **catalog 的 `auto_review_model_override`** 在 Codex 框架层把审批模型钉死为 deepseek-v4-flash —— 审批请求直接发 deepseek（流式正常），不依赖主模型。

**根因链**（为什么审批跟随主模型）：
- opencodex 生成的 catalog 所有条目 `auto_review_model_override: null`（31/31）
- codex guardian 的 `guardian_review_model_overridden` 机制：catalog 有 override → 用 override；无 → 用当前轮次模型（主模型）
- 主模型 mimo-v2.5 流式缺 `message`/`output_text` 汇总结构 → guardian 空输出

**修复**（改 catalog + models_cache 双份）：
```bash
# 1. catalog 所有 opencode-go 条目设置 override
python3 - <<'PYEOF'
import json
for path in ['~/.codex/opencodex-catalog.json', '~/.codex/models_cache.json']:
    p = __import__('os').path.expanduser(path)
    d = json.load(open(p))
    for m in d['models']:
        if m['slug'].startswith('opencode-go/'):
            m['auto_review_model_override'] = 'opencode-go/deepseek-v4-flash'
    json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False)
PYEOF

# 2. 重启 app-server 生效
PID=$(fuser ~/.codex/app-server-control/app-server-control.sock | tr -d ' ')
[ -n "$PID" ] && kill $PID
sleep 3
nohup codex -c features.code_mode_host=true app-server --listen unix:// \
  > ~/.codex/app-server-control/app-server.log 2>&1 &
```

**端到端证据**（11000 代理日志，2026-08-09 22:18，主模型 mimo-v2.5）：
```
[14:18:09.009Z] req model=opencode-go/deepseek-v4-flash isReview=true textFormat=json_schema  ← 审批固定 deepseek!
[14:18:19.438Z] POST /v1/responses -> 200 rewrote=3 [review-direct]  ← 放行
```
- ✅ 审批模型 = `deepseek-v4-flash`（override 生效，非 mimo）
- ✅ `[review-direct]` + `rewrote=3` + `enc=-` 明文
- ✅ 命令成功执行（exit 0，output: `override-test-1`）

**为什么更优**：
1. 在 **Codex 框架层**钉死审批模型（`guardian_review_model_override`），不依赖代理层改写模型名
2. 对**任何主模型**（含 mimo 这类流式有缺陷的）都有效
3. 与 opencodex issue #1225 的官方 workaround 一致

**⚠️ 注意事项**：
- catalog/models_cache 是 opencodex 生成的，**下次 `ocx sync` 会重建并可能清掉 override**（需重新执行上面的脚本）
- 若切换主模型，override 仍钉死 deepseek（这正是我们想要的）
- `review_model` 配置项**无效**（codex 0.147 guardian 不用它），override 才是正确机制

---

## 6. 历史会话恢复（标签迁移，本工作区已验证）

### 6.1 根因（openai/codex issue #15494）
恢复列表按 `model_provider` **精确过滤**。切换提供商后旧会话"消失"，但 rollout 文件从未丢失。

### 6.2 关键文件
| 路径 | 作用 |
|---|---|
| `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | 会话内容；**首行** `session_meta.payload.model_provider` |
| `~/.codex/state_5.sqlite` | `threads` 表：应用侧会话列表（含 provider、archived） |
| `/tmp/session_restore_backup_*` | 历史备份（文件 + DB） |

### 6.3 恢复步骤（严格顺序！）

```
⚠️ 顺序铁律：先停 app-server → 改文件 → 改 DB → 再启 app-server
   否则 app-server 从文件读旧 provider 进内存，会话活动会写回文件/DB
```

1. **停止所有 codex/app-server 进程**（含代理，避免任何会话活动）：
```bash
PID=$(fuser ~/.codex/app-server-control/app-server-control.sock | tr -d ' ')
[ -n "$PID" ] && kill $PID
~/.local/bin/ocx-start stop
```

2. **改 JSONL 首行** `model_provider` —— ⚠️ **必须用正则替换，严禁 JSON round-trip**：
```bash
# ✅ 正确做法: 正则只替换值, 保持首行其他字节完全不变
python3 - "$FILE" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'rb') as f:
    first_line = f.readline()
    rest = f.read()
# 兼容两种写法: "model_provider": "x" 和 "model_provider":"x"
new_first = re.sub(rb'("model_provider"\s*:\s*")([^"]*)(")',
                   rb'\g<1>openai\g<3>', first_line, count=1)
with open(path, 'wb') as f:
    f.write(new_first + rest)
PYEOF

# ❌ 错误做法 (会导致 "failed to read session metadata: does not start with session metadata"):
# json.loads(first_line) → json.dumps(d, ensure_ascii=False) 重新序列化整个首行
#   → 改变 JSON 字节布局 / 拆断行结构, codex 无法识别 session_meta
```

> **⚠️ round-trip 陷阱（血泪教训）**：`json.loads` + `json.dumps` 重写首行会破坏 JSONL 行结构，
> 导致 codex 报 `failed to read session metadata ... does not start with session metadata`，
> 标题可见但内容无法加载。修复方法：**从备份恢复原始文件 + 正则替换**（见步骤 2）。
> 判定标准：改完后 `json.loads(首行)` 必须完整可解析，且首行字节长度只变化 model_provider 值差。

3. **改 DB**（用 miniconda3 的 sqlite3，系统版太旧）：
```bash
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite "
UPDATE threads SET model_provider='openai', archived=0 WHERE id IN ('...','...');
"
```

4. **启动代理 + app-server**：
```bash
~/.local/bin/ocx-start start
nohup codex -c features.code_mode_host=true app-server --listen unix:// \
  > ~/.codex/app-server-control/app-server.log 2>&1 &
```

5. **验证**（DB + 文件双确认一致）：
```bash
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite \
  "SELECT id, model_provider, archived FROM threads WHERE id IN ('...');"
head -1 <rollout-file> | grep -o '"model_provider":"[^"]*"'
```

### 6.4 归档会话需先 unarchive
```bash
codex unarchive <session-id>     # 官方命令
```

### 6.5 ⚠️ 漏网会话：同一会话 ID 可能有多个 rollout 文件
**现象**：迁移了目标会话后，DB 扫描仍发现其他 provider 的会话。
**根因**：一个会话 ID 可能对应**多个 rollout 文件**（主会话 + 子/分叉会话），如 `019fdd8a-7ec2-...` 和 `019fdd8a-b68b-...`。只迁移 `find` 命中的第一个文件会漏掉同 ID 的其他文件。
**正确做法**：**不要按 ID 逐个找文件**，改为**全库扫描非目标 provider 的会话**批量迁移：
```bash
# 1. 全库列出所有待迁移 ID
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite \
  "SELECT id FROM threads WHERE model_provider != 'openai';" > /tmp/migrate_ids.txt

# 2. 逐个: 找文件(可能多个) → 正则替换 → 更新 DB
while read -r id; do
  [ -z "$id" ] && continue
  find ~/.codex/sessions -name "rollout-*$id.jsonl" | while read -r F; do
    python3 - "$F" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'rb') as f:
    first_line = f.readline(); rest = f.read()
new_first = re.sub(rb'("model_provider"\s*:\s*")([^"]*)(")',
                   rb'\g<1>openai\g<3>', first_line, count=1)
with open(path, 'wb') as f: f.write(new_first + rest)
PYEOF
  done
done < /tmp/migrate_ids.txt

# 3. 全库更新 DB
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite \
  "UPDATE threads SET model_provider='openai' WHERE model_provider != 'openai';"
```

### 6.6 全量迁移验证（本机实测 28 会话）
2026-08-09 实操：除目标 6 个会话外，还发现 **16 个 deepseek + 12 个 opencodego = 28 个会话**未迁移（标题均为 "The following is the Codex age..."）。全部迁移后：
```bash
# 全库 provider 分布应为: openai|0|N (无其他 provider 未归档会话)
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite \
  "SELECT model_provider, archived, count(*) FROM threads GROUP BY model_provider, archived;"
# 期望输出: openai|0|49  (或更多, 全部为 openai)
```
**迁移后铁律**：等 10 秒复查 DB —— 若 provider 被 app-server 写回（如 `deepseek|0|N` 复现），说明文件修复不彻底（app-server 从文件读旧值写回 DB），需重新停服务再修。

---

## 7. 常用命令速查

```bash
# 代理
~/.local/bin/ocx-start {start|stop|restart|status}

# 代理状态
curl -s http://localhost:10100/healthz

# 注入 / catalog（绕过 systemd 的 direct-call 方法，见 4.2/4.3）
~/.local/bin/bun /tmp/reinject.mjs
~/.local/bin/bun /tmp/gencatalog.mjs

# codex 验证
codex login status
codex exec -m "opencode-go/deepseek-v4-flash" "Reply with exactly: OK"
codex doctor

# app-server 重启（token 刷新后必须）
PID=$(fuser ~/.codex/app-server-control/app-server-control.sock | tr -d ' ')
kill $PID && sleep 3
nohup codex -c features.code_mode_host=true app-server --listen unix:// \
  > ~/.codex/app-server-control/app-server.log 2>&1 &

# 备份
cp ~/.codex/config.toml ~/.codex/config.toml.bak.$(date +%Y%m%d%H%M%S)
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite ".backup '/tmp/state_5_$(date +%Y%m%d%H%M%S).sqlite'"
```

---

## 8. 最终状态（2026-08-09 验证）

| 项目 | 状态 |
|---|---|
| opencodex 代理 | ✅ 运行中（opencode-go provider, API key） |
| codex 登录 | ✅ ChatGPT 原生登录（auth.json 有效） |
| Codex 路由 | ✅ Design B 注入（openai_base_url → localhost:10100） |
| 模型目录 | ✅ 29 模型（22 个 opencode-go + 7 个 OpenAI 原生） |
| 模型切换 | ✅ `-m opencode-go/deepseek-v4-flash` 实测 OK |
| 历史会话 | ✅ 6 个会话全部恢复（provider=openai, archived=0） |
| 开机自启 | ⚠️ crontab @reboot（systemd 不可用） |
| 启动保护提示 | ⚠️ 仪表盘 AT RISK（环境限制，非故障） |
