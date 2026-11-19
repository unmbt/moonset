# CLI 命令契约

Phase 4 提供 `pack`、`publish`、`tag` 以及此前的 changeset、版本和状态命令。

命令先解析配置所属 release domain，再发现其中的生态 workspace；可用全局 `--cwd` 定位，`--config` 显式选择分区。默认输出面向人类，`--output json` 或命令专属 `--json` 输出版本化 JSON。所有命令支持 `-h`/`--help`、`-V`/`--version`、`--quiet`，写操作支持 `--dry-run`（如果有意义）。混合模式契约见 [混合 workspace 设计](mixed-workspaces.md)。

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
| `release-notes` | 从 `CHANGELOG.md` 提取版本发布说明 | 否 | 否 |
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
moonset status [--since ref] [--verbose] [--output human|json|markdown]
  [--head-repo owner/name] [--head-ref branch]
```

输出 workspace、待处理 changeset、预计 release 和诊断。不带 `--since` 时读取工作目录的全部待处理 changeset，无需 Git 仓库或干净工作区。`--since ref` 比较 `merge-base(ref, HEAD)..HEAD`，只读取 HEAD 已提交快照，以及范围内新增、修改或重命名后仍存在的 changeset；未提交内容明确警告并排除。不自动 fetch，也不默认比较 baseBranch。

JSON 顶层固定：`schemaVersion`、`workspace`、`changesets`、`releases`、`warnings`、`errors`、`hasChanges`、`hasRelease`，以及在共存或存在未受管清单时附加可选 `coexistence`。字段新增只能向后兼容。

`--output markdown` 仅向 stdout 输出 PR Bot 评论 Markdown（警告写入 stderr），首行固定包含 `<!-- moonset-bot:changeset-check -->`，覆盖五种状态：`release`（版本变更表与转义后的 changeset 首行摘要）、`missing`（相关改动路径列表、`moonset add` 命令与提供 `--head-repo`/`--head-ref` 时的一键新建链接）、`empty`（空 changeset 放行说明）、`none`（未触及受管包）与 `error`（解析/配置报错）。所有用户文本经 HTML/Markdown 表格转义及 `@` 防提及处理，超长时按最大长度（默认 `60000` 字符）截断并保留头部。

混合结果包含各生态 workspace、UnitId、unmanaged 项、bridge 传播原因、字段所有权和 adapter capability。未实现的 JS/Cargo adapter 不得默默跳过被配置的目标。

退出码：范围内存在相关文件变化但没有任何 changeset 时为 `1`；空 changeset 可明确放行，且不逐模块强制覆盖。正常为 `0`，解析或配置错误为 `2`，I/O/Git 错误为 `3`。JSON 与 Markdown 模式 stdout 只包含对应渲染结果，stderr 用于诊断。出错时（退出码 `2` 或 `3`），Markdown 模式仍向 stdout 输出 `error` 状态评论以便 PR Bot 更新反馈。

## `publish-plan`

```text
moonset publish-plan [--since ref] [--output path|-] [--pretty]
```

只构建并序列化 release plan，不读注册表、不创建 Git 引用。省略输出或 `--output -` 写 stdout；指定文件才写盘，校验成功后在同目录创建独占临时文件并原子替换。输入文件、清单和 changeset/Git 目录禁止覆盖。

Phase 1 输出固定 `schemaVersion: 1`、`stage: "analysis"`、`executable: false`，包含发布、依赖声明更新和预发布下一状态意图；若配置了多平台 `artifacts` 或混合 bridge，还向后兼容地附加只读 `artifacts` 意图列表与 `executionGraph`（分离 `buildNodes`、`publishNodes` 与 `publishOrder`）。没有可执行文件补丁或 Changelog；不能把这个 JSON 交给发布器直接执行。此命令不执行 status 的缺少 changeset 策略检查。

已存在的输出文件必须是 moonset v1 analysis JSON，才允许替换；其他已有文件不会覆盖。相对输出路径以 `--cwd` 为基准。

## `version`

```text
moonset version [--snapshot tag] [--since ref] [--dry-run]
  [--empty] [--no-changelog] [--no-commit] [--output human|json|markdown]
  [--commit-metadata path]
```

流程：解析配置和 workspace → 读取并验证所有 changeset → 构建 plan → 展示差异 →（可选确认）写 manifest、依赖范围和 changelog → 移动/删除已消费 changeset → 写 release state。

混合模式在写盘前对所有清单和锁文件进行 staging 校验，按字段所有权合并 diff。同一次 version 可更新多个生态，但不会顺便运行另一个工具的 `changeset version`。持久化包含 UnitId 和发布图的 intent，避免消费 changeset 后丢失发布对象。

- 任何解析、规划或确认失败都不写盘。
- 默认不创建 Git commit；若配置开启 commit，只能通过 Git adapter 使用参数数组执行。
- `--dry-run` 只输出 plan 和文件 diff 摘要；搭配 `--output markdown` 时只读渲染 Release PR 正文（含引导说明、`pre` 预发布警告横幅、版本汇总表与 `# Releases` 逐包 Changelog 正文，超长按 60000 字符安全截断）。
- `--commit-metadata path` 传入只读 JSON 映射（`{ "<sha>": { "pr": "12", "author": "alice" } }`），供 `git`/`github` changelog 生成器补充关联 PR 与作者信息。
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
moonset pack [--package name ...] [--target name] [--manifest-out path]
  [--verify] [--artifacts-dir dir] [--frozen] [--dry-run] [--json]
```

对需要发布的单元调用相应 pack adapter。MoonBit 使用 `moon package`（`--dry-run` 调用 `moon package --dry-run`）；JS 使用选定且固定版本的 npm/pnpm profile（`--frozen` 附带 `--offline`）；Cargo 使用 `cargo package --allow-dirty`（`--dry-run` 使用 `cargo package --list --allow-dirty`，避免调用不存在的 `cargo package --dry-run`）。捕获来源 commit、UnitId、版本、平台、归档路径和校验值，并在非 dry-run 时记录到 `.moonset/pack-results.json`（指定 `--target` 或 `--manifest-out` 时输出到对应平台结果文件，例如 `.moonset/pack-results-<target>.json`）。传入 `--verify` 时聚合 `--artifacts-dir`（默认 `.moonset`）下的打包清单并与 `.moonset/release-state.json` 中的 `artifacts` 矩阵校验完整性和摘要；生命周期脚本由明确的打包阶段执行，查询命令不执行它们。

## `publish`

```text
moonset publish [--dry-run] [--registry name] [--only unit[,unit...]]
  [--tag dist-tag] [--artifacts-dir dir] [--retry count]
  [--allow-uncommitted] [--no-tag] [--yes] [--json]
```

发布前重新读取 workspace 和版本，校验 `release-state.json` 与当前清单版本一致、若存在 `.moonset/pack-results.json` 则校验其版本/commit/文件有效性，并校验存在 release commit 或显式 `--allow-uncommitted`。支持按 `publisher.kind`（`moon` / `command`）或 `units.<id>.publisher` 路由，并按 `publisher.dryRunFirst` 决定是否在真实发布前先执行全量 preflight `--dry-run`。混合模式按 UnitId/target 选择 publisher，不把 JS/Cargo 单元传给 `moon`。真实发布不自动运行 `version`。

混合模式 `--only` 使用完整 UnitId，缺少 fixed/bridge/runtime 闭包成员时失败（返回退出码 `1`）。`--registry`、`--tag` 只有在所有选中目标均支持且含义一致时才允许覆盖：MoonBit 不支持 `--registry` 与 `--tag`，Cargo 不支持 `--tag`；npm dist-tag 不映射为 Git tag。缺少 `--yes` 确认或工作树脏（未传 `--allow-uncommitted`）时返回退出码 `1`。

默认在所有目标成功后（且工作树干净时）交给 `tag` adapter 创建标签；`--no-tag`、`config.tag.afterPublish=false` 或 `--allow-uncommitted` 下的脏工作树会跳过自动创建标签。部分成功返回 `3`，JSON 结果列出每个包的 published/skipped/failed/blocked/unknown 状态。

## `doctor`

```text
moonset doctor [--fix] [--registry] [--output human|json]
```

检查 MoonBit 工具链版本、Git 可用性和工作树、workspace/manifest 解析、未完成 `version-journal.json`、`.changeset` 配置、publisher 登录/preflight 状态（`--registry` 覆盖 `moon` / `npm` / `cargo`）以及 CI/Action 所需环境变量（只读校验是否存在，不输出凭据正文）。默认只读；`--fix` 执行安全可逆的初始化补缺（创建缺失的 `.changeset/config.json`、`README.md`、`.gitignore` 与 `.moonset/.gitignore`，不覆盖已有文件）。

## `tag`

```text
moonset tag [--dry-run] [--push] [--force] [--format template]
```

为当前版本化单元创建 Git tag。默认：单生态单模块为 `v{version}`，单生态 workspace 为 `{name}@{version}`；混合模式为 `{ecosystem}/{name}@{version}`，每个 intent 先用 Git ref 规则验证并检测重名。混合模板支持 `{ecosystem}`、`{name}`、`{version}`；不把含 `:` 的 UnitId 直接写进 tag。存在同名且指向不同 commit 的标签时失败；`--force` 必须在交互式确认后使用。

产品级汇总标签要求全部必需 publish target 成功；不能用一次 `tag` 把部分发布伪装成整体成功。

`--push` 只推送本次新建的标签；默认不推送。

## `release-notes`

```text
moonset release-notes [--version ver] [--file path] [--package unit] [--from-state] [--json] [--pretty]
```

只读从 `CHANGELOG.md` 提取指定版本的发布说明正文（精确匹配 `## [v]<ver>` 标题，避免将 `0.1.0` 误匹配到 `0.1.0-alpha.1`）：

- 指定 `--version <ver>` 时：从 `--file`（或对应 `--package` 单元目录下的 `config.changelog.file`，默认 `CHANGELOG.md`）提取对应版本章节；文本模式直接输出正文（未找到时输出空串且退出码仍为 `0`），`--json` 输出 `{"schemaVersion":1,"version":"...","changelogPath":"...","found":bool,"prerelease":bool,"body":"..."}`。
- 指定 `--from-state` 时：读取 `.moonset/release-state.json` 中的 `tags` 与对应发布单元的 `CHANGELOG.md`，输出 `{"schemaVersion":1,"notes":[{"tag":"...","unitId":"...","version":"...","changelogPath":"...","found":bool,"prerelease":bool,"body":"..."}]}`（文本模式按顺序输出匹配到的正文）。
- 两个模式均不写盘、不请求网络；若 `--from-state` 时不存在 `.moonset/release-state.json` 或同时冲突传入参数则返回退出码 `2`。

## 全局选项与错误

- `--cwd path`：workspace 解析和相对路径基准。
- `--config path`：替代 `.changeset/config.json`；显式路径不存在是错误。
- `--no-color`、`--quiet`：只影响人类输出。
- `--yes`：跳过确认；CI 中必须显式提供。
- `--json` 是 `--output json` 的别名。
- `-h`、`--help`：打印命令帮助信息。
- `-V`、`--version`：打印与 `moon.mod` 一致的 CLI 版本号。

错误输出包含稳定 `code`、短消息、建议和可选 `path`/`line`/`column`。脚本不应依赖 message 文本。在 `--json` 模式下：`status` 报错保持兼容 `status` 结构（包含 `ok: false` 与 `errors` 数组）；其余命令统一返回简洁错误信封 `{"schemaVersion":1,"ok":false,"command":"<cmd>","errors":[...]}`。退出码遵循 `1`（策略/确认拦截，如 `missing-changeset`、`confirmation-required`、`dirty-working-tree`、`incomplete-selection`）、`2`（配置/changeset/参数/workspace 无效）、`3`（外部工具/Git/网络失败）。



# Phase 2 workflow

`moonset init` creates `.changeset/config.json`, `README.md`, and `.gitignore`
without overwriting existing files. `moonset add --package moonbit:org/name
--type patch --summary "..."` writes a stable Markdown changeset; pass
`--json` for machine readable output. `moonset pre enter|exit|status` manages
the Moonset `active`/`exit` pre-release state.

`pack` and `publish` route through the selected ecosystem adapter. npm and pnpm use their workspace manager, while Cargo stages the root `Cargo.lock`, packages `.crate` archives, and keeps credentials in Cargo's native configuration.
