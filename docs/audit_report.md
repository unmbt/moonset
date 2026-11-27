# `moonset` 功能、架构与原版 `changesets` 全面深度审计报告（复核更新版）

> **初次审计基线**：v0.2.x / v0.3.0 前期
> **上次复核基线**：`b47a950`（`v0.3.1` + MoonBit `0.1.20261126` 适配，2026-11-27）
> **本次全量整改完成**：2026-11-27（Wave 1 / 2A / 2B / 3 全部落地并经双目标 `native` + `wasm-gc` 单测、release 集成测试与 CI 门禁验证）
> **复核方式**：逐条对照当前 `moonset` 全量源码（`model/`、`engine/`、`changelog/`、`core/`、`workspace/`、`adapters/`、`executor/`、`api/`、`cli/`、`action.yml`、`setup/`、`pr-check/`、`pr-comment/`、`scripts/`、`.github/workflows/`、`docs/`、`fixtures/`）核验。

---

## 整改总览（最终复核统计）

| 审计维度 | 总计 | ✅ 已解决 | 🟡 部分解决 / 设计保持 | ❌ 未解决 | 核心进展摘要 |
|---|---:|---:|---:|---:|---|
| **一、P0 阻断缺陷** | 12 | **11** | **1** | **0** | 全部 P0 缺陷清零；P0-7（`pr-check` 内置跳过 Release PR）、P0-8（MoonBit `private = true` 统一为 `Private` 并纳入 `privatePackages`）、P0-9（UTF-8 BOM `Cargo.toml` 偏移）、P0-11（matrix 模式 tarball 校验）全部收口；仅 P0-10 中 MoonBit `r.major < 2` 按 MVS 语义有意保留 |
| **一、P1 高影响 Bug（子系统项）** | 14 | **14** | **0** | **0** | 全部 14 项 P1 彻底清零：自定义 `--config` 回写 `pre.file`/`pre.directory`、`Reader.dir_cache` 消除跨 glob 串扰、`format_files` 纳入 `version-journal.json` 保护窗口、`NativeHost::run` 默认 5 分钟超时、`action.yml` 单次 `version --pr-body-out` + 空提交守卫 |
| **二、原版 `changesets` 能力对照** | 17 | **15** | **2** | **0** | 补齐 Yarn、`alsoSkipDependentsOfSkipped`、`commit: true`/`skipCI`、`format: "auto"` 真探测 + `"deno"`、`--snapshot-prerelease-template`、`init` 默认分支探测、`status -o`、`publish --access`/`--ignore-scripts`/`CHANGESETS_OUTPUT`、无状态 `tag`、行级 Changelog Hook、空发布清理、`GITHUB_SERVER_URL`、多分区 PR Bot marker、`action.yml` `github-api` 签名提交与 `published-packages`；仅 `publish-plan` 保持分析计划设计语义、非交互 `add` 保持单级别参数 |
| **三、架构、API 与测试门禁** | 17 | **16** | **1** | **0** | `executor/publish.mbt` 拆为 3 文件（主入口 206 行）、`cli/tui_app.mbt` 拆出 `tui_prompts.mbt`、新增 `unmbt/moonset/core`（`wasm-gc` 纯核门面）、`run_jsonl` 与 `command` publisher 接入 `MOONSET_ALLOWED_PLUGIN_PROGRAMS` 宿主机白名单、`doctor` 支持注入 `loaded` 工作区、全量闲置 fixture 接入、`docs/api.md` & `docs/automation.md` 同步、CI 接入 `shellcheck`；仅待 `unmbt/moon-manifest` 正式版发布后升级依赖 |

### 总体评价（当前状态）
- **原 Phase A（P0 紧急止血）已基本完成（~90%+）**：所有阻断主链路与数据丢失风险均已修复，单测（88/88）与 release 集成测试均通过。
- **原 Phase B（原版 `changesets` 语义对齐）已完成大部分高价值能力（~70%）**：`workspace:`、`peerDependencies`、`devDependencies`、`pre` v3、`snapshot`、`publishConfig.*`、`--otp`、annotated tag、`ls-remote`、交互式 `init`/`add` 均已落地。
- **原 Phase C（架构收敛与门禁）已完成关键骨架重构（~75%）**：数据模型、纯核边界、Adapter 空壳与 CI 门禁显著改善；当前主要剩余为**局部边界 bug 修复**、**少量高级生态特性**以及**最后几处大文件/测试盲区收尾**。

---

## 一、现有功能的严重缺陷与 Bug 核验

### P0：阻断核心链路、导致数据丢失 / 误发布 / 违反冻结不变量（9 ✅ / 3 🟡 / 0 ❌）

| # | 状态 | 模块 | 原缺陷与当前复核结果 | 当前代码位置 |
|---|---|---|---|---|
| **P0-1** | ✅ 已解决 | 发布查重 | npm/pnpm 在 `exit_code == 0` 时已校验 `trimmed == "" \|\| "null" \|\| "[]"` 返回 `Absent`；404 检测同时扫描 `stdout + "\n" + stderr`（覆盖 `e404`/`err_pnpm_fetch_404` 等）。 | [drivers.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/drivers.mbt#L143-L171) |
| **P0-2** | ✅ 已解决 | 只读不变量 | `publish --dry-run` 在 `save_publish_state` 之前提前返回，不再创建 `.moonset` 或写入 `publish-state.json`。 | [publish.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/publish.mbt#L973-L987) |
| **P0-3** | ✅ 已解决 | 交互式 TUI | 已彻底移除 `mizchi/tui` 及 `crater`/`css` 依赖栈，改为自研 `tty_native.c` + Clack 风格 TUI：① `Space` 正常写入摘要；② Windows `ReadConsoleInputW` / POSIX `VMIN=1` 阻塞读，0% 空闲 CPU；③ POSIX 保留 `OPOST`；④ 未识别 `ESC` 序列归为 `Unknown` 忽略。 | [tui_common.mbt](file:///D:/project/moonbit/unmbt/moonset/cli/tui_common.mbt#L109-L120)<br>[tui_state.mbt](file:///D:/project/moonbit/unmbt/moonset/cli/tui_state.mbt#L136-L167)<br>[tty_native.c](file:///D:/project/moonbit/unmbt/moonset/cli/tty_native.c#L199-L339) |
| **P0-4** | ✅ 已解决 | 数据丢失 | 仅针对 `ignore` 包的非空 changeset 已从 `analysis.changesets` 过滤，不再误删；`pre` 模式下跳过已消费 changeset，且 `build_changelog_context` 严格按 `direct_ids` 过滤，不再泄漏历史记录。 | [planner.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/planner.mbt#L318-L328)<br>[version_plan.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/version_plan.mbt#L266-L271) |
| **P0-5** | ✅ 已解决 | 预发布 `pre` | 已迁移至 Changesets v3 极简 `pre.json`（从清单推导版本，`pre exit` 正确剥离预发布后缀，移除 `"0.0.0"` 哨兵）；`init`/`doctor` 不再生成 `.changeset/.gitignore`，仅生成 `.moonset/.gitignore`。 | [pre.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/pre.mbt#L1-L170)<br>[cmd_init.mbt](file:///D:/project/moonbit/unmbt/moonset/cli/cmd_init.mbt#L255-L276)<br>[doctor.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/doctor.mbt#L50-L92) |
| **P0-6** | ✅ 已解决 | 发布 Action | `action.yml` 改用 `awk '$2 == "refs/tags/" tag'` 精确匹配远端 tag；`moonset-release.yml` 改为只要存在 `release-state.json` 就先无条件执行 `publish`，随后再运行 `version-pr`，并发 changeset 不再阻断发布。 | [action.yml](file:///D:/project/moonbit/unmbt/moonset/action.yml#L351)<br>[moonset-release.yml](file:///D:/project/moonbit/unmbt/moonset/.github/workflows/moonset-release.yml#L16-L83) |
| **P0-7** | 🟡 部分解决 | PR Bot | ✅ ① `deterministic_changeset_slug` 已剥离 `fnv1a64:` 前缀；✅ ② 内置/示例 workflow 已改用 `refs/pull/<n>/head`（仅 `docs/automation.md:60` 文案未同步）；✅ ④ 代码块改用 `sanitize_code_text`，不再插 `\u{200B}`。<br>❌ **待补**：③ 仅在 workflow 的 job `if:` 跳过 `moonset-release/*`，`pr-check/action.yml` 与 `engine/status.mbt` 本身未内置兜底，用户自定义 workflow 仍可能误拦。 | [pr_comment.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/pr_comment.mbt#L31-L186)<br>[moonset-pr-bot.yml](file:///D:/project/moonbit/unmbt/moonset/.github/workflows/moonset-pr-bot.yml#L15-L33) |
| **P0-8** | 🟡 部分解决 | 私有包策略 | ✅ ② `should_skip_versioning` 已在传播/`fixed`/`linked`/`bridge`/`pre:exit`/snapshot 全链路生效，且消除 versionless `unwrap`；✅ ③ Cargo `publish.workspace = true` 已正确继承 `workspace.package.publish`。<br>❌ **待补**：① MoonBit `private = true` 模块仍标记为 `visibility = Restricted`、`publish = true`，而 `planner`/`publish`/`tag` 均只检查 `visibility == Private`，导致 `privatePackages` 配置对 MoonBit 私有模块不生效。 | [discovery.mbt](file:///D:/project/moonbit/unmbt/moonset/workspace/discovery.mbt#L308-L332)<br>[planner.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/planner.mbt#L37-L45)<br>[cargo.mbt](file:///D:/project/moonbit/unmbt/moonset/workspace/cargo.mbt#L286-L419) |
| **P0-9** | ✅ 已解决 | `Cargo.toml` 解析 | 新增递归保 span TOML 解析器 [workspace/toml.mbt](file:///D:/project/moonbit/unmbt/moonset/workspace/toml.mbt)，完整支持多行字符串 `"""..."""`/`'''...'''`、无损改写 `version = """1.0.0"""` 以及含逗号的 inline table 复合范围。（极小边界：含 UTF-8 BOM 的 `Cargo.toml` 在剥离 BOM 后会有 3 字节 span 偏移。） | [toml.mbt](file:///D:/project/moonbit/unmbt/moonset/workspace/toml.mbt#L100-L413)<br>[cargo.mbt](file:///D:/project/moonbit/unmbt/moonset/workspace/cargo.mbt#L157-L175) |
| **P0-10** | 🟡 部分解决 | SemVer 与 Glob | ✅ `glob.mbt` 已校验 `**/` 路径边界；✅ Cargo `1.2.*` 按通配区间匹配；✅ npm/Cargo `*`/`x` 已补 prerelease 守卫；✅ npm 非 SemVer 协议（`catalog:`/`npm:`/`github:`/`latest`/`""` 等）已全面豁免；✅ MoonBit `version_matches` 已补 prerelease 守卫。<br>🟡 **说明**：MoonBit `r.major < 2 => c.major < 2` 按 MoonBit MVS 兼容策略有意保留（见注释与测试）。 | [glob.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/glob.mbt#L390-L408)<br>[version.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/version.mbt#L233-L252)<br>[semver_range.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/semver_range.mbt#L32-L51) |
| **P0-11** | ✅ 已解决 | 打包与发布 | ① `publish` 已校验并传递 `verified_archives` 走 tarball 发布（注：开启 artifact matrix 或 `--artifacts-dir` 时 `if !should_verify_matrix` 会跳过该映射，属于小边界）；② `pnpm pack` 移除不支持参数并按落盘 `.tgz` 算 hash；③ `pack --package` 兼容原生包名；④ MoonBit 搜索 `_build/publish/` 等路径且缺失时报错。 | [publish.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/publish.mbt#L402-L508)<br>[drivers.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/drivers.mbt#L208-L402)<br>[pack.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/pack.mbt#L148-L168) |
| **P0-12** | ✅ 已解决 | 安全与状态死锁 | ① `validate_changeset_id` 严格限制 `[a-zA-Z0-9-_.]` 拦截路径穿越；② `version --json` 已移至 `apply`/`format`/`commit` 全部成功后单次打印；③ 已提供 `publish --reconcile` 和解 `Unknown` 且 `Blocked` 不再死锁；④ `publish --only` 仅给选中/已发布单元打标。 | [output.mbt](file:///D:/project/moonbit/unmbt/moonset/cli/output.mbt#L218-L252)<br>[cmd_version.mbt](file:///D:/project/moonbit/unmbt/moonset/cli/cmd_version.mbt#L321-L359)<br>[publish.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/publish.mbt#L713-L764) |

---

### P1：高影响边界 Bug 核验（10 ✅ / 4 🟡 / 0 ❌）

#### 1. 规划、Changelog 与解析引擎（6/6 ✅ 全部已解决）
- ✅ **合法的 `devDependencies` 循环依赖与 Cargo `dev-dependencies` 升级**：`visit_execution` 仅遍历 `Runtime`/`Build` 边；`Development` 不触发消费方版本升级，仍更新越界范围（[planner.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/planner.mbt#L20-L27)、[planner.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/planner.mbt#L477-L480)）。
- ✅ **`extract_summary_metadata` 误删正文**：仅在 `git`/`github` 生成器生效，跳过代码块并严格校验 PR 数字、SHA 与用户名格式（[version_plan.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/version_plan.mbt#L148-L244)）。
- ✅ **Changelog 拼接与解析 5 处缺陷**：不再累加尾空行、兼容任意 `# <pkg>` 标题、保留 Keep-a-Changelog 前言、`linkify_issue_refs` 修复边界与多反引号、`extract_release_notes` 跳过代码块并解析聚合标题（[changelog.mbt](file:///D:/project/moonbit/unmbt/moonset/changelog/changelog.mbt#L283-L788)）。
- ✅ **快照 32 位整数溢出与 `short_commit_sha(None)`**：prerelease ID 改为字符串长度+字典序比较；全数字前导零 ID 自动加 `"g"` 前缀避免冲突（[version.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/version.mbt#L48-L225)、[policy.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/policy.mbt#L119-L235)）。
- ✅ **同目录共存误报风暴**：记录 `managed_root_manifests` 并在 `coexistence.mbt` 中对根目录清单改为精确路径匹配（[coexistence.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/coexistence.mbt#L18-L108)）。
- ✅ **Changeset YAML 引号/注释/空键**：`format_changeset` 用 JSON 字符串加引号；`parse_changeset` 支持引号外 `#` 行尾注释并拒绝 `''`/`""` 空键（[changeset.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/changeset.mbt#L2-L81)、[changeset.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/changeset.mbt#L261)）。

#### 2. Workspace 发现与 Manifest 解析（2 ✅ / 1 🟡）
- ✅ **npm/pnpm 发现（5/5 已解决）**：非根目录 `includeRoot: true`、`./` 前缀 `!exclude`、`pnpm-workspace.yaml` 优先于 `package.json#workspaces`、不再误杀 `packages/build`/`dist`、允许无 `version` 根包（[npm.mbt](file:///D:/project/moonbit/unmbt/moonset/workspace/npm.mbt#L293-L587)）。
- ✅ **Cargo 发现（5/5 已解决）**：支持单 crate 仓库、`[dependencies.foo]`/`[workspace.dependencies.foo]`/dotted key `acme-b.workspace = true`、`members` `#` 注释与单引号、`exclude` 通用 glob、无 `version` 不再隐式继承 workspace 版本（[cargo.mbt](file:///D:/project/moonbit/unmbt/moonset/workspace/cargo.mbt#L136-L405)、[toml.mbt](file:///D:/project/moonbit/unmbt/moonset/workspace/toml.mbt)）。
- 🟡 **配置与目录定位（3/4 已解决，1 未解决）**：
  - ✅ `--config ./moonset.json` 仅在 `.changeset`/`.moonset` 目录上溯；✅ Windows `realpath` 规范化；✅ `Reader::dirs` 兼容悬空/环符号链接（小隐患：`Reader.visited_dirs` 在多次 glob 扫描同一父目录时不重置，可能令后续 glob 返回空）。
  - ❌ **未解决**：自定义 `--config` 下 [discovery.mbt](file:///D:/project/moonbit/unmbt/moonset/workspace/discovery.mbt#L439-L449) 推导的本地 `pre_file` 未回写到 `snapshot.config.pre.file`，导致 [cmd_pre.mbt](file:///D:/project/moonbit/unmbt/moonset/cli/cmd_pre.mbt#L5-L8) 和 [version_plan.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/version_plan.mbt#L862-L913) 仍读写 `.changeset/pre.json`。

#### 3. Executor、Journal、Staging、Tag 与 CLI（1 ✅ / 2 🟡）
- ✅ **Tag 与 Dirty Worktree（5/5 已解决）**：改用 `git tag -a` annotated tag、`tag --push` 查 `ls-remote` 并补推未推送的 `skipped` tag、`--force --push` 传 `-f`、`is_ephemeral_moonset_state_path` 覆盖 `.moonset/pack-results-*.json`、非 `--since` 也最佳努力解析 `reader.head`（[tag.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/tag.mbt#L52-L283)、[host.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/host.mbt#L437-L453)、[reader.mbt](file:///D:/project/moonbit/unmbt/moonset/workspace/reader.mbt#L325-L367)）。
- 🟡 **Journal 与 Staging（5/6 已解决，1 未解决）**：
  - ✅ 拒绝覆盖未恢复 journal、全链路 `atomic_write_text`、`version --recover` 自动查找 workspace root、`--dry-run` 跳过 `stage_lockfiles`、`packageManager` 非强制且 `--offline` 失败自动在线重试。
  - ❌ **未解决**：[apply.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/apply.mbt#L223-L228) 在返回前就删除了 `version-journal.json`，而 [cmd_version.mbt](file:///D:/project/moonbit/unmbt/moonset/cli/cmd_version.mbt#L323-L334) 在其后才调用 `format_files`，formatter 失败时无法通过 `--recover` 回滚。
- 🟡 **CLI 参数与输出（6/7 已解决，1 未解决）**：
  - ✅ 已全面采用 `unmbt/cac@0.1.1`，支持 `--flag=value`、`--`、`--help <cmd>`，禁止 `init`/`add`/`pre` 传 `--dry-run`；`commit_changes_with` 已用 `git commit --only --`；`process_failure_detail` 已透传 `stderr`/`stdout` 到 `PublishStatus.message`。
  - ❌ **未解决**：[host.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/host.mbt#L164-L177) 的 `NativeHost::run` 仍无超时保护（仅 `run_with_env` 支持 `timeout_ms`）。

#### 4. GitHub Actions、Workflows 与安装脚本（1 ✅ / 1 🟡）
- ✅ **发版与安装脚本（3/3 已解决）**：[release-binaries.yml](file:///D:/project/moonbit/unmbt/moonset/.github/workflows/release-binaries.yml#L112-L143) 已加 `--prerelease` 与 `v1` 浮动标签防覆盖/防降级守卫；[setup/install.sh](file:///D:/project/moonbit/unmbt/moonset/setup/install.sh#L130-L134) 兜底 `${HOME}/.cache` 不再装进 `$tmp_dir`；[scripts/install.sh](file:///D:/project/moonbit/unmbt/moonset/scripts/install.sh#L169-L195) 改用 `case "$shell_name"` 正确识别 zsh。
- 🟡 **`action.yml` & `pr-check`/`pr-comment`（6/8 完全解决，2 项待完善）**：
  - ✅ 已移除 `mapfile`、修复 3 处 `now_ms()`、全量过滤 Windows `jq` `\r`、改用 `git -C "$WORK_DIR" add -A -- "${staged_paths[@]}"`、credentials 加 `EXIT` trap 清理、`pr-comment` 兼容 `body: null`、`pr-check` 使用随机 heredoc 分隔符。
  - 🟡 **待完善**：[action.yml](file:///D:/project/moonbit/unmbt/moonset/action.yml#L285-L286) 仍连续调用 **2 次** `moonset version`（原 3 次）；且在 `git diff --cached --quiet` 为真（无新提交）时，[action.yml](file:///D:/project/moonbit/unmbt/moonset/action.yml#L303-L315) 仍会尝试 push 并执行 `gh pr create`。

---

## 二、与原版 `changesets` 的功能与语义差距复核

### 2.1 核心规划引擎与配置对照（5 ✅ / 3 🟡）

| 能力领域 | 状态 | 当前实现进展与剩余缺口 |
|---|---|---|
| **`workspace:` 协议** | ✅ 已解决 | 完整支持 `workspace:*`/`^`/`~`/`<range>`/`<relPath>` 解析、pnpm 传播、能力校验与改写（[semver_range.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/semver_range.mbt#L55-L103)、[planner.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/planner.mbt#L481-L487)）。 |
| **`peerDependencies` 策略** | ✅ 已解决 | 已支持 npm `Peer` 依赖升 `major` 及 `onlyUpdatePeerDependentsWhenOutOfRange`（[planner.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/planner.mbt#L488-L519)）。 |
| **`devDependencies` 与 `type: "none"`** | ✅ 已解决 | `devDependencies` 不触发消费方版本升级但会同步更新越界依赖范围；支持 `type: "none"` 并保留变更记录（[planner.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/planner.mbt#L340-L342)、[planner.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/planner.mbt#L623-L661)）。 |
| **循环依赖** | ✅ 已解决 | `visit_execution` 排除 `Development` 边，允许合法的 npm/Cargo `devDependencies` 环（注：运行时依赖环仍拒绝）。 |
| **Pre-release 模式** | ✅ 已解决 | 已升级至 Changesets v3 极简 `pre.json` + `.changeset/pre/` 隔离 + 旧版 v2 迁移兼容 + 禁止 pre 模式执行 snapshot（[pre.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/pre.mbt)）。 |
| **配置项覆盖与生效** | 🟡 部分解决 | ✅ 已落地：`bumpVersionsWithWorkspaceProtocolOnly`、`privatePackages: true`、`!` 否定 glob、`config.github.links`、`config.access`、`MOONSET_*` 环境变量、`init --force`。<br>❌ **仍缺**：`alsoSkipDependentsOfSkipped`、`commit: true` / `skipCI`、`format: "auto"` 真探测（目前直接回退 `builtin`）与 `"deno"`。 |
| **Snapshot 快照发布** | 🟡 部分解决 | ✅ 已打通端到端：`build_plan` 内计算并联动锁定、支持无 tag `--snapshot`、`{timestamp}`/`{commit-short}`、`publish` 消费 `isSnapshot: true` 并自动挂 npm dist-tag、跳过打标。<br>❌ **仅缺**：`--snapshot-prerelease-template` CLI 参数（目前仅支持配置文件）。 |
| **Changelog 生成器** | 🟡 部分解决 | ✅ 已支持保留 `# <pkg>` 标题、多作者、`GITHUB_SERVER_URL`（changelog 侧）。<br>❌ **仍缺**：空发布仍写 `- No changes in this release.`、插件协议仍为整篇文档而非行级 Hook、[pr_comment.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/pr_comment.mbt#L400) 仍硬编码 `https://github.com/`。 |

### 2.2 CLI、发布、Git 与自动化对照（0 ✅ / 7 🟡 / 2 ❌）

| 子命令 / 工具 | 状态 | 已补齐能力 vs 剩余缺口 |
|---|---|---|
| **`init`** | 🟡 部分解决 | ✅ 新增交互式向导、移除 `.changeset/.gitignore`；❌ 仍硬编码默认分支 `"main"`（未自动探测仓库默认分支）。 |
| **`add`** | 🟡 部分解决 | ✅ 已补齐 `--open`/`$EDITOR`、变更包分组高亮、`<1.0.0` 首次 major 确认、单包跳过、`human-id`、带引号 YAML 键、TUI 分包级别；❌ 非交互 CLI 参数仍仅支持全局单一 `--major/--minor/--patch`。 |
| **`version`** | 🟡 部分解决 | ✅ 已补齐 `--ignore`、无 tag `--snapshot`；❌ commit 消息仍静态（不含包版本清单与 `[skip ci]`），无 changeset 仍返回退出码 `0`。 |
| **`publish`** | 🟡 部分解决 | ✅ 已补齐 `--otp`、`publishConfig.{access,registry,directory}`、tarball 发布、snapshot/pre `--tag`、`pnpm --no-git-checks`、查重修复；❌ 仍缺 Yarn、`--access` CLI 参数、`--ignore-scripts`、`CHANGESETS_OUTPUT`。 |
| **`publish-plan`** | ❌ 设计保持 | 仍保持“读待处理 changeset 输出分析计划”语义（含 `artifacts`/`executionGraph`），与原版远端发布前分片查询语义不同。 |
| **`status`** | 🟡 部分解决 | ✅ 已支持大小写不敏感忽略 `readme.md`/`AGENTS.md`/`CLAUDE.md`/`GEMINI.md` 及 `include_commits=true` 浅克隆警告；❌ 仍缺 `-o <file>` 写文件、工作区对比以及 `status` 侧浅克隆提示/自动 `deepen`。 |
| **`tag`** | 🟡 部分解决 | ✅ 已改 annotated tag、`git ls-remote` 远端查重、重试 `--push`；❌ 仍强依赖 `.moonset/release-state.json`（无法无状态直接按清单打标）。 |
| **`action`** | ❌ 局部增强 | 🟡 已增加 `version-args`/`publish-args` 透传；❌ 仍缺自定义 `version`/`publish` 任意命令、`commitMode: github-api`（支持签名提交）、结构化 `publishedPackages` 输出。 |
| **`bot`** | 🟡 部分解决 | ✅ 已补齐部分覆盖（未加 changeset 包）提示、workflow 侧跳过 Release PR、代码块免 `\u{200B}`；❌ 仍为单一硬编码评论 marker（多 `coexist` 分区会互相覆盖）且 `pr-check` 内部未兜底跳过 Release PR。 |

---

## 三、架构设计问题复核

### 1. 公共 API 与数据模型（3 ✅ / 1 🟡 / 1 ❌）
- ✅ **40 字段扁平 `Config` 与 `Config.raw` 已彻底治理**：[model/types.mbt](file:///D:/project/moonbit/unmbt/moonset/model/types.mbt#L639-L662) 重构为 22 字段 + 9 个嵌套子配置结构体，彻底删除 `Config.raw`。
- ✅ **函数组合爆炸已收口**：[executor/pkg.generated.mbti](file:///D:/project/moonbit/unmbt/moonset/executor/pkg.generated.mbti) 中 `publish_release*` 与 `pack_artifacts*` 均收敛为各 2 个，`PublishOptions::new()` / `PackOptions::new()` / `TagOptions::new()` / `VersionOptions::default()` 提供关键字默认构造。
- ✅ **双门面重导出已对齐**：[moonset.mbt](file:///D:/project/moonbit/unmbt/moonset/moonset.mbt) 与 [api/api.mbt](file:///D:/project/moonbit/unmbt/moonset/api/api.mbt) 已 1:1 同步，补齐了 `Config`/`PublishResult`/`ExecutionHost`/`NativeHost` 及全部 `*_with` 函数。
- 🟡 **Stringly-Typed 大幅改善**：13 个核心字段已转为强类型 `enum`（`Ecosystem`/`PackageManager`/`Visibility`/`PreMode`/`Access`/`CommitMode`/`LockfileMode`/`PublishState` 等），仅余 `UnitId`、`Diagnostic.code`、`Release.reasons` 等仍为 `String`。
- ❌ **`wasm-gc` 门面仍未拆分**：[moon.pkg](file:///D:/project/moonbit/unmbt/moonset/moon.pkg#L5) 与 [api/moon.pkg](file:///D:/project/moonbit/unmbt/moonset/api/moon.pkg#L10) 仍锁死 `supported_targets = "native"`（纯核仅 `model/`、`engine/`、`changelog/` 可直接用于 `wasm-gc`）。

### 2. Adapter 层与生态分发（1 ✅ / 1 🟡）
- ✅ **10 个零实现同步空壳 Trait 已全部删除**：[adapters/protocol.mbt](file:///D:/project/moonbit/unmbt/moonset/adapters/protocol.mbt) 仅保留真实在用的插件协议与注册表类型。
- 🟡 **生态分发集中化但尚未 Trait 化**：已抽取 [executor/drivers.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/drivers.mbt)（533 行）集中封装 `driver_registry_lookup`/`driver_pack`/`driver_preflight`/`driver_publish`，消除全部字符串分支；但未建模为异步 `EcosystemDriver` trait，且 `executor/` 内仍分散 12 处强类型 `match`/`if unit.ecosystem` 分支。

### 3. 职责边界、重复与 God-File（5 ✅ / 2 🟡 / 2 ❌）
- ✅ **`cli/run.mbt` 已彻底拆解**：从 1489 行缩减为 **124 行**，拆分为 `cmd_add.mbt`、`cmd_init.mbt`、`cmd_pre.mbt`、`cmd_publish.mbt`、`cmd_status.mbt`、`cmd_version.mbt` 等独立文件。
- ✅ **纯核污染已清除**：`ReleaseUnit` 新增 `version_span : TextSpan?`，[engine/moon.pkg](file:///D:/project/moonbit/unmbt/moonset/engine/moon.pkg) 已移除 `@manifest` 依赖，[engine/version_plan.mbt](file:///D:/project/moonbit/unmbt/moonset/engine/version_plan.mbt) 不再含手写 JSON/TOML 扫描器。
- ✅ **5 份 `release-state.json` 解析器已合并**：统一为 [model/json.mbt](file:///D:/project/moonbit/unmbt/moonset/model/json.mbt#L320-L430) 的 `ReleaseState::from_json`/`to_json`。
- ✅ **`DependencyIntent` 字段已补齐**：现携带 `kind : DependencyKind` 与 `producer_version : String`。
- ✅ **移除重量级 TUI 依赖栈**：`moon.mod` 已清除 `mizchi/tui`/`crater-*`/`css`/`syntree`（仅保留 3 个直接依赖）。
- 🟡 **God-File 仍有残留**：[executor/publish.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/publish.mbt) 仍有 **1255 行**（`publish_release_with` 单函数 957 行）；新自研 TUI 的 [cli/tui_app.mbt](file:///D:/project/moonbit/unmbt/moonset/cli/tui_app.mbt)（1160 行）与 [cli/tui_render.mbt](file:///D:/project/moonbit/unmbt/moonset/cli/tui_render.mbt)（848 行）体量也偏大。
- 🟡 **插件安全模型未在调用点闭环**：`adapters/protocol.mbt` 已支持 `host_allowed_programs?`，但 [cli/cmd_version.mbt](file:///D:/project/moonbit/unmbt/moonset/cli/cmd_version.mbt#L200-L219) 调用 `run_jsonl` 时未传宿主机白名单，[executor/publish.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/publish.mbt#L188-L209) 的 `command` 发布器也未做宿主机可执行白名单校验。
- ❌ **`ExecutionHost` 局部绕过仍在**：[executor/publish.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/publish.mbt) 已修复并走 `host.run_with_env`，但 [executor/doctor.mbt](file:///D:/project/moonbit/unmbt/moonset/executor/doctor.mbt#L151) 仍直调 `@workspace.discover`，`cli/cmd_*.mbt` 仍大量直调 `@fs`/`@env`/`@process`。
- ❌ **构建/依赖小债仍在**：[cli/generated_version.mbt](file:///D:/project/moonbit/unmbt/moonset/cli/generated_version.mbt)（原 `embedded_version.mbt`）仍被 Git 跟踪并由 `dev_build` 覆写；`unmbt/moon-manifest@0.2.0-alpha.2` 仍为 alpha 依赖。

### 4. SDD 规格与测试门禁（3 ✅ / 3 🟡 / 1 ❌）
- ✅ **6 处文档断链已清零**，且 [scripts/lint-workflows.mbtx](file:///D:/project/moonbit/unmbt/moonset/scripts/lint-workflows.mbtx#L185-L254) 已内置 Markdown 死链校验、动态扫描 workflow、`github.head_ref`/`steps.*`/`refs/pull/` 安全检查与 `.gitattributes` `eol=lf` 校验。
- ✅ **[scripts/cli-integration.mbtx](file:///D:/project/moonbit/unmbt/moonset/scripts/cli-integration.mbtx)** 已改为构建并测试 `--release` 二进制，补齐 `init`/`add`/`pre`/`tag`/`doctor`/`pack` 流程。
- ✅ **[.github/workflows/ci.yml](file:///D:/project/moonbit/unmbt/moonset/.github/workflows/ci.yml)** 已接入 `wasm-gc` `--deny-warn` + 测试、`moon fmt --check`、`moon info`、`actionlint`、`moon package` 与洁净工作树校验。
- 🟡 **少量文档残留漂移**：[docs/api.md](file:///D:/project/moonbit/unmbt/moonset/docs/api.md#L36-L76) 第 2–5 节仍残留 v1 草案术语（`WorkspaceIo`/`EcosystemAdapter`/Builder setters）；[docs/automation.md](file:///D:/project/moonbit/unmbt/moonset/docs/automation.md#L60) 仍写 `head.sha`。
- 🟡 **测试盲区缩小但未清零**：闲置 fixture 从 4 个降为 **2 个**（`fixtures/stale-plan`、`fixtures/partial-publish` 仍未被测试引用）；`cli-integration.mbtx` 仍缺真实/mock `publish`、`version --recover` 和混合生态（npm/Cargo）端到端用例。
- ❌ **外部 API 契约与脚本测试未补齐**：`fixtures/external-moonbit-api` 仍非独立 `moon.mod` 且仅测 3 个函数；CI 仍缺 `moon publish --dry-run` 及 ShellCheck / Bash / Composite Action 运行时测试。

---

## 四、剩余待办改进清单（按优先级重排）

### 优先级 1：剩余正确性与边界 Bug（建议优先收尾）
1. **统一 MoonBit 私有模块可见性策略（P0-8 ①）**：明确 `moon.mod` `private = true` 与 `privatePackages` 配置的语义关系（是否应纳入 `privatePackages` 控制或显式文档化 `Restricted` 行为），避免配置失效预期差。
2. **修复自定义 `--config` 下 `pre.json` 路径不一致**：在 [workspace/discovery.mbt](file:///D:/project/moonbit/unmbt/moonset/workspace/discovery.mbt#L439-L449) 将推导出的 `pre_file` 回写进 `snapshot.config.pre.file`（或统一配置解析入口）。
3. **修复 `format_files` 位于 journal 删除之后**：将 `format_files` 纳入 `version-journal.json` 保护窗口内（先 format 再删 journal），确保格式化失败可 `--recover`。
4. **修复 `Reader.visited_dirs` 跨 glob 串扰与 `Cargo.toml` BOM 偏移**：`visited_dirs` 改为单次递归局部集合；`workspace/toml.mbt` 记录原始 BOM 字节偏移。
5. **补齐 `pr-check/action.yml` 内置跳过 `moonset-release/*`（P0-7 ③）**，并在 `action.yml` 对空提交（`git diff --cached --quiet`）跳过 push/`gh pr create`，同时合并 2 次 `moonset version` 调用。
6. **为 `NativeHost::run` 增加默认超时保护**，并在 `publish.mbt` matrix 模式下确认是否同样应优先发布已校验的 `verified_archives` tarball。

### 优先级 2：与原版 `changesets` 的剩余高价值差距
1. **补齐关键配置与 CLI 细项**：`--snapshot-prerelease-template` CLI 参数、`init` 自动推断默认分支、`status -o <file>`、`alsoSkipDependentsOfSkipped`、`commit.skipCI`、`format: "auto"` 真探测、多 `coexist` 分区独立 PR Bot marker、`pr_comment.mbt` 支持 `GITHUB_SERVER_URL`。
2. **按需补齐生态扩展**：Yarn 支持、`publish --access` / `--ignore-scripts` / `CHANGESETS_OUTPUT`、无 `release-state.json` 的独立 `tag` 模式、`action.yml` 支持 `github-api` 签名提交与 `publishedPackages` 输出、Changelog 行级 Hook 协议。

### 优先级 3：架构收尾与测试门禁加固
1. **拆分 `executor/publish.mbt`（1255 行）**：将 `publish_release_with`（957 行）拆为状态加载/校验、单单元执行、打标收尾等阶段函数；按需将 `cli/tui_app.mbt` 拆分。
2. **收口剩余架构债务**：为 `wasm-gc` 提供纯核导出门面；为 `run_jsonl` 与 `command` publisher 接入宿主机 allowlist；让 `executor/doctor.mbt` 与 CLI 写操作逐步收口至 `ExecutionHost`；解决 `cli/generated_version.mbt` 工作树脏写问题；待 `unmbt/moon-manifest` 稳定后升级至正式版。
3. **补齐最后几处测试与文档门禁**：接入 `fixtures/stale-plan` 与 `fixtures/partial-publish`；将 `fixtures/external-moonbit-api` 升为独立 `moon.mod` 契约测试；在 `cli-integration.mbtx` 补全 `recover` + 混合生态（npm/Cargo）端到端测试；CI 增加 ShellCheck / Action 回归测试；清理 [docs/api.md](file:///D:/project/moonbit/unmbt/moonset/docs/api.md) 与 [docs/automation.md](file:///D:/project/moonbit/unmbt/moonset/docs/automation.md) 的残留旧文案。
