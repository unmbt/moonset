# 编程 API

> API 目标：让 MoonBit 库、CI action 和外部工具复用同一个模型与 planner。名称在实现前为设计名，发布时以生成的 `.mbti` 为准。

稳定入口位于 `unmbt/moonset/api`，由根包 `unmbt/moonset` 对等重导出。`model`、`engine`、`changelog` 为无宿主 I/O 纯库（双目标 `native` + `wasm-gc`）；`workspace`、`adapters`、`executor`、`api` 与根包为 `native` 宿主能力层。公共 API 当前遵循 [ADR-008](decisions/008-v030-api-and-adapter-convergence.md) 收敛至 **`api_version = "2.0.0"`**，所有公开函数签名涉及的类型均从门面完整重导出。

```text
engine.parse_config(source, path?) -> Config
engine.parse_changeset(source, id~, path~, mixed?, in_pre_dir?) -> Changeset
engine.parse_pre_state(source, path?) -> PreState
engine.build_plan(snapshot, changesets, pre?, generated_at?, snapshot_tag?) -> ReleasePlan
engine.build_version_plan_with_metadata(snapshot, analysis, options, ...) -> VersionPlan
engine.status_json(snapshot, plan, changeset_directory?) -> Json
workspace.discover(cwd, config_path?, since?) -> LoadedWorkspace          // async
executor.pack_artifacts_with(host, loaded, options) -> Array[PackResult]  // async
executor.publish_release_with(host, loaded, options) -> PublishResult     // async
executor.create_tags_with(host, loaded, options) -> TagResult             // async
cli.run(args_without_executable) -> Int                                   // async
```

纯函数使用 `MoonsetError` 报告输入错误；I/O 层使用 `ExecutionHost` 注入宿主文件、进程与时钟能力。`PublishOptions`、`PackOptions`、`TagOptions`、`VersionOptions` 采用默认构造 + Builder setter 模式，避免函数签名组合爆炸。

## 1. 公共包

| 包 | 责任 | 稳定性 |
|---|---|---|
| `@moonset/api` / `@moonset` | 统一对等 facade 与 `api_version = "2.0.0"` | v2.0 |
| `@moonset/model` | 强类型枚举、嵌套 `Config`、领域类型与统一 `ReleaseState` 编解码（`native` + `wasm-gc`） | v2.0 |
| `@moonset/engine` | 纯规划器、Changesets v3 `pre`/统一 `snapshot`、SemVer/Glob/Markdown 渲染（`native` + `wasm-gc`） | v2.0 |
| `@moonset/changelog` | 内置生成器、`ChangelogGenerator`、registry、release-notes 提取（`native` + `wasm-gc`） | v2.0 |
| `@moonset/adapters` | 能力契约、JSONL 进程插件协议、`PublisherRegistry`、`PublisherPort`/`RegistryHost` | v2.0 |
| `@moonset/executor` | `ExecutionHost`、异步生态驱动（MoonBit/npm/Cargo）、journal、staging、pack、publish、tag、doctor | v2.0 |

CLI 通过 workspace 读取输入，再调用同一个 engine planner；不能复制规划逻辑。

## 2. 核心函数形状

```text
async fn discover(root~ : String, io~ : WorkspaceIo) -> WorkspaceSnapshot raise
async fn read_changesets(snapshot~ : WorkspaceSnapshot, fs~ : FileSystem) -> Array[Changeset] raise
fn build_plan(snapshot~ : WorkspaceSnapshot, changesets~ : Array[Changeset], pre~ : PreState?) -> ReleasePlan raise
async fn apply_plan(plan~ : ReleasePlan, fs~ : FileSystem, clock~ : Clock) -> ApplyResult raise
async fn publish(plan~ : ReleasePlan, publisher~ : Publisher, options~ : PublishOptions) -> PublishResult raise
```

具体公共声明以各包生成的 `.mbti` 为准。API 遵循 SemVer；兼容新增走 minor，破坏性变更走 major。ReleasePlan JSON schema 单独版本化。

## 3. 适配器接口

- `FileSystem`：read/write/rename/hash/list；默认实现基于 `moonbitlang/core/async/fs`。
- `Git`：status、diff、changed_files、commit、tag、push；命令参数独立传递。
- `Publisher`：preflight、publish、already_published；默认实现调用 `moon publish`，可替换为 registry HTTP 或测试 double。
- `Clock`：`today_utc`、`unix_seconds`；测试使用固定时钟。
- `Prompt`：confirm/select/input；CI 使用 non-interactive 实现。

混合 workspace 新增 `EcosystemAdapter` 与 `ArtifactProvider`：

- `EcosystemAdapter`：发现成员、声明字段所有权、解析/更新原生依赖、生成清单 diff、校验版本/渠道能力、staging 锁文件、pack；各步骤返回结构化数据。其 I/O 步骤在 planner 外执行，不能把 install 隐藏在纯 build_plan 中。
- `ArtifactProvider`：规划时声明源与派生包、平台产物和构建依赖，执行时交付带版本/commit/hash 的产物。未知产物不能直接成为发布目标。
- `PublisherRegistry`：按 `(ecosystem, unitId, target)` 路由，区分 already-published、内容冲突和能力不支持。单一 `Publisher` 参数仅适用于单目标便捷 API。

原 `Module` 设计改为 ReleaseUnit；adapter trait 在 v1 标记 experimental，方法以生成的 `.mbti` 为准。

## 4. 版本策略

公共 API 版本化遵循：

- `model` 的字段只新增可选字段；删除或改变含义需要 major。
- `ReleasePlan.schemaVersion` 独立于 moonset CLI 版本。
- 适配器 trait 增加方法时提供 default 或新 trait，避免破坏旧实现。
- 生成器和 publisher 名称必须可在 plan 中追踪。

## 5. API 安全边界

核心 API 不接收原始 shell 字符串、不输出凭据、不允许 generator 直接写文件。JSONL runner 只启动显式登记的 executable，并可通过 `environment` 白名单传入运行所需变量。需要宿主权限的实现必须显式传入 adapter；这样 planner 和 changeset parser 可以在 wasm/native 测试中复用。
Operational adapter ports and the JSONL generator protocol are exposed from `unmbt/moonset/api`; adapter traits are experimental in API v1.
