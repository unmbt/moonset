# 常见问题与排障指南（FAQ）

本文汇总了在使用 `moonset` 本地工作流与 GitHub Actions 自动发版过程中最常遇到的问题、原因解析与排查步骤。

---

## 1. GitHub Actions 自动发版与 PR 权限

### Q1：`version-pr` 报错 `GraphQL: GitHub Actions is not permitted to create or approve pull requests (createPullRequest)`

**原因**：  
GitHub 仓库（或所属 Organization）默认禁止工作流中的 `GITHUB_TOKEN` 创建或批准 Pull Request。

**解决方法**：
1. 打开仓库页面 **`Settings` → `Actions` → `General` → `Workflow permissions`**。
2. 勾选 **`Allow GitHub Actions to create and approve pull requests`** 并点击 **Save**。
3. 如果该复选框呈灰色不可编辑，说明被组织策略锁定，需要前往 **`Organization Settings` → `Actions` → `General` → `Workflow permissions`** 先启用该选项。

---

### Q2：为什么 `GITHUB_TOKEN` 创建并推送了 `v0.1.0` tag，却没有自动触发 `on: push: tags: ['v*']` 的二进制构建工作流？

**原因**：  
这是 GitHub Actions 的防递归机制：使用默认 `GITHUB_TOKEN` 推送分支或打 tag **不会**触发另一个工作流的 `push` 事件。

**解决方式**：  
在发布工作流中通过 `workflow_call` 直接串联 `release-binaries.yml`（可参考本仓库 [.github/workflows/moonset-release.yml](../.github/workflows/moonset-release.yml) 与 [.github/workflows/release-binaries.yml](../.github/workflows/release-binaries.yml)），无需额外创建长期 Personal Access Token (PAT)。

---

### Q3：如何正确配置 Mooncakes 发布凭据（`MOONCAKES_CREDENTIALS`）？

**原因**：  
`moon publish` 从 `~/.moon/credentials.json` 读取登录凭据，而不是仅读取单个 `MOONCAKES_TOKEN` 环境变量。

**配置步骤**：
1. 在本机执行 `moon login` 完成登录，读取本机 `~/.moon/credentials.json` 的完整 JSON 内容。
2. 在 GitHub 仓库 **`Settings` → `Secrets and variables` → `Actions`** 新增 Secret `MOONCAKES_CREDENTIALS`，粘贴该 JSON 内容。
3. 在发布工作流中通过 `mooncakes-credentials: ${{ secrets.MOONCAKES_CREDENTIALS }}` 传给 `unmbt/moonset@v1`（Action 会以 `0600` 权限写入 Runner 的 `~/.moon/credentials.json` 且不打印到日志）。

---

## 2. 本地工作流与状态文件

### Q4：`.moonset/` 目录下哪些文件应该提交到 Git，哪些应该加入 `.gitignore`？

| 文件 | 是否提交 Git | 作用说明 |
|---|---|---|
| `.moonset/release-state.json` | **必须提交** | 由 `moonset version` 生成，随 Release PR 合并到主干；CI 执行 `publish` 与 `tag` 时直接读取它确定要发布的包、版本与标签。 |
| `.moonset/version-journal.json` | **应当忽略** | `version` 写盘事务恢复日志，成功完成后自动删除；异常中断时用于 `moonset version --recover`。 |
| `.moonset/publish-state.json` | **应当忽略** | `publish` 逐包/逐目标执行状态缓存，用于失败续跑跳过已成功包；`moonset publish` / `tag` 内部会自动忽略它，不会阻断工作树干净检查。 |
| `.moonset/pack-results.json` | **应当忽略** | `pack` 生成的本地归档索引与摘要记录。 |

运行 `moonset init` 或 `moonset doctor --fix` 会自动生成包含运行期忽略项的 `.moonset/.gitignore`。

---

### Q5：`moon publish --dry-run` 或 `moon install` 报错：`moon.mod.json is no longer supported`

**原因**：  
项目依赖树中的某项传递依赖默认解析到了尚未迁移至新 `moon.mod` 格式的旧版本包（例如某些旧版 UI/CSS 包），而 `moon publish` 会在隔离临时目录校验源码包。

**解决方式**：  
使用 `moon tree` 定位旧格式传递依赖，并在项目根 `moon.mod` 的 `import` 中显式锁定已迁移的新版兼容依赖版本，直到 `moon publish --dry-run` 在干净归档验证中通过 `Check passed`。

---

### Q6：什么时候选 `moonset`，什么时候选 `moon-bump`？

- **[moon-bump](https://github.com/unmbt/moon-bump)**：适合单包或紧凑型 workspace 的**本地交互式一键发版**（直接选定版本、改 `moon.mod`、提交、打 tag 并推送）。
- **moonset**：适合**多人 PR 协作、需要自动生成 `CHANGELOG.md`、多包联动或 MoonBit + npm/pnpm + Cargo 混合 workspace** 的版本与发布治理，配合模块化 GitHub Actions 实现 PR 检查与自动发版。

---

### Q7：如何在预发布（`alpha` / `beta` / `rc`）与正式版之间切换？

```bash
# 1. 进入预发布模式（建议携带 --initial-version 记录基线版本）
moonset pre enter alpha --initial-version

# 2. 每次合并 changeset 后运行 version，版本号将按 0.2.0-alpha.0 -> 0.2.0-alpha.1 递增
moonset version

# 3. 准备毕业为正式版时退出预发布模式
moonset pre exit

# 4. 再次运行 version，自动毕业为正式版本（如 0.2.0）并清理 .changeset/pre.json
moonset version
```
