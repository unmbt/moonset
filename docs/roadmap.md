# Roadmap

> Roadmap 只描述可交付能力，不承诺日历日期。每个阶段完成后必须满足退出条件，才能进入下一阶段。

## Phase 0 — 规格与探针（已完成）

交付：需求、命令契约、配置、数据模型、架构、API、自动化和 ADR；建立最小 fixtures 和工具链探针。

退出条件：

- `requirements.md` 中 FR-001 至 FR-006 的边界已 Accepted。
- 选定 `core/async`、manifest、Git 和 SemVer 的实际 API，并有 `moon ide doc` 或项目代码证据。
- 规划器输入/输出 fixture 能覆盖单模块、workspace、fixed、linked、pre。
- 补充评审 [混合 workspace 设计](mixed-workspaces.md) 与 ADR-006，明确共存分区和统一管理；不把“可换 publisher”当成已经支持混合 workspace。

## Phase 1 — 核心读模型与规划器（已完成）

交付：workspace discovery、无损 manifest 读取、changeset parser、config loader、SemVer、依赖图和纯 release planner；实现 `status` 与 `publish-plan`。验收命令与边界见 [Phase 1 契约](phase-1-contract.md)。

退出条件：

- 规划器无 I/O 依赖，golden tests 在 `native` 与 `wasm-gc` 通过。
- 错误定位包含文件和行列；无效输入不会产生写入。
- JSON 输出 schema 版本为 `1`，并有兼容性测试。
- 核心从开始使用 UnitId、ReleaseUnit、ownership 和分类型依赖；支持同目录双清单的共存边界，覆盖 FR-018、FR-019、FR-023 的基础场景。

## Phase 2 — 贡献工作流（已完成）

交付：`init`、`add`、`pre`、交互式 TUI 摘要、格式化和 changeset README；补充 PR 检查脚本与 `doctor`。

退出条件：

- 新建项目从 `init` 到 `status` 全流程可运行。
- 重复 `init` 不覆盖文件，`add` 生成 ID 不冲突。
- CI 能使用 `status --since` 判断是否需要 changeset。

## Phase 3 — 版本与 Changelog（已完成）

交付：`version`、内置 changelog 生成器、依赖范围更新、fixed/linked/private 策略、原子写盘与 journal 恢复、`tag`、npm/pnpm/Cargo 混合清单发现与隔离锁文件 staging。

退出条件：

- 已实现 version-plan、内置 changelog（builtin/git/github）、MoonBit/npm/Cargo 版本编辑、release state、journal 恢复、tag CLI，以及 npm/pnpm/Cargo 隔离 staging 锁文件更新与 `verify-only`。
- 版本前后所有 manifest 的语法仍可被对应生态工具链解析。
- 失败演练后工作区可按恢复指令回到一致状态。
- 生成的 changelog 有稳定格式、日期和链接策略；已覆盖 FR-018 至 FR-021。

## Phase 4 — 发布与官方自动化（已完成）

交付：`pack`、`publish`、Mooncakes/npm/Cargo 命令适配、模块化 GitHub Actions（`setup`/`pr-check`/`pr-comment`/根发布 `action.yml`）、跨平台预编译二进制发布工作流与用户安装脚本（`scripts/install.sh`、`scripts/install.ps1`）、逐目标状态与失败续跑。

退出条件：

- dry-run 不修改注册表和 Git 引用。
- 发布失败能区分已发布和未发布模块，重复执行不会错误重发（含 `moon view` 幂等查询与 `publish-state.json` 续跑）。
- CI 工作流与 Action 通过 `actionlint` 与 `scripts/lint-workflows.mbtx` 静态安全审查。
- 预编译二进制与 `SHA256SUMS` 由 tag / `workflow_call` 工作流自动构建并在安装时校验。
- 已完成 `v0.1.0` 自举 Release PR、`mooncakes.io` 正式发布与多平台二进制分发流水线验证。

## Phase 5 — 扩展生态（已完成）

交付：`unmbt/moonset/api` 稳定接口、纯 `changelog` 生成器、JSONL generator/publisher 协议、第三方适配器示例与 Cargo (`crates.io`) 适配。

退出条件：

- API 版本策略（`api_version = "1.0.0"`）和兼容承诺写入 [Phase 5 API](phase-5-api.md)。
- 一个外部 MoonBit 包（`fixtures/external-moonbit-api`）和一个外部进程 JSONL 插件完成端到端测试。
- 插件超时、非法输出和权限拒绝均有测试。

## Phase 6 — PR Bot Action 与规模化治理（进行中 — 核心已随 `v0.1.0` 交付）

已交付：模块化 PR Bot Action（`pr-check` + `pr-comment`）、PR 评论幂等去重与标签同步、HTML/Markdown/提及注入转义、`FR-023` 共存只读协调导出、`NFR-005` 100 包 / 1000 changeset 性能基准（`status --since` 实测 `1495 ms`）、以及 `v0.1.0` 自举发布流水线。

后续退出条件（`0.1.1+`）：

- 已落地：**审计事件收敛**（`pr-check`、`pr-comment`、`action.yml` 输出 `audit-event` 与 Step Summary）与 **`v1` 浮动标签自动维护**（`release-binaries.yml` 正式发布时自动更新 `v1`）。
- 待线上触发：完成外部贡献者 Fork PR 的 `pull_request_target` 真实线上联调。
- **大规模性能与增量缓存**（`0.2.0+`）：将基准扩展至 1000 包 / 10000 changeset，按实测评估增量快照缓存。

## 后续迭代规划（`v0.1.1` / `v0.2.0+`）

在 `0.1.0` 稳定基线之上，已按零破坏原则完成第 1、5、6 项，其余按需推进：

1. **`FR-022` 多平台原生产物矩阵与 build/publish 分离 DAG（已随 `0.1.1` 落地）**
   - 已实现 `artifacts` 声明、build/publish 分离 DAG、`pack --target / --manifest-out / --verify`、`publish --artifacts-dir` 以及必需/可选平台包校验与阻断。
2. **更多平台与生态扩展（原 `Deferred` 项按需推进）**
   - 预编译二进制按需扩展 Windows ARM64 / macOS x64 构建目标；
   - 评估并接入非 `crates.io` 私有 Cargo registry；
   - 评估 Tauri 应用版本同步适配器（如 `tauri.conf.json`）。
3. **外部端口与生态一致性收敛（`FR-024`）**
   - 进一步将实验性 `adapters` trait 与 `executor::ExecutionHost` 统一下沉，提供更完整的 conformance suite。
4. **文档与示例演进**
   - 扩充混合 workspace（MoonBit + pnpm / Cargo）实战模板与第三方 JSONL 插件示例仓库。
5. **发布 Action 自动创建 GitHub Release（基于 `CHANGELOG.md`，已随 `0.1.1` 落地）**
   - 已实现纯核 `extract_release_notes`、只读 CLI `moonset release-notes`、根 `action.yml` 的 `create-github-releases`（默认开启）以及 `release-binaries.yml` 资产补充上传衔接。
6. **Schema 已定义但尚未接入的配置与扩展能力补齐（`FR-026`～`FR-031`，已落地）**
   - **外部格式化器执行（`FR-026`）**：已接入 `formatter`（`prettier` / `oxfmt` / `biome` / `dprint`）、`format` 模式与 `--no-format`，通过参数数组调用并按扩展名安全过滤，`doctor` 同步检测外部格式化器可用性；
   - **版本组与变更路径 Glob 扩展（`FR-027`）**：已为 `fixed`、`linked`、`ignore` 开放 `*` / `?` / `[...]` / `{...}` / `(...)` glob 匹配（含展开冲突检查与 `--only` 闭包对齐），并为 `changedFilePatterns` 补齐 `[...]`、`{...}`、`(...)`/extglob 及 `!` 否定过滤；
   - **`snapshot` 完整配置驱动（`FR-028`）**：已将 `snapshot.enabled` 门禁、`snapshot.useCalculatedVersion` 与 `snapshot.prereleaseTemplate`（`{tag}`、`{datetime}`、`{commit}`、`{version}`）接入 `version --snapshot` 规划、SemVer 校验与内部依赖更新；
   - **`pre.directory` 隔离语义（`FR-029`）**：已落地 `.changeset/pre` 等隔离目录迁移与 `pre.json` `consumed` 协同，`discover` 在 `active`/`exit` 模式下合并读取并在毕业时统一原子清理；
   - **复杂 SemVer 范围解析（`FR-030`）**：已补齐 npm `||` / 空格 / 连字符 / `>` / `<` / X-range 与 Cargo 逗号合取 / `||` / `>` / `<` / 通配符范围校验、匹配与保语义更新；
   - **发布路由细化（`FR-031`）**：已提供 `ApiPublisher` / `ApiPublisherRegistry` 与 `publish_release_with_api(_with)` 扩展注册入口，并支持混合生态下按生态或 UnitId 分发的 `--registry` / `--tag`（dist-tag）与 `publisher.registry` 映射。

## 明确暂缓项目

- Node Changesets 的配置、插件运行时及目录互写兼容：暂不承诺，保持分区共存边界（`FR-023`）。
- 任意动态 MoonBit 模块加载：由编译期 API 和 JSONL 协议覆盖，等工具链提供稳定模块加载机制后再评估。
- 默认自动提交/推送：保留显式配置开关（`commit.mode`），默认让 CI 或维护者控制 Git 提交边界。
