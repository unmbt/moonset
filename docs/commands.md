# CLI 命令契约

Phase 2 提供 `init`、`add`、`pre enter|exit|status`，并保留 `status`、`publish-plan`、`--help`、`--version`。

命令先解析配置所属 release domain，再发现其中的生态 workspace；可用全局 `--cwd` 定位，`--config` 显式选择分区。默认输出面向人类，`--output json` 或命令专属 `--json` 输出版本化 JSON。所有命令支持 `--help`、`--version`、`--quiet`，写操作支持 `--dry-run`（如果有意义）。混合模式契约见 [混合 workspace 设计](mixed-workspaces.md)，目前尚未实现。

## 命令总览

| 命令 | 作用 | 默认是否写盘 | 网络 |
|---|---|---:|---:|
| `init` | 初始化 `.changeset` | 是 | 否 |
| `add` | 创建 changeset | 是 | 否 |
| `status` | 查看变化和预计发布 | 否 | 否 |
| `publish-plan` | 输出完整 release plan | 否 | 否 |
| `version` | 应用版本和 changelog | 是 | 否 |
| `pre` | 进入或退出预发布模式 | 是 | 否 |
| `pack` | 通过所选生态 adapter 生成包归档 | 可选 | adapter 决定并预先报告 |
| `publish` | 发布已版本化模块 | 可选 | 是 |
| `tag` | 创建当前版本 Git 标签 | 可选 | 否/可选推送 |
| `doctor` | 只读诊断本机和 workspace | 否 | 可选 registry dry-run |

`git-tag` 作为兼容别名解析到 `tag`；`moonset` 不带子命令时等同于交互式 `add`，但在 CI 中必须报错并要求显式子命令。

## `init`

```text
moonset init [--force] [--config path] [--format json]
```

创建：

- `.changeset/config.json`：只在不存在时写入默认配置。
- `.changeset/README.md`：解释 front matter 和提交流程。
- `.changeset/.gitignore`：只忽略运行时状态，如 `pre.json` 由配置决定。

默认拒绝覆盖已有配置；`--force` 只允许补缺文件，不覆盖已有文件。输出创建、跳过和冲突列表。

## `add`

```text
moonset add [--package name ...] [--type major|minor|patch|none]
  [--summary text] [--empty] [--id id] [--no-format]
```

交互式模式让用户选择包、版本级别和 Markdown 摘要。非交互式模式要求同时提供 `--package`、`--type` 和 `--summary`，或显式 `--empty`。一个文件可以包含多个包的 release。

文件格式：

```markdown
---
"unmbt/example/core": minor
"unmbt/example/cli": patch
---

改动摘要，说明用户可见行为和迁移方式。
```

成功输出 changeset ID 和绝对路径。写入前检查 ID、包名和版本类型；不会自动提交 Git。

混合模式 `--package` 及 front matter 键必须使用 UnitId（例如 `npm:@acme/engine`）；选择一个单元不代表自动选择同目录的其他清单。交互模式同时显示生态、版本和发布策略。

## `status`

```text
moonset status [--since ref] [--verbose] [--output human|json]
```

输出 workspace、待处理 changeset、预计 release 和诊断。不带 `--since` 时读取工作目录的全部待处理 changeset，无需 Git 仓库或干净工作区。`--since ref` 比较 `merge-base(ref, HEAD)..HEAD`，只读取 HEAD 已提交快照，以及范围内新增、修改或重命名后仍存在的 changeset；未提交内容明确警告并排除。不自动 fetch，也不默认比较 baseBranch。

JSON 顶层固定：`schemaVersion`、`workspace`、`changesets`、`releases`、`warnings`、`errors`、`hasChanges`、`hasRelease`。字段新增只能向后兼容。

混合结果包含各生态 workspace、UnitId、unmanaged 项、bridge 传播原因、字段所有权和 adapter capability。未实现的 JS/Cargo adapter 不得默默跳过被配置的目标。

退出码：范围内存在相关文件变化但没有任何 changeset 时为 `1`；空 changeset 可明确放行，且不逐模块强制覆盖。正常为 `0`，解析或配置错误为 `2`，I/O/Git 错误为 `3`。JSON 模式 stdout 只包含 JSON，stderr 用于诊断。

## `publish-plan`

```text
moonset publish-plan [--since ref] [--output path|-] [--pretty]
```

只构建并序列化 release plan，不读注册表、不创建 Git 引用。省略输出或 `--output -` 写 stdout；指定文件才写盘，校验成功后在同目录创建独占临时文件并原子替换。输入文件、清单和 changeset/Git 目录禁止覆盖。

Phase 1 输出固定 `schemaVersion: 1`、`stage: "analysis"`、`executable: false`，包含发布、依赖声明更新和预发布下一状态意图。没有可执行文件补丁、Changelog 或 artifact；不能把这个 JSON 交给发布器直接执行。此命令不执行 status 的缺少 changeset 策略检查。

已存在的输出文件必须是 moonset v1 analysis JSON，才允许替换；其他已有文件不会覆盖。相对输出路径以 `--cwd` 为基准。

## `version`

```text
moonset version [--snapshot tag] [--since ref] [--dry-run]
  [--empty] [--no-changelog] [--no-commit]
```

流程：解析配置和 workspace → 读取并验证所有 changeset → 构建 plan → 展示差异 →（可选确认）写 manifest、依赖范围和 changelog → 移动/删除已消费 changeset → 写 release state。

混合模式在写盘前对所有清单和锁文件进行 staging 校验，按字段所有权合并 diff。同一次 version 可更新多个生态，但不会顺便运行另一个工具的 `changeset version`。持久化包含 UnitId 和发布图的 intent，避免消费 changeset 后丢失发布对象。

- 任何解析、规划或确认失败都不写盘。
- 默认不创建 Git commit；若配置开启 commit，只能通过 Git adapter 使用参数数组执行。
- `--dry-run` 只输出 plan 和文件 diff 摘要。
- `--snapshot` 需要配置允许快照版本；快照不消费稳定 changeset，除非规格另行指定。

## `pre`

```text
moonset pre enter <tag> [--initial-version]
moonset pre exit
moonset pre status
```

状态文件默认为 `.changeset/pre.json`，记录 `mode`、`tag`、已发布预版本计数和进入时版本。进入 active pre 模式时拒绝第二次 `enter`；`exit` 后允许下一次稳定版本；`status` 不改盘。

## `pack`

```text
moonset pack [--package name ...] [--frozen] [--dry-run]
```

对需要发布的单元调用相应 pack adapter。MoonBit 使用 `moon package`；JS 使用选定且固定版本的 npm/pnpm profile。捕获来源 commit、UnitId、版本、平台、归档路径和校验值；生成的 `dist/package.json` 与源码清单保持绑定。生命周期脚本由明确的打包阶段执行，查询命令不执行它们。

## `publish`

```text
moonset publish [--dry-run] [--registry name] [--tag dist-tag]
  [--only name ...] [--yes] [--no-tag] [--retry count]
```

发布前重新读取 workspace 和版本，校验存在 release commit 或显式 `--allow-uncommitted`。单生态默认 publisher 是 `moon publish`：先对全部目标执行 `--dry-run`，确认成功后才执行真实发布。混合模式按 UnitId/target 选择 publisher，并验证全部必需产物；不把 JS 单元传给 moon。真实发布不自动运行 `version`。

混合模式 `--only` 使用完整 UnitId，缺少 fixed/bridge 闭包成员时失败。`--registry`、`--tag` 只有在所有选中目标均支持且含义一致时才允许覆盖，否则要求按 target 配置；npm dist-tag 不映射为 Git tag。

默认在所有目标成功后交给 `tag` adapter 创建标签；`--no-tag` 或 `config.tag.afterPublish=false` 可关闭。部分成功返回 `3`，JSON 结果列出每个包的 published/skipped/failed 状态。

## `doctor`

```text
moonset doctor [--fix] [--registry] [--output human|json]
```

检查 MoonBit 工具链版本、Git 可用性和工作树、workspace/manifest 解析、`.changeset` 配置、publisher 登录状态（默认只做 dry-run）以及 Action 所需环境变量。默认只读；`--fix` 仅执行明确且可逆的初始化修复，并逐项确认。

## `tag`

```text
moonset tag [--dry-run] [--push] [--force] [--format template]
```

为当前版本化单元创建 Git tag。默认：单生态单模块为 `v{version}`，单生态 workspace 为 `{name}@{version}`；混合模式为 `{ecosystem}/{name}@{version}`，每个 intent 先用 Git ref 规则验证并检测重名。混合模板支持 `{ecosystem}`、`{name}`、`{version}`；不把含 `:` 的 UnitId 直接写进 tag。存在同名且指向不同 commit 的标签时失败；`--force` 必须在交互式确认后使用。

产品级汇总标签要求全部必需 publish target 成功；不能用一次 `tag` 把部分发布伪装成整体成功。

`--push` 只推送本次新建的标签；默认不推送。

## 全局选项与错误

- `--cwd path`：workspace 解析和相对路径基准。
- `--config path`：替代 `.changeset/config.json`；显式路径不存在是错误。
- `--no-color`、`--quiet`：只影响人类输出。
- `--yes`：跳过确认；CI 中必须显式提供。
- `--json` 是 `--output json` 的别名。

错误输出包含稳定 `code`、短消息、建议和可选 `path`/`line`/`column`。脚本不应依赖 message 文本。



# Phase 2 workflow

`moonset init` creates `.changeset/config.json`, `README.md`, and `.gitignore`
without overwriting existing files. `moonset add --package moonbit:org/name
--type patch --summary "..."` writes a stable Markdown changeset; pass
`--json` for machine readable output. `moonset pre enter|exit|status` manages
the Moonset `active`/`exit` pre-release state.

