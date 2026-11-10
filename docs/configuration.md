# 配置规范

配置文件默认位于 release domain 根的 `.changeset/config.json`，除非使用 `--config`。单生态时 domain 通常等于 workspace 根；混合时可包含多个 workspace。配置 schema 版本为 `1`；未知顶层字段默认报错，实验字段位于 `experimental` 对象。本地 JSON Schema 草案见 [schema/config-v1.json](schema/config-v1.json)；下方远端 `$schema` 地址仅为预留标识，尚未验证托管可用性。

## 1. 合并优先级

```text
defaults < .changeset/config.json < MOONSET_*（仅非机密运行选项） < CLI
```

环境变量只用于 CI 的运行开关和凭据引用，例如 `MOONSET_NON_INTERACTIVE=1`、`MOONSET_REGISTRY_TOKEN_ENV=NPM_TOKEN`；配置文件和日志永远不包含 token 本身。

## 2. 默认配置

```json
{
  "$schema": "https://moonset.dev/schema/config-v1.json",
  "schemaVersion": 1,
  "changelog": { "generator": "builtin", "file": "CHANGELOG.md" },
  "commit": { "mode": "never", "addMessage": "chore: add changeset", "versionMessage": "chore: release" },
  "baseBranch": "main",
  "access": "public",
  "updateInternalDependencies": "out-of-range",
  "changedFilePatterns": ["**"],
  "fixed": [],
  "linked": [],
  "ignore": [],
  "privatePackages": { "version": false, "tag": false, "publish": false },
  "pre": { "file": ".changeset/pre.json", "directory": ".changeset/pre" },
  "snapshot": { "enabled": false, "useCalculatedVersion": false, "prereleaseTemplate": "{tag}-{datetime}" },
  "tag": { "create": true, "afterPublish": true, "format": "auto", "push": false },
  "publisher": { "kind": "moon", "registry": "default", "dryRunFirst": true },
  "format": "auto",
  "github": { "links": true, "thanks": true }
}
```

## 3. 字段说明

| 字段 | 类型 | 说明 |
|---|---|---|
| `changelog` | object/false | `generator` 为 `builtin`、`git`、`github` 或自定义 API 名；`options` 传给生成器。 |
| `commit` | object/false | `mode` 为 `never`、`add`、`version`、`both`；默认不自动提交。 |
| `baseBranch` | string | `status --since` 和 Action 默认比较分支。 |
| `access` | `public/restricted` | 传给 publisher 的可见性请求；最终由 registry 权限决定。 |
| `updateInternalDependencies` | `never/patch/minor/out-of-range` | 依赖者何时更新版本范围。 |
| `fixed` | string[][] | 每组包共享同一目标版本。支持精确名字，glob 在 v1.1 冻结。 |
| `linked` | string[][] | 一组包共享版本线，但没有变更时不强制发布。 |
| `ignore` | string[] | 暂时跳过的包；若与非 ignore 包存在必须联动的依赖，规划失败。 |
| `privatePackages` | object | 分别控制 version、tag、publish，默认全关；不能绕过 npm `private: true` 等原生发布禁令。MoonBit 的 restricted visibility 不等于 npm private。 |
| `pre` | object | 预发布状态文件和 changeset 隔离目录。 |
| `snapshot` | object | 快照版本是否启用、基准版本和预发布模板。 |
| `tag` | object | 标签创建时机、模板策略和推送开关。 |
| `publisher` | object | `moon`、`command` 或 API publisher；自定义命令走参数化 JSONL 协议。 |
| `changedFilePatterns` | string[] | `status --since` 认定包发生变化的 glob。 |
| `format` | string/false | `auto` 或已支持 formatter；false 表示不自动格式化。 |
| `github` | object | changelog 链接和感谢语开关；App 行为另见 automation。 |
| `experimental.mixedWorkspaces` | object | 混合 domain 的 workspace、UnitId 覆盖、bridge 和锁文件策略；Proposed，见下节。 |

## 4. 示例

```json
{
  "schemaVersion": 1,
  "baseBranch": "main",
  "access": "public",
  "fixed": [["unmbt/core", "unmbt/cli"]],
  "linked": [["unmbt/plugins/*"]],
  "updateInternalDependencies": "patch",
  "privatePackages": { "version": true, "tag": false, "publish": false },
  "changelog": {
    "generator": "github",
    "options": { "repo": "unmbt/moonset", "disableThanks": false }
  },
  "tag": { "create": true, "afterPublish": true, "format": "{name}@{version}", "push": false },
  "snapshot": { "enabled": true, "useCalculatedVersion": true, "prereleaseTemplate": "{tag}-{datetime}" },
  "publisher": { "kind": "moon", "registry": "default", "dryRunFirst": true }
}
```

## 5. 设计约束

- 默认值必须在 `Config::default` 中集中定义，不能散落到命令实现。
- CLI flag 覆盖配置，但不能把安全检查静默关闭；如 `--allow-uncommitted` 必须出现在 plan 和日志中。
- `fixed`、`linked`、`ignore` 的 glob 展开在 workspace 快照上完成，输出中记录实际匹配包。
- `changelog` 和 `publisher` 的自定义名称只能引用注册的 MoonBit API 或显式允许的外部命令。
- 配置错误在任何写操作前报告；错误消息包含 JSON path，例如 `$.tag.format`。

## 6. 混合 workspace（实验草案）

详见 [混合 workspace 设计](mixed-workspaces.md) 和 [完整配置示例](examples/mixed-workspaces.json)。该扩展已加入本地 JSON Schema，以便验证文档形状；通过 schema 不代表 CLI 已实现该能力。

| 子字段 | 契约 |
|---|---|
| `mode` | `coexist` 分区共存，或 `unified` 统一管理；不自动接管已有 Changesets 的目录。 |
| `workspaces` | 显式 `{id, ecosystem, root, manager, includeRoot}`；路径相对 domain。npm/pnpm 共用 `npm` 生态。 |
| `units` | 已发现 UnitId 的 `publish`、`publisher`、`tagFormat` 覆盖；不得用未知 ID 隐式创建源码单元。 |
| `bridges` | `{consumer, producer, kind: "build", bump, waitFor}`；构建依赖，默认不改原生依赖声明。 |
| `lockfiles` | `refresh`（缺省）在 staging 刷新并审阅；`verify-only` 在预期锁文件需变化时失败。 |

混合模式 `fixed`、`linked`、`ignore` 使用完整 UnitId。未覆盖的 publisher 按生态选择：MoonBit → moon，npm → npm；全局 moon publisher 不作用于 JS。全局显式指定 incompatible publisher 则报错。`tagFormat` 的生态模板用于避免同名跨生态 Git tag 冲突；不能直接使用包含冒号的 UnitId。

schema 可校验结构和 manager/生态配对；重复 workspace ID、路径越界、字段所有权、不存在的 UnitId、依赖环和 publisher 能力需要语义校验。`cargo` 在 schema 中保留，但在 Cargo adapter 发布前必须返回 unsupported capability。


