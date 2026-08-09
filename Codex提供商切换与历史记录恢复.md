# Codex 提供商切换与历史记录恢复手册

> 适用环境：本机（$HOME），Codex Desktop / CLI v0.147.0。
> 目的：记录“切换服务提供商（deepseek → Opencode Go）”与“找回消失的历史会话记录”的完整操作方法，供后续复用。

## 1. 背景与问题

**现象**：切换登录方式 / 服务提供商后，`codex resume` 与历史列表中的旧会话“消失”。

**根因**（已实证，对应 openai/codex 已知 issue #15494）：

- Codex 的恢复列表按 `model_provider`（提供商）**精确过滤**：只显示与当前 `model_provider` 一致的会话。
- 切换提供商时如果旧 provider 的 `[model_providers.*]` 配置块被删除，旧会话不仅从列表消失，按 ID 直接恢复还会报 `Model provider 'xxx' not found`。
- 会话内容文件（`~/.codex/sessions/.../rollout-*.jsonl`）**从未丢失**，只是“看不见 + 加载不了”。

## 2. 关键文件位置

| 路径 | 作用 |
|---|---|
| `~/.codex/config.toml` | 主配置：`model`、`model_provider`、`[model_providers.*]` 块、API Key |
| `~/.codex/models.json` | 模型目录（如 `auto_review_model_override`） |
| `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | 会话内容；首行 `session_meta` 含 `model_provider` |
| `~/.codex/state_5.sqlite` | `threads` 表：应用侧会话列表，含 `model_provider` 列 |
| `~/.codex/session_index.jsonl` | 会话标题索引 |
| `~/.codex/app-server-control/` | 桌面 app-server 的 socket、日志、启动脚本 |
| `~/.codex/config.toml.bak.*` / `models.json.bak.*` | 历史配置备份 |

## 3. 提供商切换操作（deepseek → Opencode Go，模型不变）

前提：**模型不变**（当前 `deepseek-v4-flash`）；Opencode Go 接入参数：

```toml
[model_providers.opencodego]
name = "opencodego"
base_url = "https://opencode.ai/zen/go/v1/"
wire_api = "responses"
experimental_bearer_token = "sk-zoTF...（Opencode Go API Key）"
```

步骤：

1. **备份配置**：`cp ~/.codex/config.toml ~/.codex/config.toml.bak.<时间戳>`
2. **修改提供商**：`config.toml` 中 `model_provider = "opencodego"`；`model = "deepseek-v4-flash"` 保持不动。
3. **保留旧 provider 块**：`[model_providers.deepseek]` 建议保留，方便旧会话按 ID 加载；只切换当前生效的 `model_provider`。
4. **验证端点可用**（网络通、模型能出词）：

   ```bash
   curl -sS -X POST 'https://opencode.ai/zen/go/v1/responses' \
     -H 'Content-Type: application/json' \
     -H 'Authorization: Bearer <API Key>' \
     -d '{"model":"deepseek-v4-flash","input":"Reply with exactly: OK","max_output_tokens":10}'
   ```

   返回 HTTP 200 且带模型输出即正常。

5. **重启 app-server 使配置生效**（桌面端会自动拉起新实例）：

   ```bash
   # 找到当前 app-server 并重启
   ps -ef | grep 'app-server --listen unix://' | grep -v grep
   kill <PID>          # 桌面端会自动重启；等几秒未重启则手动拉起
   umask 077
   nohup codex -c features.code_mode_host=true app-server --listen unix:// \
     > ~/.codex/app-server-control/app-server.log 2>&1 &
   ```

## 4. 历史记录恢复操作（标签迁移）

**根因回顾**：恢复列表按 `model_provider` 过滤；且 app-server 启动时会缓存线程的 provider 值，会话活动会把缓存写回数据库。所以正确顺序是：**先改数据库，再重启 app-server**，否则旧缓存会把旧标签写回去，会话再次“消失”。

步骤：

1. **备份**：

   ```bash
   BK=/tmp/session_restore_backup_<时间戳>; mkdir -p $BK
   cp ~/.codex/sessions/YYYY/MM/DD/rollout-<id>.jsonl $BK/
   $HOME/miniconda3/bin/sqlite3 ~/.codex/state_5.sqlite ".backup '$BK/state_5.sqlite'"
   ```

2. **改文件元数据**：把每个会话 JSONL **首行** `session_meta` 里的 `model_provider` 改为当前 provider（就地改写、保持 inode，不动其余内容）。注意 JSON 有两种写法：`"model_provider": "xxx"`（带空格）与 `"model_provider":"xxx"`（紧凑）。

3. **改数据库**：

   ```sql
   UPDATE threads SET model_provider='opencodego'
   WHERE id IN ('019fd895-...','019fdd66-...', ...);
   ```

4. **重启 app-server**（先改库、再重启，避免旧缓存写回）。
5. **验证**：`codex resume --all` 中可见全部会话；复核 `threads.model_provider` 与文件首行一致。

## 5. 六个历史会话清单（本工作区）

| 会话标题 | 完整 ID |
|---|---|
| 恢复历史记录 | `019fe128-8d6a-7f53-8db1-384301a70157` |
| 我之前交给了你一个任务，让你安装appotainer…（回退清理） | `019fdd66-85ad-7050-9196-7576a89173a3` |
| Codex远程连接 | `019fe13a-deae-7043-9b94-436f8f7c5986` |
| 评估研究计划的创新与可行性 | `019fdd8a-7ec2-7171-8ffd-ac73359f25ce` |
| /goal 请你尝试安全地在我的用户环境中安装 Apptainer 并部署 vLLM 框架 | `019fd895-904d-7732-bd31-26d3c6d43dcb` |
| 在这个对话中，我需要你帮助我检查codex更新超时的原因 | `019fdd76-d818-7f61-9455-6ee02eebf3f0` |

> 注：6 月 11 日的论文附录会话（`019eb615`）位于另一工作区 `/mnt/<user>/Math_Paper_ETL` 且已归档，默认列表不显示属正常现象。

## 6. 常见坑与注意事项

- **切 provider 后旧会话隐藏是已知行为**（issue #15494）：切换登录方式后列表变少≠数据丢失，先看文件是否还在。
- **不要删旧 provider 配置块**：删了会导致旧会话按 ID 也无法恢复（`Model provider not found`）。
- **app-server 缓存写回**：改完数据库必须重启 app-server，否则会话一活动就把旧标签写回去。
- **本机系统 sqlite3 太旧**（3.7.17，不支持部分索引 `WHERE`）：会误报 “malformed database schema”，请用 `$HOME/miniconda3/bin/sqlite3`（3.51.1）。
- **本机内核不支持 user namespaces**（bwrap 不可用）：沙箱内命令与 `apply_patch` 都会失败，相关操作需以非沙箱方式（提权）执行。
- **API Key 存放**：写在 `config.toml` 的 `[model_providers.*]` 块 `experimental_bearer_token` 中；切换提供商时保留原块即可继续按 ID 加载旧会话。

## 7. 备份位置汇总

- `/tmp/session_restore_backup_20260808201522`、`/tmp/session_restore_backup2_20260808215136`（opencodego 时代）
- `/tmp/session_restore_backup_native_20260809034032`（原生 openai 迁移）
- `/tmp/session_restore_backup_deepseek_202608090422`（deepseek 迁移）
- `/tmp/session_restore_backup_opencodego_202608090430`（本次 opencodego 迁移，含 config.toml）
- `~/.codex/config.toml.bak.*`、`~/.codex/models.json.bak.*`

需要回滚时，用对应备份覆盖 `state_5.sqlite` 与会话文件即可。
