# SDD 符合性与代码审查报告

> 审查日期：2026-11-18  
> 审查基线：基于 `docs/` 下 SDD 规约与当前仓库代码逐模块核对

---

## 1. 当前验证基线

在当前工作区执行以下验证命令均已通过（2026-11-18 复核基线）：

- `moon check --target native --deny-warn`：通过（exit 0）
- `moon check --target wasm-gc`：通过（exit 0，验证 `model` / `engine` / `changelog` 纯计算核跨目标编译）
- `moon test --target native`：53 项测试全部通过（`Total tests: 53, passed: 53, failed: 0`）
- `moon test --target wasm-gc`：31 项测试全部通过（`Total tests: 31, passed: 31, failed: 0`）
- `moon run scripts/embed-schema.mbtx --check`：通过
- `moon run scripts/cli-integration.mbtx`：通过（含外部 JSONL 插件、`init -> add -> pre -> version -> tag -> doctor --fix`、`commit.mode`、非 `status` 错误信封与退出码 `1` 验证）
- `moon fmt --check`：通过

> 说明：第 2～5 节记录的是重构前的原始审查发现，保留作为问题溯源基线；当前修复状态与边界以第 6 节为准。

---

## 2. 架构设计与 SDD 契约一致性问题

### 2.1 纯库层锁死在 `native` 目标，违背无平台约束
- **SDD 要求**：[docs/README.md](README.md) 与 [编程 API](api.md) 规定“库层保持无平台状态”“planner 和 changeset parser 可以在 wasm/native 测试中复用”。
- **现状问题**：无任何宿主 I/O 的纯计算包 [engine/moon.pkg](../engine/moon.pkg)、[changelog/moon.pkg](../changelog/moon.pkg) 以及 [api/moon.pkg](../api/moon.pkg)、[moon.pkg](../moon.pkg) 均声明了 `supported_targets = "native"`，限制了跨目标复用与无平台测试。

### 2.2 执行层逻辑全部堆叠在 `cli/run.mbt`，`adapters` 端口未接入主流程
- **SDD 要求**：[系统架构](architecture.md) 与 [编程 API](api.md) 定义了 `apply_plan`、`publish` 等可复用核心能力，以及 `FileHost`、`ProcessHost`、`RegistryHost`、`DiscoveryPort`、`OperationalAdapter`、`PublisherPort` 等可注入/可模拟端口。
- **现状问题**：
  - [cli/run.mbt](../cli/run.mbt) 达 1800 行，将 journal 原子写盘与恢复（`apply_version_plan`、`recover_version`）、lockfile staging（`stage_lockfiles`、`copy_staging_tree`）、Git 标签（`tag_command`）、打包（`pack_command`）、发布编排与状态持久化（`publish_command`、`registry_lookup`）、外部插件调用（`version_command`）全部作为私有 `async fn` 直接绑定在 `@fs`/`@shell.Cmd`/`@env` 上。
  - [api/api.mbt](../api/api.mbt) 未导出 `apply_plan` 或 `publish` 编排能力。
  - [adapters/protocol.mbt](../adapters/protocol.mbt) 定义的 `FileHost`、`ProcessHost`、`RegistryHost`、`OperationalAdapter`、`PublisherPort`、`PublisherRegistry` 在生产流程中未被使用；`AdapterRegistry::with_builtins()` 仅返回静态能力报告。

### 2.3 包边界与公共 API 暴露过宽
- [系统架构](architecture.md) 规划了 `internal/*` 隔离内部包并提醒避免通过 `pub using` 造成 `.mbti` 不稳定，但当前所有包均为顶层公开包，[api/api.mbt](../api/api.mbt) 与 [moonset.mbt](../moonset.mbt) 大量使用 `pub using` 转发类型。
- [cli/pkg.generated.mbti](../cli/pkg.generated.mbti) 将 TUI 内部函数与状态（`tui_begin`、`tui_cleanup`、`tui_key`、`reduce_select`、`reduce_choice`、`edit_summary`、`render_*`）全部作为 `cli` 包公共 API 导出。

### 2.4 文档状态与实际实现进度不同步
- [需求规格](requirements.md) 中 `FR-001 (init)`、`FR-002 (add)`、`FR-007 (version)`、`FR-008 (pre)`、`FR-010 (tag)`、`FR-012 (config)` 在代码中已有基础实现，但状态仍停留在 `Proposed`；[docs/README.md](README.md) 顶部仍标注“Phase 1 alpha 实现”。
- [命令契约](commands.md) 与 `FR-017` 列出的 `doctor` 命令在 [cli/arguments.mbt](../cli/arguments.mbt) 中尚未实现（传入 `doctor` 会返回 `Unknown command: doctor`）。

---

## 3. 代码编写与逻辑 Bug 清单

### 3.1 高优先级（直接影响核心功能正确性）

1. **`publish` 状态机重复追加导致状态文件与输出污染**
   - **位置**：[cli/run.mbt](../cli/run.mbt#L1015-L1041)、[cli/run.mbt](../cli/run.mbt#L1157-L1303)
   - **问题**：同一 `(unitId, version, target)` 在 preflight 时 `statuses.push(..., state: "preflighted")`，开始发布时又 `push(..., state: "publishing")`，完成后再 `push(..., state: "published" / "unknown")`，从未就地更新同一条目。重试读取 `.moonset/publish-state.json` 时又将历史条目前置保留，导致单个包在状态文件中同时存在多条相互矛盾的状态记录。

2. **混合 workspace 对非 `moon` 单元的 `publisher` 覆盖误报错**
   - **位置**：[workspace/discovery.mbt](../workspace/discovery.mbt#L367-L374)
   - **问题**：校验 `experimental.mixedWorkspaces.units.<id>.publisher` 时直接判断 `publisher != "moon"` 即抛出 `"Unsupported MoonBit publisher override"`，未区分 `unit.ecosystem`。按 [混合 workspace 设计](mixed-workspaces.md) 示例配置 `"npm:@acme/engine": { "publisher": "npm" }` 会直接导致 `discover` 失败。

3. **`pre` 模式命令行到 `version` 执行全链路断裂**
   - **位置**：[cli/arguments.mbt](../cli/arguments.mbt#L138-L142)、[cli/run.mbt](../cli/run.mbt#L1543-L1591)、[engine/pre.mbt](../engine/pre.mbt#L91-L119)、[engine/version_plan.mbt](../engine/version_plan.mbt#L516-L526)
   - **问题**：
     - `pre enter <tag>` 无法传参：`arguments` 解析 `pre_action` 后遇到第二个位置参数 `<tag>` 直接报 `Unexpected argument`；不传 tag 时 `pre_command` 将 `tag` 硬编码为 `"next"`。
     - 重复执行 `pre enter` 不会拒绝，而是直接覆盖已有 `pre.json`（违反 `FR-008`）。
     - `pre exit` 直接删除 `pre.json`，而不是将 `mode` 设为 `"exit"`，导致 [engine/planner.mbt](../engine/planner.mbt#L265-L278) 中的预发布毕业回稳逻辑在 CLI 中无法触发。
     - `build_version_plan` 未生成写回 `next_pre_state` 到 `pre.json` 的 `FileEdit`，且在 `pre` active 模式下仍把所有 `analysis.changesets` 生成为删除编辑；`target_version` 也未利用 `state.initial_versions` 计算二次预发布基准版本。

4. **`tag` 命令的 `sourceHead` 校验与正常发布流程冲突**
   - **位置**：[cli/run.mbt](../cli/run.mbt#L769-L774)、[workspace/reader.mbt](../workspace/reader.mbt#L137-L143)
   - **问题**：不带 `--since` 执行 `version` 时 `snapshot.git_head` 为 `None`；若带 `--since` 执行 `version`，`release-state.json` 记录的是提交 release commit 前的 `HEAD`。用户在 `version` 后提交 release commit，再运行 `tag` 时 `sourceHead != head_out` 会直接报错 `"Git HEAD changed since version plan was applied"`。

5. **`Cargo.toml` 字节偏移与 CRLF / 多字节 UTF-8 字符不匹配**
   - **位置**：[workspace/cargo.mbt](../workspace/cargo.mbt#L137-L165)、[engine/version_plan.mbt](../engine/version_plan.mbt#L49-L59)、[engine/version_plan.mbt](../engine/version_plan.mbt#L102-L123)
   - **问题**：`cargo_entries` 与 `replace_toml_version` 先把 `\r\n` 替换为 `\n` 再按 UTF-16/字符 `length()` 累加 `offset`，随后把偏移传给按 `@utf8.encode` 字节切片的 `replace_byte_span`。若 `Cargo.toml` 含 `\r\n` 或非 ASCII 注释，替换位置将发生偏移并损坏文件。此外手写行扫描 TOML 也不支持行尾注释与单引号字符串。

6. **自定义 `changelog.file` 时未预加载原文，导致写盘前哈希/覆盖问题**
   - **位置**：[workspace/discovery.mbt](../workspace/discovery.mbt#L394-L401)
   - **问题**：`discover` 预加载已有 changelog 时硬编码读取 `"CHANGELOG.md"`，忽略了 `config.changelog_file`。使用自定义 changelog 文件名时 `snapshot.sources` 缺少原文，导致 `build_version_plan` 误判文件不存在并产生错误 `before_hash`。

---

### 3.2 中优先级（契约缺失、边界漏洞与代码质量）

1. **Schema 校验器与配置解析不一致**
   - [engine/schema.mbt](../engine/schema.mbt) 未实现 `propertyNames` 与 `pattern`，导致 [docs/schema/config-v1.json](schema/config-v1.json) 中针对 `UnitId` 的正则校验形同虚设。
   - [engine/config.mbt](../engine/config.mbt#L286-L298)：配置 `"changelog": false` 会静默回落为 `"builtin"`；`config.github` 从 `changelog.repo` 读取，但 Schema 中 `changelog` 对象设为 `additionalProperties: false` 且仅允许 `generator`/`file`/`options`。
   - [engine/config.mbt](../engine/config.mbt#L124-L127) 用 `source.find` 匹配首个键名定位诊断行列，嵌套同名键时行列号可能失准。
   - [engine/version_plan.mbt](../engine/version_plan.mbt#L86-L99) 的 `replace_json_string` 使用 `@json.parse` 后整文件 `stringify(indent=2)` 重写 `package.json`，会破坏非 2 空格缩进或原有格式风格。

2. **规划器混合生态能力与去重问题**
   - [engine/planner.mbt](../engine/planner.mbt#L181-L196)：`visit()` 只检查包依赖环，未检查 `config.bridges` 环及混合执行环（`FR-020` / `MIX-006`）。
   - [engine/planner.mbt](../engine/planner.mbt#L279-L331)：`for ;;` 循环前与循环内存在重复的 bridge 传播代码块。
   - [engine/planner.mbt](../engine/planner.mbt#L387-L393)、[engine/planner.mbt](../engine/planner.mbt#L451-L455)：`npm` 生态被排除在依赖传播与 `dependency_updates` 之外，且 [workspace/npm.mbt](../workspace/npm.mbt#L254-L255) 的依赖 span 硬编码为 `0..0`。
   - [engine/version_plan.mbt](../engine/version_plan.mbt#L242-L302)、[engine/version_plan.mbt](../engine/version_plan.mbt#L433)：`git`/`github` 生成器的 `commit`、`pull_request`、`author` 全为 `None`，且 `ChangelogEntry.section` 硬编码为 `"builtin"`；同目录多单元写同一 `CHANGELOG.md` 仅直接报 `ownership-conflict`。
   - [engine/version_plan.mbt](../engine/version_plan.mbt#L463-L473)：`moon.mod` 的 `shift` 偏移计算仅对比首个 dependency intent 之前的公共前缀，若多个编辑交错在依赖声明前后，偏移平移逻辑脆弱。

3. **快照隔离与 CLI 安全/契约缺口**
   - **快照隔离破坏**：`--since` 模式下 [workspace/npm.mbt](../workspace/npm.mbt#L68-L103)（`package_candidates`）与 [workspace/cargo.mbt](../workspace/cargo.mbt#L80-L126)（`cargo_candidates`）的通配符展开直接调用 `@fs.exists` / `@fs.readdir` 读取工作目录，未通过 `Reader` 读取 Git `HEAD` 树。
   - **`publish` 门禁缺失**：未校验 release commit / 工作树干净性 / `--allow-uncommitted`、未校验 `--yes` 确认、未校验 `--only` 的 fixed/bridge 闭包完整性、未检查 `private_publish`、未按 `tag.afterPublish` 触发 `tag`、也未按拓扑/产物依赖顺序发布。
   - **`pack` 解析失效**：对 `moonbit` 调用 `moon package --frozen` 后尝试用 `@json.parse` 解析输出（`moon package` 不输出 npm JSON），导致 `archive_path` 与 `content_hash` 恒空、`verified` 恒为 `false`；同时未过滤 `publish == false` 单元，也未实现 `--package`/`--frozen` 参数解析。
   - **`tag` 缺口**：未预检多个单元模板渲染后的 tag 重名，也未区分“同名 tag 指向同一 commit 与指向不同 commit”。
   - **`add` 与 TUI 缺口**：非交互 `add` 未校验 `--package` 是否存在于当前 workspace；交互式 `interactive_add`（[cli/run.mbt](../cli/run.mbt#L1482-L1540)）把所有选择包硬编码为 `Patch`，未使用已编写的 `render_bump_page`、`render_confirmation` 和 `reduce_choice`。
   - **参数与顶层错误处理**：[cli/arguments.mbt](../cli/arguments.mbt) 中 `tag` 复用 `--format` 导致与 `--format json` 冲突；不带子命令直接执行 `moonset` 直接报错而不是进入交互式 `add`（非 CI）或提示（CI）；[cli/run.mbt](../cli/run.mbt#L1765-L1799) 使用 `args.contains("json")` 判断 JSON 错误输出（任何值恰好为 `"json"` 的参数都会误触发），且所有命令异常均固定输出 `status` 的 JSON 结构。

---

## 4. 测试与验证体系问题（已补充落地）

1. **`cli/` 测试覆盖**（已补齐）
   - 已新增 [cli/cli_wbtest.mbt](../cli/cli_wbtest.mbt) 覆盖参数解析与 TUI 状态机/视图渲染。
   - 已扩展 [scripts/cli-integration.mbtx](../scripts/cli-integration.mbtx) 跑通 `init -> add -> pre -> version -> tag -> doctor --fix`、`commit.mode`、`publish` 门禁退出码 `1` 与非 `status` 错误信封。
2. **规划器、混合工作区与最小 fixture 集**（已补齐核心用例）
   - 已按 [测试策略](test-strategy.md) 建立 `fixtures/` 最小集（`single-module/`、`workspace-two-modules/`、`fixed-and-linked/`、`prerelease/`、`invalid-frontmatter/`、`private-and-ignore/`、`stale-plan/`、`partial-publish/`），并在 [workspace/integration_test.mbt](../workspace/integration_test.mbt) 接入验证。
   - [engine/planner_test.mbt](../engine/planner_test.mbt)、[engine/version_test.mbt](../engine/version_test.mbt)、[executor/executor_test.mbt](../executor/executor_test.mbt) 已补充 `bridges` 传播与环检测、`npm` 依赖传播、跨生态 `fixed`/`linked`、`pre` 二次预发布与 `MIX-001`～`MIX-012` 关键场景。

---

## 5. 后续修复与改进建议

1. **优先修复阻塞型功能 Bug**
   - 修复 `pre enter <tag>` 参数解析、重复进入拒绝、`pre exit` 写 `mode: "exit"`，以及 `build_version_plan` 对 `pre.json` 的更新与保留 changeset 逻辑。
   - 修复 `workspace/discovery.mbt` 中按生态区分 `units.*.publisher` 校验的误报。
   - 修复 `publish_command` 的 `statuses` 原地更新、release commit / `--yes` / `--only` 闭包检查与 `afterPublish` 行为，并修正 `tag_command` 的 `sourceHead` 校验语义。
   - 修复 `Cargo.toml` 的 UTF-8 字节偏移计算及 `config.changelog_file` 快照预读。
2. **补齐测试防线**
   - 为 `cli/arguments.mbt`、`cli/tui_state.mbt`、`cli/tui_render.mbt` 补充纯单元测试。
   - 扩展 `scripts/cli-integration.mbtx`（或新增集成测试），跑通 `init -> add -> pre -> version -> recover -> tag` 与 fake registry 下的 `publish` 部分失败重试链路，以及 `MIX-001` ~ `MIX-012` 关键用例。
3. **收敛架构与文档状态**
   - 将 `cli/run.mbt` 中的文件事务/journal、Git、staging、pack 与 publish 编排下沉到库层并接入 `adapters` 端口；移除纯库层包不必要的 `supported_targets = "native"` 限制，并同步更新 [需求规格](requirements.md) 状态与 [测试策略](test-strategy.md)。

---

## 6. 修复与复核记录（2026-11-18）

基于本报告第 2～5 节的问题清单已完成两轮集中调整、缺陷收口与 SDD 文档同步：

- **架构对齐与跨目标纯库层**：
  - 移除 [engine/moon.pkg](../engine/moon.pkg) 与 [changelog/moon.pkg](../changelog/moon.pkg) 的 `supported_targets = "native"`；`model`、`engine`、`changelog` 纯计算核心均已通过 `wasm-gc`（31 项测试）与 `native`（53 项测试）双目标验证。
  - 新增 [executor/](../executor/) 包与异步宿主边界 `ExecutionHost`（含 `apply_version_plan_with`、`commit_changes_with`、`recover_version_with`、`stage_lockfiles_with`、`pack_artifacts_with`、`publish_release_with`、`create_tags_with`、`run_doctor_with`），并在 [api/api.mbt](../api/api.mbt) 与 [moonset.mbt](../moonset.mbt) 导出；同步更新 [系统架构](architecture.md) 与 [编程 API](api.md) 确立 `ExecutionHost` + `adapters`（`PublisherRegistry` / `AdapterRegistry` / v1 实验 traits）分工。
  - 收窄 [cli/pkg.generated.mbti](../cli/pkg.generated.mbti) 公共表面，仅保留 `cli::run`。
- **高/中优先级缺陷与 4 处核心缺口修复**：
  - **`pre` 模式全链路**：修复 `pre enter <tag>` 参数解析与重复进入拒绝、`pre exit` 写 `mode: "exit"`；统一单包与 `fixed`/`linked` 组的 `compute_group_target_version` 基准计算（`initial_versions`）；二次预发布 changelog 过滤已消费 `consumed` changeset；空发布不生成冗余 `pre.json` 编辑并在 `exit` 时清理 `pre.json`。
  - **`publish` / `pack` / `tag` 与生态适配**：修复 `publish` 状态按 `(unit_id, version, target)` 原地更新、`--only` 闭包校验、`private_publish`、拓扑发布顺序、失败续跑 `registry_lookup` 与 `after_publish` 自动 tag（`--allow-uncommitted` 脏树跳过自动 tag）；接入 `config.publisher`（`command` -> `PublisherRegistry`、`dryRunFirst`、`registry`）、manifest 版本一致校验与 `.moonset/pack-results.json` 产物校验；修复 `cargo package --list --allow-dirty` dry-run（不再误传 `--dry-run`）、`moon package --dry-run`、`Cargo.toml` `publish = []` 禁令、`cargo_req_span` 键名匹配与 `**` glob、`pnpm-workspace.yaml` `#` 注释剥离；统一 `VersionPlan.tags` 模板渲染与 Git ref 规则校验。
  - **Changelog 与配置/CLI**：在 [workspace/discovery.mbt](../workspace/discovery.mbt) 收集 Git `changeset_commits`，在 [engine/version_plan.mbt](../engine/version_plan.mbt) 提取 summary `pr:`/`commit:`/`author:` 元数据喂入内置 `git`/`github` 生成器（无信息时优雅降级），并支持同目录多单元聚合 `CHANGELOG.md`；完整接通 `commit.mode`（`add`/`version`/`both`）+ `--no-commit`、`version --empty`、`doctor --fix`（可逆补缺）与 `npm`/`cargo`/`moon` `--registry` / CI 环境检查；修复 `cli/arguments.mbt` 中 `--registry` 顺序无关解析与 `has_doctor` 误判；规范 `cli::run` 策略门禁退出码 `1` 与非 `status` 命令简洁 JSON 错误信封。
- **测试与 SDD 文档同步**：
  - 建立 [test-strategy.md](test-strategy.md) §3 全部 8 个 `fixtures/` 最小集，扩充 [engine/planner_test.mbt](../engine/planner_test.mbt)、[engine/version_test.mbt](../engine/version_test.mbt)、[workspace/integration_test.mbt](../workspace/integration_test.mbt)、[executor/executor_test.mbt](../executor/executor_test.mbt)、[cli/cli_wbtest.mbt](../cli/cli_wbtest.mbt) 与 [scripts/cli-integration.mbtx](../scripts/cli-integration.mbtx)。
  - 同步更新 [docs/README.md](README.md)、[需求规格](requirements.md)（补齐测试映射与验证证据）、[命令契约](commands.md)、[混合 workspace 设计](mixed-workspaces.md) 与 [测试策略](test-strategy.md)。
- **尚余部分/延后事项**：
  - `FR-014`/`FR-015`（GitHub Action 在线演练与 GitHub App 服务端逻辑）、`FR-022`（多平台原生二进制目标产物矩阵）、`FR-023`（跨分区自动协调导出）以及非 `crates.io` Cargo registry / Tauri 同步仍维持 `Proposed`/`Partial`/`Deferred` 状态。
