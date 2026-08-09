# opencodex Deployment & Troubleshooting Handbook on CentOS 7

> Applies to: CentOS 7 (glibc 2.17) / x86_64 / no user-level systemd
> Tool versions: codex-cli 0.147.0 + opencodex 2.11.1 (source mode, GitHub `lidge-jun/opencodex`)
> Written: 2026-08-09
> Purpose: fully document opencodex installation, startup, model routing, history recovery, and every known pitfall with its solution on CentOS 7, for future reuse.

---

## 1. Environment Baseline (CentOS 7 peculiarities)

| Item | Value | Impact |
|---|---|---|
| OS | CentOS 7 (glibc **2.17**) | **Root cause of every compatibility issue** |
| Architecture | x86_64 | Normal |
| Node | default PATH v16.20.2 (nvm has v18.17.0/v22.21.1/v24.12.0) | Node 18+ official binaries need glibc 2.25–2.28, **running them directly reports GLIBC_2.2x not found** |
| glibc compatibility layer | `~/opt/glibc-2.28/` + `~/opt/gcc-9.5.0/` | Hand-compiled; the **only reliable way to bypass the glibc limit** |
| Bun | 1.3.11 (`~/.bun/bin/bun`, ELF needs glibc 2.18+) | Must be run through a wrapper (`~/.local/bin/bun`) |
| User-level systemd | ❌ unavailable (`systemctl --user` → `Failed to get D-Bus connection`) | opencodex's `ocx service` mode **is entirely broken** |
| Display DISPLAY | none | GUI dashboard needs SSH port forwarding |
| System sqlite3 | 3.7.17 (too old) | Use `$HOME/miniconda3/bin/sqlite3` (3.51.1) |
| Kernel user namespaces | not supported | bwrap sandbox unavailable |

---

## 2. Installing opencodex (source mode, bypassing npm's Node 18 requirement)

### 2.1 Why not use the official npm install
opencodex's npm bin is a Node shim (`bin/ocx.mjs`, needs Node ≥18) that execs a bundled Bun (1.3.14) to run the TS source. This machine's default Node 16 does not satisfy that, and the bundled Bun ELF also needs glibc 2.28 — **the entire npm path is blocked by glibc**.

### 2.2 Source-mode steps (verified working)

```bash
# 1. Extract the source tarball
mkdir -p /tmp/opencodex-src && tar xzf opencodex-main.tar.gz -C /tmp/opencodex-src/

# 2. Install dependencies with the user bun wrapper (bun 1.3.11 works through the glibc-2.28 wrapper)
cd /tmp/opencodex-src/opencodex-main
export http_proxy=http://127.0.0.1:10809
export https_proxy=http://127.0.0.1:10809
~/.local/bin/bun install

# 3. Verify the CLI loads
~/.local/bin/bun run src/cli/index.ts --help
```

**Key: you MUST use `~/.local/bin/bun` (the wrapper), not `bun` or `~/.bun/bin/bun`.**

### 2.3 How the glibc wrapper works (this machine's unique solution)

`~/.local/bin/bun` is a bash script that explicitly loads the real bun with the glibc-2.28 loader:

```bash
#!/bin/bash
exec $HOME/opt/glibc-2.28/lib/ld-linux-x86-64.so.2 \
  --library-path "$HOME/opt/glibc-2.28/lib:$HOME/opt/gcc-9.5.0/lib64:/lib64:/usr/lib64" \
  $HOME/.bun/bin/bun "$@"
```

The same loader can run Node 18/22 (installed via nvm, but running directly reports GLIBC_2.27/GLIBCXX missing):

```bash
LD="~/opt/glibc-2.28/lib/ld-linux-x86-64.so.2"
LP="$HOME/opt/glibc-2.28/lib:$HOME/opt/gcc-9.5.0/lib64:/lib64:/usr/lib64"
$LD --library-path "$LP" ~/.nvm/versions/node/v18.17.0/bin/node --version   # → v18.17.0 ✅
```

### 2.4 ⚠️ Iron rule: never mix via LD_LIBRARY_PATH

```bash
export LD_LIBRARY_PATH="$HOME/opt/glibc-2.28/lib:..."   # ❌ segfault (139)
```
Mixing glibc 2.28 libraries with the system's 2.17 **crashes with a segfault**. You must use the loader's `--library-path` parameter, **never export LD_LIBRARY_PATH**.

---

## 3. Starting the Proxy (core operation)

### 3.1 Wrapper startup script `~/.local/bin/ocx-start` (verified)

```bash
~/.local/bin/ocx-start              # start
~/.local/bin/ocx-start status       # status
~/.local/bin/ocx-start stop         # stop
~/.local/bin/ocx-start restart      # restart
```

Script core (runs the source with the glibc wrapper internally):

```bash
nohup ~/.local/bin/bun run src/cli/index.ts start --port 10100 \
  > $HOME/.opencodex-logs/proxy.log 2>&1 &
```

### 3.2 Autostart on boot (systemd replacement)

User-level systemd is unavailable, so `ocx service install` necessarily fails. Use a crontab `@reboot` entry:

```bash
crontab -l > /tmp/cron.bak
echo '@reboot sleep 15 && $HOME/.local/bin/ocx-start start >> $HOME/.opencodex-logs/crontab.log 2>&1' >> /tmp/cron.bak
crontab /tmp/cron.bak
```

### 3.3 Dashboard access (no DISPLAY)

```bash
# Run on your local machine
ssh -L 10100:localhost:10100 <user>@<server>
# Open http://localhost:10100 in your browser
```

---

## 4. Configuring Provider & Model Routing

### 4.1 Adding the opencode-go provider (registry-native, API key mode)

```bash
~/.local/bin/bun run src/cli/index.ts provider add opencode-go \
  --api-key sk-xxx \
  --default-model deepseek-v4-flash \
  --set-default \
  --sync
```

**Pitfall**: the provider name MUST be the registry-native `opencode-go` (the `openai-chat` adapter). Do **not** create your own `opencodego` + `openai-responses` adapter — it gets misclassified as a Codex account pool (`codexAccountMode: pool`), and requests fail with `OpenAI account pool has no usable account credential`.

### 4.2 Injecting the Codex config (Design B)

```bash
~/.local/bin/bun run src/cli/index.ts restore back   # ⚠️ this command fails because of systemd
```

**Pitfall**: `ocx sync` / `ocx restore back` internally call `admitCodexWrite`, which uses `systemctl --user` to prove config ownership → **necessarily fails on CentOS 7** (`Refusing to write because ownership could not be proven: systemctl show exited 1`).

**Workaround**: call the injection function directly (verified working):

```bash
cat > /tmp/reinject.mjs <<'EOF'
import { injectCodexConfig } from "/tmp/opencodex-src/opencodex-main/src/codex/inject.ts";
const result = await injectCodexConfig(10100, undefined, {});
console.log("success:", result.success);
EOF
~/.local/bin/bun /tmp/reinject.mjs
```

### 4.3 Generating the model catalog

```bash
cat > /tmp/gencatalog.mjs <<'EOF'
import { syncCatalogModels } from "/tmp/opencodex-src/opencodex-main/src/codex/catalog/sync.ts";
import { loadConfig } from "/tmp/opencodex-src/opencodex-main/src/config.ts";
const result = await syncCatalogModels(loadConfig());
console.log("added:", result.added, "| path:", result.path);
EOF
~/.local/bin/bun /tmp/gencatalog.mjs
```

### 4.4 Post-injection config.toml shape (Design B, loopback default)

```toml
model = "gpt-5.6-luna"          # default model (changeable)
openai_base_url = "http://127.0.0.1:10100/v1"      # ← injected by opencodex
model_catalog_json = "$HOME/.codex/opencodex-catalog.json"  # ← injected by opencodex
```

Design B's `openai_base_url` scheme lets codex keep the native `openai` provider id, so **ChatGPT login + thread history are not remapped**.

### 4.5 Model switching (inside codex)

```bash
codex exec -m "opencode-go/deepseek-v4-flash" "task"
codex exec -m "opencode-go/kimi-k3" "task"
codex exec -m "gpt-5.6-luna" "task"        # native OpenAI model
```

### 4.6 ⚠️ Setting the default model (key to preventing bounce-back)

**Correct form**: the root `model` uses a **bare model name** (no provider prefix):
```toml
model = "deepseek-v4-flash"     # ✅ correct
# model = "opencode-go/deepseek-v4-flash"  # ❌ gets stripped by opencodex
```
**Reason**: opencodex's `stripRootRoutedModel` (inject.ts) deletes **any** root `model` line containing `/` on restore/stop. The bare name `deepseek-v4-flash` contains no `/`, so it is not stripped; and when codex routes a request through the opencodex proxy, a prefix-less model matches `opencode-go`'s `defaultModel` (`deepseek-v4-flash`) and routes correctly.

**Change command**:
```bash
sed -i 's/^model\s*=.*/model = "deepseek-v4-flash"/' ~/.codex/config.toml
```
**Verified**: neither injection (reinject), app-server restarts, nor `ocx stop` overwrite this line. End-to-end `codex exec` goes through deepseek-v4-flash by default (DS_DEFAULT/FINAL verified).

---

## 5. Complete List of Pitfalls Encountered

### 5.1 Bare Bun segfault / missing GLIBC (most frequent)
**Symptom**: proxy fails to start; `ocx ensure` reports `Proxy did not become healthy`.
**Root cause**: opencodex internally does `spawn(process.execPath, startArgv(...))` with the bare bun ELF (needs glibc 2.18+); CentOS 7 reports `GLIBC_2.18/2.24/2.25 not found` directly.
**Solution**: start the proxy manually with `ocx-start` (the wrapper); do not rely on ocx auto-spawning.

### 5.2 `ocx service install` fails
**Symptom**: dashboard shows "startup protection AT RISK / unable to read startup protection status".
**Root cause**: user-level systemd unavailable (cannot connect to D-Bus).
**Impact**: the proxy is not auto-started after reboot (use crontab instead).
**Classification**: **environment limitation, not a config error**. The proxy itself, the injection, and routing all work normally.

### 5.3 `ocx codex-shim install` has destructive side effects (important)
**Symptom**: after installing the shim, running codex triggers an ensure failure and **removes the config.toml injection and stops the proxy**.
**Root cause**: the shim's ensure spawns bare bun internally and fails → `syncCleanup` restores the native config.
**Conclusion**: **do not use the shim on CentOS 7**. Already tested and uninstalled.

### 5.4 Custom provider name causes account-pool misclassification
**Symptom**: after `provider add opencodego` (custom name), requests fail with `OpenAI account pool has no usable account credential`.
**Root cause**: `openai-responses` adapter + non-registry name → `providerCodexAccountMode` looks up the registry and assigns `pool`.
**Solution**: use the registry-native `opencode-go` (the `openai-chat` adapter, API key auth).

### 5.5 token_revoked / weird login state
**Symptom**: TUI reports `token_revoked`; `codex login status` is intermittently good/bad.
**Root cause**: **the app-server process cached an invalidated old ChatGPT token** (read at startup; not restarted after login refresh).
**Solution**: restart app-server (`kill <pid>` + start manually) so it re-reads auth.json.

### 5.6 426 Upgrade Required warning (normal behavior)
**Symptom**: codex startup log reports `HTTP error: 426 Upgrade Required, url: ws://127.0.0.1:10100/v1/responses`.
**Truth**: codex's built-in openai provider hardcodes trying WebSocket first; when opencodex disables websocket it returns 426 so codex **cleanly falls back to HTTP** (`WebsocketStreamOutcome::FallbackToHttp`). **Not an error**; everything works normally.

### 5.7 GUI build needs Node 20+ (not 18)
**Symptom**: gui dependencies (vite 8, eslint 10) require Node `^20.19.0 || ^22.13.0`.
**Solution**: run **Node 22.21.1** (already in nvm) with the glibc-2.28 loader + npm install gui dependencies + vite build.

### 5.8 fd limit (bun install fails)
**Symptom**: `bun install` reports `low max file descriptors (Unexpected), Current limit: 4096`.
**Root cause**: system hard limit is 4096, cannot be raised (unprivileged user).
**Solution**: install gui dependencies with **npm** (run Node 22 via the loader) instead of bun install.

### 5.9 ⚠️ `ocx stop` / `ocx-start stop` restores the native Codex config (most insidious)
**Symptom**: after stopping the proxy, the `openai_base_url`/`model_catalog_json` injection is removed from `config.toml`, and `opencodex-catalog.json` degrades back to 9 native OpenAI models (all opencode models disappear).
**Root cause**: opencodex design behavior — on SIGTERM the proxy runs `syncCleanup()`, **automatically restoring the Codex config to native** ("stop and restore native Codex"). This is the intended semantics of `ocx stop`, not a bug.
**Impact**: any "stop proxy → edit config → restart proxy" operation (e.g. session history migration) also wipes the injection.
**Solution**: after stopping the proxy you must **re-inject + force-rebuild the catalog**:
```bash
# 1. Re-inject (Design B)
~/.local/bin/bun /tmp/reinject.mjs

# 2. Force-rebuild the catalog (must delete first, otherwise sync decides "no update needed" and added:0)
rm -f ~/.codex/opencodex-catalog.json
~/.local/bin/bun /tmp/gencatalog.mjs    # expect added: 22+
```
**Acceptance criteria**: after rebuild, `python3 -c "import json; d=json.load(open('~/.codex/opencodex-catalog.json')); print(len(d['models']))"` should be 29 (22 opencode + 7 native).
**Prevention**: for operations like session migration, if you do not need the proxy, skip `ocx-start stop` and only stop app-server (stopping app-server does not trigger opencodex's syncCleanup).

### 5.10 ⚠️ guardian approval failure (response_format unsupported + fix)
**Symptom**: `Automatic approval review failed: Provider error 400: This response_format type is unavailable now`.
**Root-cause chain** (verified):
1. codex guardian approval requests carry `text.format.json_schema` (structured output)
2. opencodex's `opencode-go` provider uses `adapter=openai-chat` → forwards it as the chat API's `response_format.json_schema`
3. **Console Go (DeepSeek chat) upstream rejects json_schema** → 400 → approval fail-closed
4. whereas **opencode.ai's `/responses` endpoint natively supports json_schema** (verified HTTP 200)

**Verification**:
```bash
# chat-completions path (what opencodex uses) → 400
curl -sS -x http://127.0.0.1:10809 https://opencode.ai/zen/go/v1/chat/completions \
  -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"review"}],
       "response_format":{"type":"json_schema","json_schema":{"name":"r","schema":{"type":"object"}}}}'
# → 400 This response_format type is unavailable now

# /responses path (direct) → 200
curl -sS -x http://127.0.0.1:10809 https://opencode.ai/zen/go/v1/responses \
  -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-flash","input":"review",
       "text":{"format":{"type":"json_schema","name":"r","schema":{"type":"object","properties":{"outcome":{"type":"string"}}}}}}'
# → 200 valid JSON
```

**Fix (11000 local proxy splits traffic by feature)**: `$HOME/opt/deepseek-proxy/proxy.js`
- **Approval requests** (model=`codex-auto-review` or carries `json_schema`) → **connect directly to opencode `/responses`** (native support)
- **Main conversation requests** (no json_schema) → forward to opencodex (10100)
- Key implementation:
  ```js
  const hasJsonSchema = !!(parsed.text?.format?.type === 'json_schema' || parsed.response_format?.type === 'json_schema');
  const isReview = parsedModel.includes('codex-auto-review') || hasJsonSchema;
  // Direct connection: strip the opencode-go/ prefix from the model name + remove the duplicate /v1 from the URL
  parsed.model = 'deepseek-v4-flash';  // direct opencode only accepts bare names
  const upstreamPath = req.url.replace(/^\/v1/, '');  // OPENCODE_DIRECT already contains /v1
  ```

**Verification results** (tested 2026-08-09):
| Request | Path | Result |
|---|---|---|
| deepseek-v4-flash + json_schema | `[review-direct]` opencode | ✅ 200 |
| top-level response_format.json_schema | `[review-direct]` opencode | ✅ 200 |
| streaming approval (stream) | `[review-direct]` opencode | ✅ 200 |
| main conversation (no json_schema) | opencodex 10100 | ✅ 200 |
| **real approval (end-to-end)** | `[review-direct]` opencode | ✅ **200 allowed** |

**⚠️ What NOT to do**: do not switch the whole config back to `model_provider=opencodego` direct connection — that reroutes **all** models and makes the session history (filtered by provider) disappear entirely. **Only the approval model** should go direct; main conversations stay on opencodex.

### 5.11 ✅ Approval final fix (2026-08-09, end-to-end verified)

**Full root-cause chain** (extending 5.10 to the final resolution):
1. **zstd compression**: codex 0.147's `enable_request_compression` feature defaults ON → the approval request body is zstd-compressed (entropy ≈ 8) → the 11000 proxy cannot parse it (`parse-error: Unexpected token (`)
2. **Model name prefix**: the approval model carries the `opencode-go/` prefix, and opencode /responses only accepts bare names → 401 `Model opencode-go/deepseek-v4-flash is not supported`
3. **Final fix** (three key points in proxy.js):
   ```js
   // 1. Turn off codex compression (config.toml [features])
   [features]
   enable_request_compression = false   // ← approval body becomes plaintext JSON

   // 2. Proxy recognizes approvals (isReview) + strips the prefix
   const isReviewRequest = m === 'codex-auto-review' || m.endsWith('/codex-auto-review')
     || !!(parsed.text?.format?.type === 'json_schema')
     || !!(parsed.response_format?.type === 'json_schema');
   if (isReviewRequest) {
     parsed.model = m.includes('/') ? m.slice(m.indexOf('/') + 1) : m;  // strip opencode-go/
   }
   ```

**End-to-end real-approval evidence** (11000 proxy log, 2026-08-09 22:00):
```
[13:59:52.331Z] req model=opencode-go/deepseek-v4-flash isReview=true textFormat=json_schema
  body="You are judging one planned coding-agent action... derive outcome from the security policy"
[14:00:07.062Z] POST /v1/responses -> 200 rewrote=3 [review-direct]
```
- ✅ `enc=-` (plaintext, compression off)
- ✅ `[review-direct]` (direct opencode /responses)
- ✅ `rewrote=3` (stripped prefix + json_object + json prompt)
- ✅ HTTP 200 → the command executed successfully (exit 0)

**Related opencodex official issues** (verified in lidge-jun/opencodex):
- **#1338** (closed by bot): 2.11.x structured-output 400 regression, **not officially fixed yet**
- **#1225** (open): feature request for custom auto-review model config, not implemented
- **#637/#816/#833**: codex-auto-review routing pinned to the canonical openai provider
- **#985/#1137**: origin of unconditionally forwarding response_format

**Essence of this machine's solution**: it does not rely on an opencodex fix; a local 11000 proxy splits **approval requests** (feature = json_schema) to connect directly to opencode /responses (native support), while main conversations stay on opencodex. This works for any opencodex version.

### 5.12 ✅ Approval model override approach (better; pinned at the Codex framework layer)

**Problem**: the 5.11 approach depends on the proxy rewriting the model name, but when the **main model itself has a flawed streaming response** (e.g. mimo-v2.5 only pushes `response.output_text.delta` + an empty `response.completed`, so guardian cannot parse the final text), even a correctly handling proxy produces empty output and fails closed.

**Better approach**: use the catalog's `auto_review_model_override` to pin the approval model to deepseek-v4-flash at the **Codex framework layer** — approval requests go directly to deepseek (streaming works), independent of the main model.

**Root-cause chain** (why approval follows the main model):
- every entry in the opencodex-generated catalog has `auto_review_model_override: null` (31/31)
- codex guardian's `guardian_review_model_overridden` mechanism: catalog has an override → use it; no override → use the current turn's model (the main model)
- main model mimo-v2.5's stream lacks the `message`/`output_text` summary structure → guardian gets empty output

**Fix** (edit both catalog + models_cache):
```bash
# 1. Set the override for all opencode-go entries in the catalog
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

# 2. Restart app-server to apply
PID=$(fuser ~/.codex/app-server-control/app-server-control.sock | tr -d ' ')
[ -n "$PID" ] && kill $PID
sleep 3
nohup codex -c features.code_mode_host=true app-server --listen unix:// \
  > ~/.codex/app-server-control/app-server.log 2>&1 &
```

**End-to-end evidence** (11000 proxy log, 2026-08-09 22:18, main model mimo-v2.5):
```
[14:18:09.009Z] req model=opencode-go/deepseek-v4-flash isReview=true textFormat=json_schema  ← approval pinned to deepseek!
[14:18:19.438Z] POST /v1/responses -> 200 rewrote=3 [review-direct]  ← allowed
```
- ✅ approval model = `deepseek-v4-flash` (override took effect, not mimo)
- ✅ `[review-direct]` + `rewrote=3` + `enc=-` plaintext
- ✅ command executed successfully (exit 0, output: `override-test-1`)

**Why it is better**:
1. Pins the approval model at the **Codex framework layer** (`guardian_review_model_override`), not dependent on the proxy rewriting the model name
2. Works with **any main model** (including ones with flawed streaming like mimo)
3. Consistent with the official workaround for opencodex issue #1225

**⚠️ Notes**:
- catalog/models_cache are generated by opencodex; the **next `ocx sync` rebuilds them and may clear the override** (re-run the script above)
- if you switch the main model, the override stays pinned to deepseek (exactly what we want)
- the `review_model` config key is **ineffective** (codex 0.147's guardian does not use it); the override is the correct mechanism

---

## 6. Session History Recovery (label migration, verified in this workspace)

### 6.1 Root cause (openai/codex issue #15494)
The resume list is filtered **exactly** by `model_provider`. After a provider switch, old sessions "disappear", but the rollout files are never lost.

### 6.2 Key files
| Path | Purpose |
|---|---|
| `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | Session content; **first line** `session_meta.payload.model_provider` |
| `~/.codex/state_5.sqlite` | `threads` table: app-side session list (includes provider, archived) |
| `/tmp/session_restore_backup_*` | historical backups (files + DB) |

### 6.3 Recovery steps (strict order!)

```
⚠️ Order iron rule: stop app-server first → edit files → edit DB → start app-server again
   otherwise app-server reads the old provider from the files into memory, and session activity writes it back to the files/DB
```

1. **Stop all codex/app-server processes** (including the proxy, to avoid any session activity):
```bash
PID=$(fuser ~/.codex/app-server-control/app-server-control.sock | tr -d ' ')
[ -n "$PID" ] && kill $PID
~/.local/bin/ocx-start stop
```

2. **Edit the JSONL first line** `model_provider` — ⚠️ **must use regex replacement, never a JSON round-trip**:
```bash
# ✅ correct: regex replaces only the value, keeping every other byte of the first line unchanged
python3 - "$FILE" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'rb') as f:
    first_line = f.readline()
    rest = f.read()
# Compatible with both spellings: "model_provider": "x" and "model_provider":"x"
new_first = re.sub(rb'("model_provider"\s*:\s*")([^"]*)(")',
                   rb'\g<1>openai\g<3>', first_line, count=1)
with open(path, 'wb') as f:
    f.write(new_first + rest)
PYEOF

# ❌ wrong approach (causes "failed to read session metadata: does not start with session metadata"):
# json.loads(first_line) → json.dumps(d, ensure_ascii=False) re-serializes the whole first line
#   → changes the JSON byte layout / breaks the line structure, codex cannot recognize session_meta
```

> **⚠️ round-trip trap (lesson learned the hard way)**: `json.loads` + `json.dumps` rewriting the first line breaks the JSONL line structure,
> causing codex to report `failed to read session metadata ... does not start with session metadata` —
> the title is visible but the content cannot be loaded. Fix: **restore the original file from backup + regex replacement** (see step 2).
> Acceptance criteria: after the change, `json.loads(first line)` must parse completely, and the first line's byte length should only differ by the model_provider value.

3. **Edit the DB** (use miniconda3's sqlite3; the system one is too old):
```bash
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite "
UPDATE threads SET model_provider='openai', archived=0 WHERE id IN ('...','...');
"
```

4. **Start the proxy + app-server**:
```bash
~/.local/bin/ocx-start start
nohup codex -c features.code_mode_host=true app-server --listen unix:// \
  > ~/.codex/app-server-control/app-server.log 2>&1 &
```

5. **Verify** (DB + file double-confirmed consistent):
```bash
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite \
  "SELECT id, model_provider, archived FROM threads WHERE id IN ('...');"
head -1 <rollout-file> | grep -o '"model_provider":"[^"]*"'
```

### 6.4 Archived sessions must be unarchived first
```bash
codex unarchive <session-id>     # official command
```

### 6.5 ⚠️ Missed sessions: one session ID may have multiple rollout files
**Symptom**: after migrating the target sessions, the DB scan still finds sessions from other providers.
**Root cause**: one session ID can correspond to **multiple rollout files** (main session + child/forked sessions), e.g. `019fdd8a-7ec2-...` and `019fdd8a-b68b-...`. Migrating only the first file matched by `find` misses the other files with the same ID.
**Correct approach**: **do not look up files one by one by ID**; instead scan the whole DB for sessions of non-target providers and migrate them in bulk:
```bash
# 1. List all IDs to migrate from the whole DB
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite \
  "SELECT id FROM threads WHERE model_provider != 'openai';" > /tmp/migrate_ids.txt

# 2. For each: find files (possibly multiple) → regex replace → update DB
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

# 3. Update the whole DB
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite \
  "UPDATE threads SET model_provider='openai' WHERE model_provider != 'openai';"
```

### 6.6 Full migration verification (28 sessions verified on this machine)
Hands-on 2026-08-09: besides the 6 target sessions, **16 deepseek + 12 opencodego = 28 sessions** were also found unmigrated (titles all "The following is the Codex age..."). After migrating everything:
```bash
# Whole-DB provider distribution should be: openai|0|N (no other non-archived provider sessions)
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite \
  "SELECT model_provider, archived, count(*) FROM threads GROUP BY model_provider, archived;"
# expected output: openai|0|49  (or more, all openai)
```
**Iron rule after migration**: wait 10 seconds and re-check the DB — if a provider was written back by app-server (e.g. `deepseek|0|N` reappears), the file fix was incomplete (app-server read the old value from the files and wrote it back to the DB); stop the services and fix again.

---

## 7. Common Command Quick Reference

```bash
# Proxy
~/.local/bin/ocx-start {start|stop|restart|status}

# Proxy status
curl -s http://localhost:10100/healthz

# Injection / catalog (direct-call method bypassing systemd, see 4.2/4.3)
~/.local/bin/bun /tmp/reinject.mjs
~/.local/bin/bun /tmp/gencatalog.mjs

# codex verification
codex login status
codex exec -m "opencode-go/deepseek-v4-flash" "Reply with exactly: OK"
codex doctor

# app-server restart (required after token refresh)
PID=$(fuser ~/.codex/app-server-control/app-server-control.sock | tr -d ' ')
kill $PID && sleep 3
nohup codex -c features.code_mode_host=true app-server --listen unix:// \
  > ~/.codex/app-server-control/app-server.log 2>&1 &

# Backups
cp ~/.codex/config.toml ~/.codex/config.toml.bak.$(date +%Y%m%d%H%M%S)
$HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite ".backup '/tmp/state_5_$(date +%Y%m%d%H%M%S).sqlite'"
```

---

## 8. Final Status (verified 2026-08-09)

| Item | Status |
|---|---|
| opencodex proxy | ✅ running (opencode-go provider, API key) |
| codex login | ✅ native ChatGPT login (auth.json valid) |
| Codex routing | ✅ Design B injection (openai_base_url → localhost:10100) |
| Model catalog | ✅ 29 models (22 opencode-go + 7 native OpenAI) |
| Model switching | ✅ `-m opencode-go/deepseek-v4-flash` verified OK |
| Session history | ✅ all 6 sessions restored (provider=openai, archived=0) |
| Autostart on boot | ⚠️ crontab @reboot (systemd unavailable) |
| Startup protection notice | ⚠️ dashboard AT RISK (environment limitation, not a fault) |
