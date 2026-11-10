# 数据模型

## 1. 核心实体

```text
WorkspaceSnapshot
 ├─ EcosystemWorkspace[]
 ├─ ReleaseUnit[]
 ├─ DependencyEdge[] + BuildBridge[]
 ├─ VersionOwnership[] + LockfileOwnership[]
 ├─ GitSnapshot
 └─ Config
Changeset[] + PreState? + WorkspaceSnapshot
                 │
                 ▼
           ReleasePlan
        ├─ Release[]
        ├─ FileEdit[]
        ├─ ChangelogEntry[]
        ├─ TagIntent[]
        └─ Warnings[]
```

## 2. 类型约定

以下是语义契约，最终 MoonBit 字段名以实现包的 `pkg.generated.mbti` 为准。公共类型属于 `@moonset/model` 或 facade 包，不放在 `internal/*` 中。

### `ReleaseUnit`（替代原草案的 `Module`）

- `id`：`ecosystem:nativeName`，在 release domain 内唯一。
- `ecosystem`、`nativeName`、`workspaceId`：区分 MoonBit 模块、npm 包及未来 Cargo crate。
- `root`、`manifests`、`versionSource`：路径、相关清单和唯一版本权威字段；同目录可有多个生态单元。
- `version`：当前版本或无版本的工具单元；后者须显式初始化后才能进入版本发布计划。
- `releasePolicy`、`publishTargets`、`visibility`：版本、标签、发布与访问级别独立；不统一为一个 private 布尔值。npm `private: true` 的禁令不能被策略覆盖。
- `dependencies`：带依赖种类、原始协议、原始范围及清单字段位置的边；解释由 ecosystem adapter 提供。

不变量：同生态重名或字段所有权冲突为错误；同目录跨生态不自动合并；生成清单绑定源单元，不重复发现。纯 MoonBit 模式下，`moon.mod` 对应一个单元，`moon.pkg` 不单独版本化。

### `EcosystemWorkspace` 与 ownership

记录 `id`、生态、原生根、manager 及版本、成员 UnitId 和锁文件。多个 workspace 由同一 release domain 管理；`VersionOwnership` 指向唯一字段写入者，`LockfileOwnership` 指向唯一 manager。完整规则见 [混合 workspace 设计](mixed-workspaces.md)。

### `DependencyEdge` / `BuildBridge`

包依赖用于原生范围和依赖者计算。BuildBridge 记录 consumer、producer、最低 bump 和 `waitFor(build|publish)`，默认不产生清单依赖编辑。fixed/linked 是独立版本约束，不隐含构建关系。

### `WorkspaceSnapshot`

包含各生态 workspace、发布单元、依赖边、bridge、ownership、domain 根、Git 状态、工具链版本和配置摘要。快照是规划器的完整输入之一；不得在规划过程中重新读取文件。

### `Changeset`

- `id`：相对 `.changeset` 的唯一 Markdown 文件名，不含 `.md`。
- `releases`：`{ unitId, type }[]`，type 为 `major|minor|patch|none`；单生态原始名字在解析时规范化，混合模式强制生态前缀。
- `summary`：去除 front matter 后的 Markdown。
- `sourcePath`、`sourceLine`：诊断和 changelog 链接。
- `commit`：可选，引入该文件的 Git commit。

### `PreState`

```text
mode: active | exit
 tag: String
 initialVersions: Map[UnitId, Version]
 nextNumbers: Map[UnitId, Int32]
 consumed: Set[ChangesetId]
```

`exit` 状态用于让最后一次预发布转换回稳定版；读取不到状态文件等同于稳定模式，而损坏状态是配置错误。

### `Release`

- `unitId`、`oldVersion`、`newVersion`。
- `level`：合并后的最高级别。
- `reasons`：changeset ID、fixed/linked、依赖更新等有序原因。
- `changesets`：直接贡献的 changeset ID。
- `publish`、`tag`：最终策略判断。

### `ReleasePlan`

包含 schemaVersion、workspace fingerprint、输入 changeset fingerprint、release、文件编辑、changelog、tag intents、warnings 和生成时间（由 Clock 注入）。混合计划还包括原生 adapter 版本、锁文件操作、构建/发布图和期望 artifact；`version` 完成后持久化 intent，供消费 changeset 后的 CI 使用。

不变量：

- 没有 `Release` 时 `FileEdit`、`ChangelogEntry` 和 `TagIntent` 为空。
- 每个写入目标最多一个最终编辑，编辑顺序稳定。
- `newVersion` 大于 `oldVersion`，除非 `type=none`。
- plan fingerprint 覆盖所有决定结果的输入；执行前必须再次匹配。

### `FileEdit`

`path`、`kind(manifest|dependency|lockfile|changelog|changeset|state)`、`owner`、`beforeHash`、`afterText`、`atomic`。执行器先验证 `beforeHash`，防止用户在 plan 后修改文件。多个字段编辑必须合并成唯一文件编辑；同字段多所有者报错。`atomic` 仅指单文件替换，多文件由 journal 管理。

### `PublishResult`

每个 `(planId, unitId, version, target)` 一个结果：`published|skipped|already-published|failed|blocked`，包含 registry、artifact 摘要、attempts、externalId 和可恢复错误。token、完整命令行和 HTTP header 永不进入该类型；`blocked` 用于上游节点失败导致无法开始的目标。

### `ArtifactIntent` / `PackResult`

Intent 在规划时声明 UnitId、版本、目标平台、生成器及所需输入；PackResult 在构建后补充 release commit、文件位置和内容摘要。源清单、生成清单、平台包与产品安装包显式关联，不能把构建输出当新源码成员扫描。

## 3. 版本与依赖规则

1. 同一包多个 changeset 取最高级别：major > minor > patch > none。
2. fixed 组先统一最高目标版本，再传播依赖更新。
3. linked 组只在组内已有 release 时统一版本；没有 release 的成员保持原版本。
4. 内部依赖只有在新范围越界或配置要求时才提升依赖者。
5. ignored 包不能被隐式带入非 ignored release；冲突必须阻止计划。
6. pre 模式将稳定版本增量和预发布序号分开计算，序号按包持久化。
7. 跨生态默认独立版本；bridge 取 consumer 的最低 bump，fixed/linked 显式声明同版本约束。原生依赖范围由 adapter 判断，构建/发布图单独检测环。
