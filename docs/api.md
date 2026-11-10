# 编程 API

> API 目标：让 MoonBit 库、CI action 和外部工具复用同一个模型与 planner。名称在实现前为设计名，发布时以生成的 `.mbti` 为准。

## 1. 公共包

| 包 | 责任 | 稳定性 |
|---|---|---|
| `@moonset/model` | `UnitId`、`ReleaseUnit`、`EcosystemWorkspace`、`WorkspaceSnapshot`、`Changeset`、`ReleasePlan`、错误和 JSON schema | 目标 v1 稳定 |
| `@moonset/engine` | `discover`、`read_changesets`、`build_plan`、`status`、`apply_plan` facade | v1 稳定 |
| `@moonset/changelog` | 内置生成器、`ChangelogGenerator`、registry | v1 稳定 |
| `@moonset/adapters` | Git、filesystem、publisher、clock 的接口和参考实现 | v1 实验，v2 稳定 |

CLI 只调用 engine facade；不能复制 planner 逻辑。

## 2. 核心函数形状

```text
async fn discover(root~ : String, io~ : WorkspaceIo) -> WorkspaceSnapshot raise
async fn read_changesets(snapshot~ : WorkspaceSnapshot, fs~ : FileSystem) -> Array[Changeset] raise
fn build_plan(snapshot~ : WorkspaceSnapshot, changesets~ : Array[Changeset], pre~ : PreState?) -> ReleasePlan raise
async fn apply_plan(plan~ : ReleasePlan, fs~ : FileSystem, clock~ : Clock) -> ApplyResult raise
async fn publish(plan~ : ReleasePlan, publisher~ : Publisher, options~ : PublishOptions) -> PublishResult raise
```

精确参数、错误类型和 optional label 在实现时用当前 MoonBit 工具链确认；不会从其他语言 API 直接翻译。

## 3. 适配器接口

- `FileSystem`：read/write/rename/hash/list；默认实现基于 `moonbitlang/core/async/fs`。
- `Git`：status、diff、changed_files、commit、tag、push；命令参数独立传递。
- `Publisher`：preflight、publish、already_published；默认实现调用 `moon publish`，可替换为 registry HTTP 或测试 double。
- `Clock`：`today_utc`、`unix_seconds`；测试使用固定时钟。
- `Prompt`：confirm/select/input；CI 使用 non-interactive 实现。

混合 workspace 新增 `EcosystemAdapter` 与 `ArtifactProvider`（设计中）：

- `EcosystemAdapter`：发现成员、声明字段所有权、解析/更新原生依赖、生成清单 diff、校验版本/渠道能力、staging 锁文件、pack；各步骤返回结构化数据。其 I/O 步骤在 planner 外执行，不能把 install 隐藏在纯 build_plan 中。
- `ArtifactProvider`：规划时声明源与派生包、平台产物和构建依赖，执行时交付带版本/commit/hash 的产物。未知产物不能直接成为发布目标。
- `PublisherRegistry`：按 `(ecosystem, unitId, target)` 路由，区分 already-published、内容冲突和能力不支持。单一 `Publisher` 参数仅适用于单目标便捷 API。

原 `Module` 设计改为 ReleaseUnit；API 尚未发布，这次是草案修订。精确 trait 方法将在 adapter conformance fixtures 建立后冻结，见 [混合 workspace 设计](mixed-workspaces.md)。

## 4. 版本策略

公共 API 版本化遵循：

- `model` 的字段只新增可选字段；删除或改变含义需要 major。
- `ReleasePlan.schemaVersion` 独立于 moonset CLI 版本。
- 适配器 trait 增加方法时提供 default 或新 trait，避免破坏旧实现。
- 生成器和 publisher 名称必须可在 plan 中追踪。

## 5. API 安全边界

核心 API 不接收原始 shell 字符串、不输出凭据、不允许 generator 直接写文件。需要宿主权限的实现必须显式传入 adapter；这样 planner 和 changeset parser 可以在 wasm/native 测试中复用。
