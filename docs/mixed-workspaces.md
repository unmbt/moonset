# 混合生态 workspace 设计

> 状态：Proposed，2026-11-10。这是对第一版 MoonBit 单生态假设的修订，尚未实现。涉及 FR-018 至 FR-024、ADR-006。本文的配置位于 `experimental.mixedWorkspaces`；实现稳定后再冻结公共配置和 API。

## 1. 要解决的问题

一个 Git 仓库可以同时包含 MoonBit workspace、npm/pnpm workspace，以及将来接入的 Cargo workspace。它们的目录、版本、依赖和发布目标不一定一一对应。

本地已有例子：`napi-mbt/moon.mod` 是 `unmbt/napi-mbt@0.3.7`，同目录的 `package.json` 是 `napi-mbt@0.2.1` 且 `private: true`。这是本次检查时的文件内容，不表示两者应该同步。`test-napi-mbt` 也在同目录保存两类清单。MoonBit 的一个 `moon.pkg` 是编译单元，不自动成为独立发布单元。

因此，moonset 需要把“仓库”“生态 workspace”“发布单元”“构建产物”分别建模。仅增加一个 npm publisher 不能解决混合仓库：还必须发现 JS 成员、编辑 JSON 清单、理解依赖协议、处理锁文件和构建产物。

## 2. 两种管理方式

| 方式 | moonset 的职责 | 适用场景 |
|---|---|---|
| 分区共存 | 只管理明确划归自己的发布单元；JS 使用 Changesets，Rust 使用自己的工具；各自拥有 changeset 目录和版本文件 | 渐进采用、各部分独立发布 |
| 统一管理 | 一个 release domain、一份 changeset 记录、一份跨生态计划；各 adapter 负责自己生态的发现、编辑、打包和发布 | MoonBit + JS SDK、原生绑定、多目标发行 |

release domain 是一个配置控制的发布边界，默认与单仓库一致，但不等同于任一生态的 workspace。分区可以独立变更；同一版本字段、changeset 文件、锁文件不得被两个管理者同时写入。

分区共存时，每个分区使用独立的 `.changeset` 目录和配置；根目录 Changesets 的 `.changeset` 不交给 moonset 消费。可在 CI 组合独立计划，但跨分区联动只能提示或导出协调信息，不能自动修改另一个管理者的版本。`--config` 显式指定配置时，以该配置所属 `.changeset` 的父目录作为 release domain 根。

统一管理使用 moonset 的 `.changeset/config.json`。保留 Markdown front matter 的形状，但这不是与 Node Changesets 的配置/运行时完全兼容声明；两种工具不得同时消费该目录。

## 3. 发布单元身份与版本权威

每个 `ReleaseUnit` 至少包含：

- `id`：`<ecosystem>:<nativeName>`，例如 `moonbit:acme/engine`、`npm:@acme/engine`、`cargo:engine-core`。
- `ecosystem`：`moonbit`、`npm`，将来扩展 `cargo`；pnpm 是 npm 生态的包管理器，不是另一种发布单元。
- `workspaceId`、`root`、`manifests`：成员归属、源目录和清单；一个目录允许存在多个生态的单元。
- `versionSource`：版本字段及其所有者。继承版本、生成清单和同步镜像必须指向唯一权威字段。
- `releasePolicy`：是否 version/tag；`publishTargets` 单独描述是否发布、registry、访问级别和发布目录。

一个 release domain 内 UnitId 唯一；同生态同名的两个源码单元不能靠目录顺序消歧，必须调整成员范围或拆成独立 domain。同一个单元可以发布到多个 registry，无需制造两个版本身份；远程去重键为 `(UnitId, version, targetRegistry)`。

混合模式下，changeset、fixed/linked、ignore 和 `--package/--only` 使用完整 ID：

```markdown
---
"moonbit:acme/engine": minor
"npm:@acme/engine": patch
---

新增引擎能力，并修正 JS 包装层。
```

单生态模式可继续接受原始名称，加载时规范化为 UnitId；混合模式不自动猜测省略前缀的名称。迁移旧 changeset 时输出显式映射供审阅。身份不决定相同版本：不同生态默认独立计算。

## 4. 发现与边界

1. 优先使用显式 `--config`；否则向上寻找属于 moonset 的配置，在 Git 仓库边界停止。`moon.work` 和 npm workspace 清单用于成员发现，不抢先截断 release domain。找到另一工具的配置时诊断并要求选择分区，不把它静默迁移为 moonset 配置。
2. 单生态兼容模式保留原有发现行为。混合模式必须显式列出各 workspace 的根、生态、包管理器和是否包含根成员；存在 `package.json` 只证明它存在，不授权接管。
3. MoonBit adapter 解析成员声明；JS adapter 分别遵循 npm `workspaces` 和 `pnpm-workspace.yaml` 的成员语义。配置与 `packageManager` 声明或锁文件矛盾时报告错误，不能因 PATH 上先找到某个工具就选择它。
4. workspace 可以嵌套、同级，或两类清单位于同一目录。多个配置项解析到同一 canonical manifest 时去重；同生态两个 workspace 都声明拥有它则报 `ambiguous_owner`。忽略符号链接别名，并拒绝越出 domain 的成员。
5. 默认不遍历 `node_modules`、`.mooncakes`、`_build`、`target`、构建输出和嵌套 Git checkout；显式成员也需要边界校验。根 workspace 的工具清单、示例和测试项目不是默认发布目标。
6. 文件变更通过 adapter 的输入集合归属，可归属多个单元。共享 native 源码、绑定定义、构建配置需显式 input mapping；无法归属的相关共享文件必须报告，不静默当作无变更。

本次源码 checkout `moonset/changesets/` 就是必须排除的嵌套仓库实例，不能作为 moonset 自身的待发布 npm workspace。

## 5. 三类关系分别计算

| 关系 | 作用 | 如何声明 |
|---|---|---|
| 包依赖 | 校验版本范围、修改依赖声明、必要时提升依赖者 | adapter 从原生清单读取；保留原始依赖种类与协议 |
| 构建/交付依赖 | 原生库变化需要重建 JS `.node`/Wasm 包；确定产物准备顺序 | 显式 bridge，注明 consumer、producer、传播级别、等待 build 或 publish |
| 版本组 | 需要统一发行编号的产品 | `fixed` 或 `linked`，使用 UnitId |

例如 MoonBit `acme/engine` 的 minor 变更，可以让 `@acme/engine` 包装层 patch 发布；JS 公共 API 若也有破坏性变更，作者另加 major changeset。跨语言关系没有通用的 bump 对应表，bridge 的 `bump` 是最低级别，不能降低作者声明的级别。

- build bridge 默认不写 consumer 的依赖清单：npm 不能通过普通 `dependencies` 安装 Mooncakes 模块。
- `waitFor: build` 表示只需要 producer 的产物，不要求先发 Mooncakes；`waitFor: publish` 表示确实依赖远端可下载的版本。
- `fixed` 才会让所有成员进入计划并取同一目标版本；`linked` 只统一已需要发布的成员。跨生态组必须先检查 adapter 对目标版本的支持。
- 版本传播计算到固定点：所有目标版本都以本次快照的原始版本为基准，合并最高 bump；不能每经过一条 bridge 就再次递增一次 patch。构建/发布执行图单独拓扑排序。若存在无法满足的执行环，写入前报告完整环，不按名字顺序碰运气。
- `--only` 只能选完整的所需闭包：缺少 bridge 或 fixed 组成员则报错并列出必须追加的 ID，不能悄悄跳过约束。

## 6. npm/pnpm 与 MoonBit 的语义边界

### 依赖与锁文件

JS adapter 保留 `dependencies`、`devDependencies`、`optionalDependencies`、`peerDependencies` 的区别；dev-only 变更不等价于公开运行时依赖变化。peer 范围扩展和破坏性收窄要有独立测试与策略。

`workspace:*`、`workspace:^`、`workspace:~`、显式范围、别名、`file:`/`link:` 等由对应包管理器 profile 解释。不支持的协议报 capability error；不能把 `workspace:` 字符串交给通用 SemVer 重写器，也不能把 npm 范围语义套给 MoonBit import。

每个 lockfile 有唯一 manager。版本修改在隔离 staging 中完成后，由固定版本包管理器刷新锁文件，再校验允许的 diff 和依赖变化。不能只改 `package.json` 而留下一份过期锁文件；用户采用 `verify-only` 时，有差异就失败。解析阶段不触发 install 或生命周期脚本。锁文件需要网络才能解析时单独报告，不能把离线 plan 成功宣称为可直接执行。

### private 与 visibility

`version`、`publish`、`visibility` 是三件事。npm `private: true` 是禁止 npm 发布，即使配置 `privatePackages.publish=true` 也不能绕过；内部工具包仍可选择更新版本。MoonBit 当前 `moon publish --help` 把 `moon.mod private=true` 描述为请求 restricted access，不能翻译为 npm 的发布禁令。adapter 必须保留原始语义；不能通过“统一 private 布尔值”做跨生态判断。

### 发布目录、产物与渠道

源清单和 `dist/package.json` 由 source/generator 关系连接，生成清单不能被误发现成第二个源码单元。`PackResult` 记录 UnitId、版本、commit、目标平台、内容摘要和来源，不只是一条文件路径。

原生绑定常包含一个 JS 主包和若干平台包。生成包必须由 artifact provider 在规划阶段声明稳定 ID/名称和目标版本，再由构建填充内容；主包等全部必需平台产物准备、验证、发布完成后才能发布，不能在 CI 中临时发现未知包并直接推送。

npm dist-tag（如 `next`）和 Git tag 是不同概念。pre/snapshot 的版本格式和 channel 能力按 publisher 检查；Mooncakes 或其他目标不支持某渠道时必须显式失败或由用户选择适配策略，不能假装所有 registry 都支持 npm `--tag`。

## 7. 配置草案

下面的片段将 `native/moon.work` 和根 pnpm workspace 放入同一 domain。`units` 的覆盖项只适用于已发现的单元，未知 ID 是错误；`publish` 缺省为 true，但仍受 manifest 的禁止规则和 publisher 能力约束。示例中的配置键是设计，不是可运行的 CLI。

可单独校验的文件见 [examples/mixed-workspaces.json](examples/mixed-workspaces.json)。

```json
{
  "schemaVersion": 1,
  "experimental": {
    "mixedWorkspaces": {
      "mode": "unified",
      "workspaces": [
        { "id": "native", "ecosystem": "moonbit", "root": "native", "manager": "moon", "includeRoot": false },
        { "id": "js", "ecosystem": "npm", "root": ".", "manager": "pnpm", "includeRoot": false }
      ],
      "units": {
        "moonbit:acme/engine": { "publish": false },
        "npm:@acme/engine": { "publisher": "npm", "tagFormat": "npm/{name}@{version}" }
      },
      "bridges": [
        {
          "consumer": "npm:@acme/engine",
          "producer": "moonbit:acme/engine",
          "kind": "build",
          "bump": "patch",
          "waitFor": "build"
        }
      ],
      "lockfiles": "refresh"
    }
  }
}
```

源库本身不发 Mooncakes，仅作为 JS 包的构建输入；若两端都要发布，修改 publish policy 即可，版本默认仍独立。需要严格同步时，在顶层显式加 `fixed: [["moonbit:acme/engine", "npm:@acme/engine"]]`。

`publisher` 注册名与包管理器不同：JS workspace 可由 pnpm 解析和打包，npm adapter 负责 npm registry 发布。配置不提供令牌正文。混合模式禁止把全局 `publisher.kind=moon` 作为 npm 单元的 fallback；缺少 adapter 必须在 plan/apply 前报错。`tagFormat` 支持 `{ecosystem}`、`{name}`、`{version}`；完整 UnitId 含 `:`，不得原样用作 Git ref。

分区共存使用 `mode: "coexist"`，只声明归 moonset 管理的 workspace。自动扫描到的其他生态仅显示为 unmanaged。两种 mode 都显式配置成员，不意味着 coexist 可以跳过所有权检查。

## 8. 统一发布流程与部分失败

```text
发现各生态 workspace → 规范化 UnitId / ownership / dependency graph
  → 统一版本计划 → staging 清单和锁文件校验 → release PR
  → release commit 的多平台 build / pack → 验证全部产物
  → 按发布图分发到各 registry → 汇总结果 → tags / 产品 release
```

文件事务和远端事务分开。多文件写入使用 journal 和恢复机制，不能把每个文件的原子 rename 宣称为整个仓库原子提交。npm、Mooncakes、GitHub Release 之间没有共同事务：一个成功、另一个失败时保留成功事实，只重试缺失节点，不自动 unpublish 或回滚已发布版本。

执行结果键包括 `(planId, UnitId, version, target)`。重试先核对远端版本/可用摘要，已有版本内容矛盾或无法确认一致性时阻止覆盖。持久化 version 后的 intent 和 artifact 清单；不能在 changeset 已消费后重新扫描空目录来猜发布对象。发布完成后才创建产品级 tag；独立单元 tag 如允许提前创建，也必须有对应成功凭据。

## 9. JS + Rust（napi-rs / Tauri 类型）

这里使用它们说明仓库形态，不声称已验证或兼容这些框架当前版本的配置 API。

- **原生绑定**：Cargo crate 提供构建输入，npm 主包和平台包负责分发；crate 可设置不发布。bridge 表示构建与再发布的关系，构建任务由 napi-rs 等已有工具承担。
- **桌面应用**：前端 npm 包可能是 private 开发项目，Cargo crate 可能不发 crates.io；用户真正发布的是安装包和 GitHub Release。它们可以构成一个产品版本组，但无须强迫两个源码包都上传 registry。
- **Cargo 适配的后续条件**：解析 workspace 成员、继承版本、path/workspace 依赖和 `Cargo.lock`；对 Tauri 应用配置版本字段定义唯一版本权威及同步映射。未知配置文件不能靠全局字符串替换改版本。

Cargo/Tauri adapter 在后续阶段评估；第一版核心必须能表示这些关系，但不能将“可扩展”写成“已经支持 Rust 发布”。

## 10. 交付顺序与验收

1. **Phase 1**：UnitId、ownership、typed edge、共存边界进入核心；同目录双清单和被忽略嵌套仓库成为 fixture。
2. **Phase 3**：MoonBit + npm/pnpm 联合规划、JS 清单和锁文件 staging、changeset 迁移契约；该阶段即使只支持 dry-run 也必须清楚报告 capability。
3. **Phase 4**：真实 npm 发布、原生平台包、跨 registry 恢复、Action 按 target 隔离凭据。
4. **Phase 5+**：Cargo、应用产物与框架版本同步 adapter；每种 adapter 通过 conformance 测试才声明支持。

具体验收编号和失败场景见 [测试策略](test-strategy.md)。配置、版本计划和 adapter 接口尚未发布，所以现在调整核心比以后把 `Module` 强行扩展成 npm package 成本更低。
