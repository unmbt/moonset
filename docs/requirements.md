# 需求规格

> 状态：Phase 1～5 核心能力、混合 workspace、`FR-022` 多平台产物矩阵与 build/publish 分离 DAG、`FR-023` 共存导出、`FR-025` 自动创建 GitHub Release、`FR-026`～`FR-031`（外部格式化器、Glob 扩展、`snapshot` 配置、`pre.directory` 隔离、复合 SemVer 范围、API Publisher 与分目标发布映射）、`NFR-005` 性能基准、PR Bot GitHub Action 与 `OPS-002` 审计事件/`v1` 浮动标签自动化均已实现并完成本地验证；在线 GitHub Runner 环境演练待推送触发，非 crates.io Cargo registry / Tauri 保持 `Partial`/`Deferred`。

### 开发验证约束

本项目的本地验证必须复用 CI 的严格告警策略：提交前运行
`moon check --target native --deny-warn`。新增或修改测试后还应运行
`moon test --target native --deny-warn`；若当前 MoonBit 工具链不接受 test 的
`--deny-warn` 参数，必须至少运行严格 check，并记录工具链限制和替代命令。
本地依赖验证前执行 `moon update` 并运行 `moon publish --dry-run` 验证干净打包链路（传递依赖已在 `moon.mod` 显式锁定）。

## 1. 问题与目标

MoonBit workspace 可以包含多个 `moon.mod`、`moon.pkg` 和 `moon.work`，但现有版本修改、变更记录、发布和 Git 标签流程分散在人工脚本中。moonset 要把“贡献者记录变更意图”和“维护者生成可审阅发布计划”连接起来，同时保留 MoonBit 清单的格式和注释。

目标：

- 让每个需要发布的改动以可审阅的 changeset 文件进入 Git。
- 从 workspace 依赖图计算确定性的版本和 changelog 变更。
- 支持稳定版、预发布版、快照版和多包协同发布。
- 让本地命令、GitHub Actions（含 PR Bot）和 MoonBit 编程 API 使用同一套核心规划器。
- 让注册表发布和 Git 操作可替换、可模拟、可重试。
- 支持 MoonBit 与 npm/pnpm workspace 分区共存，并分阶段支持统一发布；架构从第一阶段纳入跨生态身份、清单所有权和构建依赖。详见 [混合 workspace 设计](mixed-workspaces.md)。

## 2. 非目标

- 不实现 Mooncakes 注册表、GitHub App 或任何中心化托管服务。
- 不替代 `moon` 编译器、依赖解析器和包发布权限系统。
- 不默认修改没有 release 的包版本。
- 不在核心库中执行任意 shell 字符串；外部命令必须通过参数数组或明确的插件协议调用。
- 不把 Changesets 的 Node.js 包加载模型直接搬进 MoonBit；自定义生成器使用编译期 API 或受限进程协议。

## 3. 用户与使用场景

| 角色 | 场景 | 主要入口 |
|---|---|---|
| 贡献者 | 说明一个 PR 需要发布哪些包以及变更级别 | `moonset add` |
| 维护者 | 检查待发布内容和依赖联动 | `moonset status`、`publish-plan` |
| 发布负责人 | 生成版本、更新 changelog、提交审阅 | `moonset version` |
| CI | 在合并后发布 Mooncakes 并创建标签 | `publish`、`tag` |
| PR Bot（Action） | 对缺少或待发布的 changeset 在 PR 下幂等评论或加标签 | `pr-check` + `pr-comment` Action (`status --since`) |
| MoonBit 集成作者 | 复用解析、规划、生成或发布能力 | `@moonset/*` API |

## 4. 功能需求

| ID | 需求 | 验收条件 | 状态 | 验证证据 |
|---|---|---|---|---|
| FR-001 | 初始化 | `init` 创建 `.changeset/`、默认 `config.json` 和 README；重复运行不覆盖用户文件，并给出可机器读取结果。 | Implemented | `scripts/cli-integration.mbtx` (`init --json` / 幂等跳过) |
| FR-002 | 记录变更 | `add` 支持交互式和非交互式输入，生成唯一 Markdown changeset；支持 `major/minor/patch/none`，禁止未知包名和空摘要（除非显式 `--empty`）。 | Implemented | `cli/cli_wbtest.mbt`、`scripts/cli-integration.mbtx` (`add` 校验与提交) |
| FR-003 | 发现 workspace | 按 release domain 发现已授权的 workspace；MoonBit adapter 读取 `moon.work` 成员和单模块项目，输出稳定排序的 ReleaseUnit，区分编译包和发布模块。 | Implemented (MoonBit/npm/Cargo) | `workspace/integration_test.mbt`、`workspace/cargo_test.mbt` |
| FR-004 | 解析 changeset | 解析平面 YAML front matter 子集和 Markdown 摘要，报告文件路径、行号、包名和版本类型；任何一个文件无效时规划失败且不写盘。 | Implemented | `engine/parsing_test.mbt`、`fixtures/invalid-frontmatter/` |
| FR-005 | 生成 release plan | 合并 changeset、fixed/linked 组、内部依赖和预发布状态，输出 old/new version、原因和受影响文件；同样输入必须得到同样计划。 | Implemented | `engine/planner_test.mbt`、`engine/planner_golden_test.mbt` |
| FR-006 | 查看状态 | `status` 显示待处理 changeset、预计版本、缺失 changeset 和配置错误；支持 `--since`、`--verbose`、`--output json`。 | Implemented | `scripts/cli-integration.mbtx` (`status --since` / 退出码 `1`) |
| FR-007 | 应用版本 | `version` 原子更新 `moon.mod`、相关依赖范围、各包 `CHANGELOG.md`，消费已应用 changeset，并保留可审阅 diff。 | Implemented | `engine/version_test.mbt`、`executor/executor_test.mbt` |
| FR-008 | 预发布 | `pre enter <tag>`、`pre exit` 管理 `.changeset/pre.json`；重复进入、错误退出和标签非法时给出明确错误。 | Implemented | `engine/planner_test.mbt`、`engine/version_test.mbt`、`scripts/cli-integration.mbtx` |
| FR-009 | 发布 | `publish` 只发布计划中有新版本且允许发布的模块，支持 dry-run、Mooncakes/npm/Cargo/command target、逐目标状态和失败续跑；默认不自动执行 `version`。 | Implemented | `executor/executor_test.mbt`、`scripts/cli-integration.mbtx` |
| FR-010 | 标签 | `tag` 根据当前版本创建确定性 Git 标签，支持单模块 `vX.Y.Z` 与 workspace `name@X.Y.Z`，支持预览和可选推送。 | Implemented | `executor/executor_test.mbt`、`scripts/cli-integration.mbtx` |
| FR-011 | 打包与计划 | `pack` 调用 MoonBit/npm/Cargo 打包流程并输出带来源与摘要的 artifact JSON；`publish-plan` 输出不改盘的发布 JSON。 | Implemented | `executor/executor_test.mbt`、`scripts/cli-integration.mbtx` |
| FR-012 | 配置 | `.changeset/config.json` 支持版本策略、fixed/linked、ignore、私有包、changelog、tag、publisher、GitHub 和格式化器；未知顶层字段默认报错。 | Implemented | `engine/parsing_test.mbt`、`scripts/embed-schema.mbtx --check` |
| FR-013 | 自定义 changelog | 内置生成器覆盖纯文本、Git、GitHub 三类；MoonBit API 和受限 JSONL 进程协议都能提供自定义 release line；支持同目录聚合输出。 | Implemented | `changelog/changelog_test.mbt`、`engine/version_test.mbt`、`scripts/cli-integration.mbtx` |
| FR-014 | GitHub Action 自动化 | 提供 `setup`、`pr-check`、`pr-comment` 与根 Action（`version-pr`/`publish`）及参考工作流；按 Job 最小权限隔离，支持 OIDC 或显式令牌，基于远端 tag 幂等防重发；`version-pr` 通过纯核 `render_release_pr_body` 输出含说明引导、`pre` 警告、版本汇总表与 `# Releases` 逐包 Changelog 详情的 Release PR 正文并自动解析 PR/作者元信息。 | Implemented (本地实现与静态审查已通过；在线 runner 演练待触发) | `action.yml`、`setup/`、`pr-check/`、`pr-comment/`、`engine/release_pr.mbt`、`docs/examples/workflows/`、`scripts/lint-workflows.mbtx` |
| FR-015 | PR Bot（Action） | 使用双 Job 隔离权限（Job 1 只读计算、Job 2 写评论）；按 marker `<!-- moonset-bot:changeset-check -->` 与可信 bot 作者幂等更新同一条评论；覆盖 release/missing/empty/none/error 五种状态；不直接改版本或发布。 | Implemented (本地实现与测试已通过；真实 Fork PR 在线演练待触发) | `engine/pr_comment.mbt`、`engine/pr_comment_test.mbt`、`cli/cli_wbtest.mbt`、`scripts/cli-integration.mbtx`、`pr-check/`、`pr-comment/` |
| FR-016 | 编程 API | 核心模型、解析器、规划器、执行器和适配器接口有稳定的 MoonBit 公共包；I/O 通过注入接口可测试。 | Implemented (`api`, `executor`, `native` + `wasm-gc` pure core) | `fixtures/external-moonbit-api/`、`moon test --target wasm-gc` |
| FR-017 | 环境诊断 | `doctor` 只读检查 MoonBit、Git、workspace、配置、publisher 和必要权限，输出可修复建议；支持 `--fix` 可逆补缺。 | Implemented | `executor/executor_test.mbt`、`scripts/cli-integration.mbtx` |
| FR-018 | 混合 workspace 与所有权 | 同级、嵌套、同目录双清单均可表达；按声明发现 npm/pnpm 与 MoonBit 成员；工具清单、生成目录、嵌套仓库不被默认接管；重复所有权在写入前报错。 | Implemented | `workspace/integration_test.mbt`、`engine/planner_test.mbt` |
| FR-019 | 跨生态身份 | 使用生态前缀 UnitId；同名跨生态单元可区分；混合 changeset、选择器、pre 状态和计划使用相同 ID；旧记录迁移提供可审阅映射。 | Implemented | `engine/parsing_test.mbt`、`workspace/integration_test.mbt` |
| FR-020 | 跨生态依赖与版本组 | 包依赖、build bridge 和 fixed/linked 分开；bridge 提升 consumer 的最低 bump 并进入闭包；环与不完整 `--only` 选择在写入前失败。 | Implemented | `engine/planner_test.mbt`、`executor/executor_test.mbt` |
| FR-021 | 原生清单和锁文件 | adapter 在隔离 staging 使用精确 packageManager 版本校验/更新锁文件；`verify-only` 差异失败，不改写 `workspace:` 协议。 | Implemented | `executor/staging.mbt`、`engine/planner_test.mbt` |
| FR-022 | 构建产物与多目标发布 | 支持在 `experimental.mixedWorkspaces.units.<id>.artifacts` 声明多平台构建目标与关联平台衍生包；`publish-plan` 与 `release-state.json` 持久化 build/publish 分离 DAG；`pack` 支持 `--target`/`--manifest-out`/`--verify`/`--artifacts-dir`；`publish` 先完整校验必需平台产物与 commit/hash 一致性再逐 `(unitId, version, target)` 拓扑发布，必需平台缺失或失败时阻断主包并保留已发布凭据支持续跑，可选平台不阻塞主包。 | Implemented | `engine/artifact_dag_test.mbt`、`executor/executor_test.mbt`、`fixtures/partial-publish/`、`scripts/cli-integration.mbtx` |
| FR-023 | 与已有工具共存 | Changesets 等工具和 moonset 分区管理，changeset/版本字段/锁文件只有一个写入者；不互相消费记录或静默迁移配置；只读导出跨分区协调摘要。 | Implemented | `engine/coexistence.mbt`、`engine/coexistence_test.mbt`、`workspace/integration_test.mbt` |
| FR-024 | Adapter 能力契约 | 接口涵盖 discovery、编辑、range、lockfile、pack 和 publish；未知能力在 apply 前明确失败；Cargo crates.io 已接入，其他 Cargo registry/Tauri 保持 Deferred。 | Partial (`executor::ExecutionHost` + `PublisherRegistry` + capability gating; v1 `adapters` traits preserved) | `adapters/protocol_test.mbt`、`executor/executor_test.mbt` |
| FR-025 | 自动创建 GitHub Release 与 Release Notes 提取 | 提供纯核 `extract_release_notes` 与只读 CLI `moonset release-notes`（支持单包与 `--from-state` 多包）；根 Action `mode: publish` 支持 `create-github-releases`（默认 `'true'`），按 `CHANGELOG.md` 版本章节幂等创建 GitHub Release（无匹配章节回退 `--generate-notes`，已存在则跳过），`release-binaries.yml` 复用该 CLI 替代重复脚本解析。 | Implemented | `changelog/changelog_test.mbt`、`cli/cli_wbtest.mbt`、`scripts/cli-integration.mbtx` |
| FR-026 | 外部格式化器执行与 `--no-format` | `formatter`（`builtin`/`prettier`/`oxfmt`/`biome`/`dprint`）与 `format`（`false`/`auto`/工具名）生效；`add` 与非 `--dry-run` 的 `version` 在写盘后、自动提交前按工具支持的扩展名通过参数数组调用格式化器；`--no-format` 或 `format: false` 跳过外部调用；只读命令与 `--dry-run` 永不调用格式化器。 | Implemented | `engine/v020_features_test.mbt`、`executor/executor_test.mbt`、`scripts/cli-integration.mbtx` |
| FR-027 | 版本组与变更路径 Glob 扩展 | `fixed`、`linked`、`ignore` 支持 `*`/`?`/`[...]`/`{...}`/`(...)` glob 匹配（展开后去重并检查版本组冲突）；`changedFilePatterns` 支持 `*`/`**`/`?`/`[...]`/`{...}`/`(...)` 与 `!` 否定过滤；非法 glob 语法在写盘前以 `invalid-config` 拒绝。 | Implemented | `engine/glob.mbt`、`engine/v020_features_test.mbt`、`engine/parsing_test.mbt` |
| FR-028 | `snapshot` 配置驱动与模板生成 | `version --snapshot <tag>` 受 `snapshot.enabled` 门禁保护（未开启则以 `snapshot-disabled` 拒绝）；按 `snapshot.useCalculatedVersion` 选择 `0.0.0` 或计算版本基准；按 `snapshot.prereleaseTemplate`（支持 `{tag}`、`{datetime}`、`{commit}`、`{version}`）渲染并校验合法 SemVer，更新内部依赖范围且不消费稳定 changeset 或写入 `release-state.json`。 | Implemented | `engine/policy.mbt`、`engine/v020_features_test.mbt`、`scripts/cli-integration.mbtx` |
| FR-029 | `pre.directory` 隔离语义 | 在 `pre` `active` 模式下运行 `version` 时，已消费 changeset 原子迁移至 `pre.directory`（默认 `.changeset/pre`）并与 `pre.json` 的 `consumed` 协同；`discover` 在存在 `pre.json`（`active`/`exit`）时合并读取 `changeset_directory` 与 `pre.directory`；`pre exit` 后 `version` 毕业时统一清理两个目录的 changeset 与 `pre.json`。 | Implemented | `engine/v020_features_test.mbt`、`workspace/integration_test.mbt`、`scripts/cli-integration.mbtx` |
| FR-030 | 复合 SemVer 范围解析与更新 | npm 支持 `||` 联合、空格合取、连字符 `A - B`、`>`/`>=`/`<`/`<=`/`=`/`^`/`~` 与 X-range；Cargo 支持逗号合取、`||` 联合、`>`/`>=`/`<`/`<=`/`=`/`^`/`~` 与通配符；非法语法在规划前报错，更新后范围保证满足目标版本。 | Implemented | `engine/semver_range.mbt`、`engine/v020_features_test.mbt` |
| FR-031 | API Publisher 注册入口与分目标发布映射 | 提供 `ApiPublisher` / `ApiPublisherRegistry` 与 `publish_release_with_api(_with)` 使 `publisher.kind = "api"` 与单单元自定义 publisher 可编程接入；`--registry` 与 `--tag`（及 `publisher.registry`）支持按生态（`npm=<val>,cargo=<val>`）或按 UnitId（`npm:@acme/ui=<val>`）分目标分发，保留无作用域参数跨混合生态时的安全拒绝。 | Implemented | `engine/v020_features_test.mbt`、`executor/executor_test.mbt`、`cli/cli_wbtest.mbt` |

## 5. 非功能需求

| ID | 需求 | 验收条件 | 状态 | 验证证据 |
|---|---|---|---|---|
| NFR-001 | 跨平台 | Windows、Linux、macOS native 构建；Git 和路径处理不依赖 POSIX shell。 | Implemented | `.github/workflows/ci.yml`、`moon test --target native` |
| NFR-002 | 确定性 | 相同 Git 树、时间输入和配置产生相同计划；发布时间由 `Clock` 注入，默认使用 UTC。 | Implemented | `engine/planner_test.mbt`、`engine/planner_golden_test.mbt` |
| NFR-003 | 可恢复 | 文件替换、Git 标签和发布步骤有阶段状态；失败结果包含已完成步骤和下一条恢复命令。 | Implemented | `executor/executor_test.mbt` (journal rollback & partial publish retry) |
| NFR-004 | 可观测 | 人类输出可读；`--json` 使用版本化 schema，日志不泄露 token。 | Implemented | `cli/cli_wbtest.mbt`、`scripts/cli-integration.mbtx` |
| NFR-005 | 性能 | 100 个包、1000 个 changeset 预算冻结：纯规划+渲染 p50 < 1 s（实测 `27.66 ms`）；CLI `status --json` p50 < 5 s（实测 `411 ms`）；`status --since`（含批量快照与 Markdown 渲染）p50 < 5 s（实测 `1495 ms`）。 | Implemented | `engine/planner_bench_test.mbt`、`scripts/bench-status.mbtx` |
| NFR-006 | 兼容性 | 只使用当前 MoonBit 工具链验证过的 API；依赖升级必须记录 ADR 和回归结果。 | Implemented | `moon check --target native --deny-warn`、`moon check --target wasm-gc` |

## 6. 安全需求

| ID | 需求 | 验收条件 | 状态 | 验证证据 |
|---|---|---|---|---|
| SEC-001 | 命令注入防护 | Git、Moon 和 publisher 命令使用可执行文件加参数数组；插件命令明确显示并可禁用。 | Implemented | `adapters/protocol_test.mbt`、`executor/host.mbt` |
| SEC-002 | 发布确认 | 真实发布前显示 registry、包、版本、访问级别和标签；CI 必须显式设置非交互模式。 | Implemented | `executor/publish.mbt` (`--yes` 门禁退出码 `1`) |
| SEC-003 | 最小权限 | GitHub Action 文档与参考 workflow 按 Job 只申请必须的 `contents`、`pull-requests`、`issues` 权限；发布 token 不进入日志。 | Implemented | `adapters/protocol.mbt`、`executor/doctor.mbt`、`scripts/lint-workflows.mbtx` |
| SEC-004 | 工作区安全 | 默认拒绝脏工作树、未跟踪 `.changeset` 和发布中间状态；绕过必须是显式 flag 且记录。 | Implemented | `executor/publish.mbt`、`executor/tag.mbt` |
| SEC-005 | `pull_request_target` 隔离 | Checkout PR head 的 Job 必须设置 `persist-credentials: false` 且无写权限，仅执行可信预编译/基础分支二进制静态读取，禁止运行目标仓库构建或脚本；禁止 `${{ github.event.* }}` 与 `${{ inputs.comment }}` 直接插值进 `run:`；评论文本转义防注入。 | Implemented | `scripts/lint-workflows.mbtx`、`engine/pr_comment_test.mbt`、`.github/workflows/moonset-pr-bot.yml` |

## 7. 运维需求（OPS）

| ID | 需求 | 验收条件 | 状态 | 验证证据 |
|---|---|---|---|---|
| OPS-001 | 预编译二进制分发 | `release-binaries.yml` 按 tag 构建 Linux(x64/arm64)、macOS(arm64)、Windows(x64) 原生二进制与 `SHA256SUMS` 并随 Release 发布；`setup` Action 下载后必须完成 SHA-256 校验。 | Implemented (已完成 `v0.1.0` 流水线验证并支持 `@v1` 主版本解析) | `.github/workflows/release-binaries.yml`、`setup/install.sh`、`setup/action.yml` |
| OPS-002 | Action 审计事件与 `v1` 浮动标签 | `pr-check`、`pr-comment` 与根 `action.yml` 均输出脱敏紧凑 JSON `audit-event`（`schemaVersion`/`repository`/`runId`/`runAttempt`/`command`/`planFingerprint`/`result`/`durationMs`/`errorCode`）并写入 Step Summary；正式 SemVer tag 发布成功后自动更新 `v1` 浮动标签。 | Implemented | `scripts/lint-workflows.mbtx`、`action.yml`、`pr-check/action.yml`、`pr-comment/action.yml`、`.github/workflows/release-binaries.yml` |

## 8. 退出码契约

- `0`：成功，包含没有待发布变更的成功查询。
- `1`：可修复的用户或策略问题，例如缺少 changeset、验证失败或需要确认。
- `2`：配置、changeset 或 workspace 无效。
- `3`：外部工具、Git、网络或注册表失败；结果包含恢复提示。

## 9. 验收场景

1. 单模块项目添加一个 patch changeset，`status --output json` 能看到预计版本，`version` 只修改该模块和 changelog。
2. 两个互相依赖的模块中只修改被依赖者，规划器按配置判断是否提升依赖者并更新范围。
3. fixed 组中一个包有 major changeset，组内全部包得到同一目标版本。
4. 预发布模式进入 `next` 后连续两次版本，序号单调递增；退出后下一次稳定版不带预发布后缀。
5. 一个 changeset front matter 损坏时，`version` 不改任何 manifest/changelog。
6. `publish --dry-run` 调用 publisher 的验证路径但不创建注册表版本或 Git 标签。
7. 外部贡献者从 Fork 提交缺少 changeset 的 PR 时，PR Bot Action 在双 Job 隔离下幂等评论一次并可选添加标签；重复推送或补上 changeset 后仅更新同一条评论，不触发发布且不执行 Fork 代码。
8. 自定义生成器超时或输出非法 JSON 时，发布计划失败且不写入 changelog。
9. 一个目录内 `moon.mod` 与 `package.json` 版本不同，只配置 MoonBit 分区时，JS 版本和锁文件保持原状。
10. 统一配置下 MoonBit producer 升级触发 npm consumer 的 patch bridge；npm `private: true` 始终禁止发布，即使可以更新其版本。
11. 平台包成功发布但 JS 主包失败时，保留成功凭据并仅重试主包；不创建“整个产品已发布”的标签。


Phase 5 supports experimental operational adapter ports, JSONL external changelog generators, npm/pnpm routing, and Cargo workspace discovery/pack/publish for crates.io. External plugins are trusted processes; the protocol limits executable selection, environment variables, elapsed time, and output size, but does not provide OS-level file or network isolation.
