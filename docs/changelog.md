# Changelog 规范

## 1. 文件与标题

默认每个可发布模块在自身目录维护 `CHANGELOG.md`。新增版本插入文件顶部（保留已有内容和首部说明）：

```markdown
# Changelog

## 1.4.0 - 2026-11-10

### Minor Changes

- [#123](https://github.com/org/repo/pull/123) [`a1b2c3d`](https://github.com/org/repo/commit/a1b2c3d) Thanks [@alice](https://github.com/alice)! - 支持 workspace 发布计划。

### Patch Changes

- 修复依赖范围更新。
- Updated dependencies:
  - unmbt/core@1.4.0
```

日期由注入的 UTC `Clock` 提供。保留已有 `# Changelog` 或 `# <package-name>` 标题及 Keep-a-Changelog 前言段落；若单元存在有效版本升级但无直接 changeset 与依赖更新（例如 `fixed` 组或 `pre exit` 毕业），写入 `- No changes in this release.`，避免空版本标题。

混合模式 changelog 归属 ReleaseUnit。同目录多个单元若写同一 `CHANGELOG.md`，必须选择显式聚合生成器（分节标注 UnitId 与各自版本）或不同文件路径；不能由两个 adapter 各自 prepend。bridge 引起的重建发布注明 producer 和原因，不能伪装成 npm 清单依赖更新。聚合 changelog 的版本节不强制所有成员共享版本。

## 2. 内置生成器

| 名称 | 数据来源 | 默认行为 |
|---|---|---|
| `builtin` | changeset 摘要和 release 类型 | 无外部网络，按类型分组 |
| `git` | builtin + changeset commit | 添加 commit short hash 和链接 |
| `github` | git + GitHub PR/作者 | 添加 PR、作者感谢和依赖段落；取不到远端信息时降级为 git |

生成器必须是纯的：输入 `ChangelogContext` 和 options，输出 Markdown 行或段落，不读写工作区。

## 3. 自定义生成器契约

编译期 MoonBit API：

```text
pub(open) trait ChangelogGenerator {
  fn name(Self) -> String
  fn render(Self, ChangelogContext) -> String
}
```

`ChangelogContext` 包含 `unit_id`、`version`、`date`、`lines`（含 `changeset_id`/`summary`/`bump`/`old_version`/`new_version`/`commit`/`pull_request`/`authors`）、`dependency_lines`、`existing`、`repository`、`links`、`thanks` 与 `server_url`（支持 `GITHUB_SERVER_URL`）；不得包含 token。实现注册到 `GeneratorRegistry`，配置使用稳定名称。

外部 JSONL 协议（实验）：进程启动后逐行接收 `{schemaVersion,method,payload}`，逐行返回 `{ok,result}`；stderr 只作为诊断；超时、非 JSON 或 schema 不匹配都使 plan 失败。进程不得直接修改 workspace。

## 4. 链接与感谢

GitHub 链接优先使用配置的 `repo`，否则使用 `GITHUB_REPOSITORY`。找不到 PR 时保留摘要，不生成猜测链接。感谢语必须可关闭，且作者名来自 GitHub API 的结构化响应。

## 5. 兼容与校验

- 生成器输出必须是有效 UTF-8 Markdown。
- 新增段落只能追加，不重排历史版本。
- `version --dry-run` 输出最终文本 hash，执行时再次校验，避免生成器结果漂移。
- 自定义生成器版本应写入 plan 的 `generator` 字段，便于复现。
