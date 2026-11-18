# GitHub 自动化设计

> 决策记录见 [ADR-007：以模块化 GitHub Action 替代 GitHub App 服务端](decisions/007-pr-bot-as-action.md)。moonset 所有自动化均通过模块化 Composite GitHub Actions 与预编译 `moonset` CLI 运行在用户自己的 GitHub Runner 上，不提供 GitHub App 或中心化托管服务。

## 1. 推荐流水线

将自动化拆成四类独立 Job，避免单一 token 同时拥有 PR 写权限和注册表发布凭据：

1. **PR Check（Job 1，`pr-check`）**：在只读权限下运行 `moonset status --since "$BASE_SHA" --output markdown` 与 `--output json`，生成确定性评论 Markdown 与状态，并通过 Job outputs 导出。
2. **PR Comment（Job 2，`pr-comment`）**：不 checkout 代码，仅持 `pull-requests: write` 权限读取 Job 1 outputs，按隐藏 marker + 可信作者幂等更新同一条 PR 评论，可选添加缺失标签或回传检查失败退出码。
3. **Release PR（`moonset@v1`，`mode: version-pr`）**：默认分支合并后，若存在待消费 changeset，执行 `moonset version --no-commit`，更新或创建 release PR（默认分支 `moonset-release/<baseBranch>`），在 PR 正文列出预计版本表供维护者审阅。
4. **Publish and Tag（`moonset@v1`，`mode: publish`）**：release PR 合并并存在 `.moonset/release-state.json` 时，按远端 Git tag 幂等检查未发布的发布目标，依次执行 `moonset publish --yes --no-tag --json` 与 `moonset tag --push --yes`，并上传 publish 状态 JSON 作为 artifact。

## 2. 参考 workflow

所有参考 workflow 可直接复制使用，依赖 `unmbt/moonset` 官方发布的复合 Action（自动下载并校验对应 tag 的预编译 CLI 二进制）：

- PR 检查与评论机器人模板：[docs/examples/workflows/moonset-pr-bot.yml](examples/workflows/moonset-pr-bot.yml)
- 自动创建 Release PR 与发布模板：[docs/examples/workflows/moonset-release.yml](examples/workflows/moonset-release.yml)

单仓库内自用 release workflow 见 [.github/workflows/moonset-release.yml](../.github/workflows/moonset-release.yml)；PR Bot 自用 workflow 见 [.github/workflows/moonset-pr-bot.yml](../.github/workflows/moonset-pr-bot.yml)。混合发布继续遵循第 7 节的依赖图与 target 路由，不能把非 MoonBit 单元交给 `moon publish`。

## 3. 权限矩阵与安全红线

| Job | `permissions` | Checkout 策略 | 凭据与秘密 |
|---|---|---|---|
| `pr-check`（Job 1） | `contents: read` | PR head，`persist-credentials: false` | 无；不传入任何 registry 或写权限 token |
| `pr-comment`（Job 2） | `pull-requests: write`（可选 `issues: write`） | **禁止 checkout** | `GITHUB_TOKEN`（仅当前仓库评论权限） |
| `version-pr` | `contents: write`、`pull-requests: write` | 默认分支 | `GITHUB_TOKEN`；严禁传入 registry token |
| `publish` | `contents: write`、`id-token: write`（可选） | release commit | registry secrets；不申请 `pull-requests: write` |

> [!CAUTION]
> **`pull_request_target` 安全红线（SEC-005）**
> 1. 面对外部贡献者 Fork PR 时，只有 `pull_request_target` 才能向 PR 写入评论；如果仓库不接受 Fork PR 或只需本地检查，可直接改用只读 `pull_request`。
> 2. 在 `pull_request_target` 下 checkout 了 PR head 代码的 Job 中，**绝对禁止运行 PR 代码里的任何构建命令或脚本**（例如 `moon build`、`moon test`、`npm install`、`pnpm install`、`cargo build` 或自定义 `plugins.generators`），因为 `moon.pkg` pre-build、package scripts 或 Cargo `build.rs` 均可执行任意代码。
> 3. `pr-check` 必须仅运行可信的预编译 `moonset` 二进制（经 `SHA256SUMS` 校验的 Release 资产，或从基础分支构建的可信二进制）去静态解析清单、`changeset` 与 `git diff`。
> 4. **禁止脚本注入**：所有 `${{ github.event.* }}` 与 `${{ inputs.* }}` 必须先绑定到 `env:` 变量再于 shell 中以 `"$VAR"` 引用，评论正文通过文件或环境变量传入 `gh api`，绝不直接插值进 `run:` 脚本。
> 5. 日志中只打印 registry 名、包名、版本和脱敏 external id，不打印 token。

## 4. 发布 PR 与并发

- Release PR 默认使用分支 `moonset-release/<baseBranch>`，配置 `concurrency: group: moonset-release-${{ github.ref }}`，取消过时的 plan。
- plan artifact 与 `.moonset/release-state.json` 包含 workspace/config/changesets fingerprint；执行前重新校验，防止旧 PR 覆盖新改动。
- 发布 job 使用 `concurrency: moonset-publish` 且设置 `cancel-in-progress: false`，不取消正在执行的发布任务。
- 部分发布失败时保留 artifact 和 `.moonset/publish-state.json`；重试时跳过已确认成功目标，并通过 `git ls-remote --tags` 与 publisher `already_published` 校验避免误重发。

## 5. PR Bot（GitHub Action）

### 事件与并发

- `pull_request_target`：`opened`、`synchronize`、`reopened`、`ready_for_review`（可按需改为 `pull_request`）。
- 并发组：`concurrency: group: moonset-pr-bot-${{ github.event.pull_request.number }}`，`cancel-in-progress: true`，确保快速连续 push 只保留最新一次结果。

### 双 Job 行为

1. **Job 1（`pr-check`）**：
   - 使用 `actions/checkout` 拉取 `github.event.pull_request.head.sha`（`fetch-depth: 0`、`persist-credentials: false`）。
   - 调用 `setup` 获取可信预编译 `moonset` 二进制（或使用 `binary-path` 指定的受信任本地二进制）。
   - 执行 `moonset status --since "$BASE_SHA" --output markdown --head-repo "$HEAD_REPO" --head-ref "$HEAD_REF"`（容忍退出码 `1`/`2` 不中断 Job，以便把错误或缺失提示传给 Job 2）。
   - 同时查询 `moonset status --since "$BASE_SHA" --output json` 归类状态：`release`、`missing`、`empty`、`none`、`error`。
2. **Job 2（`pr-comment`）**：
   - 不 checkout 仓库。
   - 在输出评论第一行埋入固定标记：`<!-- moonset-bot:changeset-check -->`。
   - 调用 `gh api --paginate repos/$REPO/issues/$PR/comments` 搜索**作者 login 匹配 `bot-login`（默认 `github-actions[bot]`）且正文包含 marker** 的已有评论（防止其他用户通过粘贴 marker 劫持更新）。
   - 找到则 `PATCH` 更新该评论；未找到且 `should-comment == "true"` 则 `POST` 新建评论；未找到且 `should-comment == "false"` 则跳过。
   - 若配置了 `label`（如 `moonset/missing-changeset`），在 `state == "missing"` 时添加标签，在其他状态时幂等移除标签。
   - 若设置了 `fail-on-missing: true` 且 `state` 为 `missing` 或 `error`，最后以退出码 `1` 失败，阻断合并。

### 评论状态与内容安全

- **五种评论状态**：
  - `release`（✅）：展示版本变更表（`UnitId | 当前版本 → 新版本 | bump`）、关联 changeset 文件与转义后的首行摘要，以及混合模式的 `coexistence` 协调提示。
  - `missing`（⚠️）：列出相关改动路径（最多 20 条）、`moonset add` 本地命令示例、当提供 `--head-repo`/`--head-ref` 时附带 GitHub 一键新建 `.changeset/*.md` 的预填 URL，以及 `--empty` 说明。
  - `empty`（ℹ️）：确认已存在空 changeset，本次 PR 不触发发布。
  - `none`（ℹ️）：未触及任何受管单元；可通过 `comment-on-no-changes: false` 关闭首次新建（若已有历史 bot 评论仍会更新）。
  - `error`（❌）：解析或配置错误时报告 `code`、`path:line:column` 与转义后的错误信息；绝不执行 `version`、`publish`、`tag`。
- **转义与截断**：changeset 摘要、分支名、错误消息属于不可信输入。纯渲染器 `engine.status_markdown` / `engine.error_markdown` 必须转义 HTML 特殊字符（`&`、`<`、`>`）、表格竖线 `|` 与 `@` 提及（插入零宽字符），并限制最大长度（默认 `60000` 字符，超出后保留头部并附截断提示），防止评论中伪造 marker 或超出 GitHub 单条评论 `65535` 字符限制。

## 6. 审计事件

Action 输出的 JSON 与工作流日志记录 `schemaVersion`、repository、`run_id` / `run_attempt`、plan fingerprint、command、result、duration 和 error code；删除 commit message、token、摘要中的敏感值。保留时间由仓库策略决定。

## 7. 混合发布与 native addon 流程

1. 版本 PR 更新所有受管清单和锁文件，持久化 release intent；合并后以 release commit 固定输入，不能依赖已消费 changeset 重新推导目标。
2. 按 ArtifactIntent 生成构建矩阵（OS/架构/ABI）。napi-mbt、napi-rs 或其他构建工具负责生成二进制，moonset 负责验证 UnitId、版本、commit、目标和 hash。
3. 必需平台包全部验证完成后才能开始相关发布；按 `waitFor(build|publish)` 和 registry 依赖执行图运行。多平台 build job 不持有发布凭据。
4. npm、Mooncakes 和未来 Cargo/GitHub 目标各用自己的 publisher、权限与凭据；OIDC 支持逐目标验证，不从 npm 能力推断其他 registry。
5. 单一 coordinator 管理 `(domain, planId)` 的 journal/concurrency。发布 job 不取消正在执行的旧计划；失败时持久化成功/失败/blocked 状态，可续跑但不自动撤回已发版本。
6. 只有全部必需目标成功才标记产品完成并生成汇总 tag/release。可选目标失败也必须显示；不得把网络超时当作“未发布”。

PR Bot 的评论结果展示 UnitId 和所属 domain，只评价自己管理的分区；通过 `coexistence` 摘要提示跨分区改动及未归属共享文件。已有 Changesets bot 可以留在独立分区，但不能让两个 bot 为同一 changeset 目录执行版本更新。

## 8. Action 模块与二进制分发

### 模块结构

```text
moonset/
├── action.yml              # unmbt/moonset@v1          (mode: version-pr | publish)
├── setup/action.yml        # unmbt/moonset/setup@v1    (下载并校验预编译 CLI)
├── pr-check/action.yml     # unmbt/moonset/pr-check@v1 (Job 1：只读计算评论与状态)
└── pr-comment/action.yml   # unmbt/moonset/pr-comment@v1 (Job 2：不拉代码创建/更新评论)
```

### Action 输入输出契约

- **`setup/action.yml`**：
  - 输入：`version`（默认由 `github.action_ref` 推导，非 `v*` 时取 `latest`）、`binary-path`（可选，跳过下载直接使用可信本地路径）、`github-token`（默认 `github.token`）。
  - 输出：`path`（二进制路径）、`version`（实际解析版本）。
- **`pr-check/action.yml`**：
  - 输入：`base-sha`（必填）、`head-repo`、`head-ref`、`working-directory`（默认 `.`）、`version`、`binary-path`、`comment-on-no-changes`（默认 `'true'`）、`github-token`。
  - 输出：`comment`（渲染好的 Markdown 文本）、`state`（`release|missing|empty|none|error`）、`exit-code`、`should-comment`（`'true'|'false'`）。
- **`pr-comment/action.yml`**：
  - 输入：`comment`（必填）、`state`（必填）、`should-comment`（默认 `'true'`）、`pr-number`（默认事件 PR 编号）、`github-token`（默认 `github.token`）、`bot-login`（默认 `'github-actions[bot]'`）、`label`（默认 `''`）、`fail-on-missing`（默认 `'false'`）。
  - 输出：`comment-id`、`action`（`created|updated|skipped`）。
- **根 `action.yml`**：
  - 输入：`mode`（`version-pr` | `publish`，默认 `version-pr`）、`version`、`binary-path`、`working-directory`、`branch`（默认 `moonset-release/<base>`）、`title`（默认 `chore: release packages`）、`commit-message`（默认 `chore: release`）、`github-token`、`mooncakes-credentials`（可选，在 `publish` 模式下以 `0600` 权限写入 `~/.moon/credentials.json`）。
  - 输出：`has-changesets`、`pull-request-number`、`published`、`tags`。

### 预编译二进制分发（OPS-001）

- 由 `.github/workflows/release-binaries.yml` 在推送 `v*` tag、`workflow_dispatch` 或由自举发布流 `workflow_call` 调用时构建并随 GitHub Release 产出：
  - `moonset-linux-x64`（基于 `ubuntu-22.04` 构建，兼容 glibc 2.35+）
  - `moonset-linux-arm64`（基于 `ubuntu-22.04-arm` 构建）
  - `moonset-darwin-arm64`（基于 `macos-15` 构建）
  - `moonset-win32-x64.exe`（基于 `windows-latest` 构建）
  - `SHA256SUMS`（覆盖上述全部资产的 SHA-256 校验文件）
- CI Runner 由 `setup` Action（`setup/install.sh`）下载并校验 `SHA256SUMS` 后注入 `GITHUB_PATH`；普通开发者终端安装请使用 `scripts/install.sh`（Linux/macOS）或 `scripts/install.ps1`（Windows PowerShell），两者均安装到 `~/.unmbt` 并强制执行 `SHA256SUMS` 校验。Action major tag（如 `v1`）与对应 release 版本保持对齐。
