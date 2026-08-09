# Codex Provider Switching & Session History Recovery Handbook

> Applies to: this machine (`$HOME`), Codex Desktop / CLI v0.147.0.
> Purpose: record the complete, verified procedure for "switching the service provider (deepseek → Opencode Go)" and "recovering disappeared historical sessions" for future reuse.

## 1. Background & Problem

**Symptom**: After switching the login method / service provider, old sessions "disappear" from `codex resume` and the history list.

**Root cause** (verified; corresponds to known openai/codex issue #15494):

- Codex's resume list is filtered **exactly** by `model_provider`: it only shows sessions whose `model_provider` matches the current one.
- When switching providers, if the old provider's `[model_providers.*]` config block was deleted, old sessions not only vanish from the list, but restoring by ID also fails with `Model provider 'xxx' not found`.
- The session content files (`~/.codex/sessions/.../rollout-*.jsonl`) are **never lost** — they are just "invisible + unloadable".

## 2. Key File Locations

| Path | Purpose |
|---|---|
| `~/.codex/config.toml` | Main config: `model`, `model_provider`, `[model_providers.*]` blocks, API Key |
| `~/.codex/models.json` | Model catalog (e.g. `auto_review_model_override`) |
| `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | Session content; the first line's `session_meta` contains `model_provider` |
| `~/.codex/state_5.sqlite` | `threads` table: app-side session list, includes the `model_provider` column |
| `~/.codex/session_index.jsonl` | Session title index |
| `~/.codex/app-server-control/` | Desktop app-server socket, logs, launch scripts |
| `~/.codex/config.toml.bak.*` / `models.json.bak.*` | Historical config backups |

## 3. Provider Switching Procedure (deepseek → Opencode Go, same model)

Prerequisite: **the model stays the same** (currently `deepseek-v4-flash`); Opencode Go connection parameters:

```toml
[model_providers.opencodego]
name = "opencodego"
base_url = "https://opencode.ai/zen/go/v1/"
wire_api = "responses"
experimental_bearer_token = "sk-zoTF...（Opencode Go API Key）"
```

Steps:

1. **Back up the config**: `cp ~/.codex/config.toml ~/.codex/config.toml.bak.<timestamp>`
2. **Change the provider**: set `model_provider = "opencodego"` in `config.toml`; leave `model = "deepseek-v4-flash"` untouched.
3. **Keep the old provider block**: it is recommended to keep `[model_providers.deepseek]` so old sessions can still be loaded by ID; only switch the currently active `model_provider`.
4. **Verify the endpoint works** (network reachable, model produces output):

   ```bash
   curl -sS -X POST 'https://opencode.ai/zen/go/v1/responses' \
     -H 'Content-Type: application/json' \
     -H 'Authorization: Bearer <API Key>' \
     -d '{"model":"deepseek-v4-flash","input":"Reply with exactly: OK","max_output_tokens":10}'
   ```

   HTTP 200 with model output means everything is fine.

5. **Restart app-server to apply the config** (the desktop app automatically spawns a new instance):

   ```bash
   # Find the current app-server and restart it
   ps -ef | grep 'app-server --listen unix://' | grep -v grep
   kill <PID>          # The desktop app auto-restarts; if it does not within a few seconds, start it manually
   umask 077
   nohup codex -c features.code_mode_host=true app-server --listen unix:// \
     > ~/.codex/app-server-control/app-server.log 2>&1 &
   ```

## 4. History Recovery Procedure (label migration)

**Root cause recap**: the resume list is filtered by `model_provider`; also, the app-server caches each thread's provider value at startup, and session activity writes the cached value back to the database. So the correct order is: **update the database first, then restart app-server** — otherwise the stale cache writes the old label back and the sessions "disappear" again.

Steps:

1. **Back up**:

   ```bash
   BK=/tmp/session_restore_backup_<timestamp>; mkdir -p $BK
   cp ~/.codex/sessions/YYYY/MM/DD/rollout-<id>.jsonl $BK/
   $HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite ".backup '$BK/state_5.sqlite'"
   ```

2. **Edit file metadata**: in each session JSONL, change `model_provider` in the **first line**'s `session_meta` to the current provider (rewrite in place, keep the inode, touch nothing else). Note: JSON has two spellings — `"model_provider": "xxx"` (with a space) and `"model_provider":"xxx"` (compact).

3. **Edit the database**:

   ```sql
   UPDATE threads SET model_provider='opencodego'
   WHERE id IN ('019fd895-...','019fdd66-...', ...);
   ```

4. **Restart app-server** (edit the DB first, then restart — avoids the stale cache writing back).
5. **Verify**: all sessions are visible in `codex resume --all`; double-check that `threads.model_provider` matches the first line of each file.

## 5. The Six Historical Sessions (this workspace)

| Session Title | Full ID |
|---|---|
| Restore history | `019fe128-8d6a-7f53-8db1-384301a70157` |
| I gave you a task earlier to install apptainer... (rollback cleanup) | `019fdd66-85ad-7050-9196-7576a89173a3` |
| Codex remote connection | `019fe13a-deae-7043-9b94-436f8f7c5986` |
| Evaluate the innovation and feasibility of the research plan | `019fdd8a-7ec2-7171-8ffd-ac73359f25ce` |
| /goal Please try to safely install Apptainer in my user environment and deploy the vLLM framework | `019fd895-904d-7732-bd31-26d3c6d43dcb` |
| In this conversation, I need you to help me check why the codex update timed out | `019fdd76-d818-7f61-9455-6ee02eebf3f0` |

> Note: the June 11 paper appendix session (`019eb615`) lives in another workspace `/mnt/<user>/Math_Paper_ETL` and has been archived; it is normal for it not to appear in the default list.

## 6. Common Pitfalls & Notes

- **Old sessions hiding after a provider switch is known behavior** (issue #15494): fewer items in the list after switching login method ≠ data loss — first check whether the files still exist.
- **Do not delete the old provider config block**: doing so makes old sessions unrestorable even by ID (`Model provider not found`).
- **app-server cache write-back**: you must restart app-server after editing the database, otherwise the first session activity writes the old label back.
- **This machine's system sqlite3 is too old** (3.7.17, no partial-index `WHERE` support): it falsely reports "malformed database schema" — use `$HOME/miniconda3/bin/sqlite3` (3.51.1) instead.
- **This machine's kernel does not support user namespaces** (bwrap unavailable): sandboxed commands and `apply_patch` both fail, so related operations must run unsandboxed (elevated).
- **API Key storage**: it lives in the `experimental_bearer_token` field of the `[model_providers.*]` block in `config.toml`; keep the old block when switching providers so old sessions can still be loaded by ID.

## 7. Backup Locations Summary

- `/tmp/session_restore_backup_20260808201522`, `/tmp/session_restore_backup2_20260808215136` (opencodego era)
- `/tmp/session_restore_backup_native_20260809034032` (native openai migration)
- `/tmp/session_restore_backup_deepseek_202608090422` (deepseek migration)
- `/tmp/session_restore_backup_opencodego_202608090430` (this opencodego migration, includes config.toml)
- `~/.codex/config.toml.bak.*`, `~/.codex/models.json.bak.*`

To roll back, restore `state_5.sqlite` and the session files from the corresponding backup.
