# ADR-007：以模块化 GitHub Action 替代 GitHub App 服务端

- 状态：Accepted
- 日期：2026-11-18
- 关联：FR-014、FR-015、SEC-003、SEC-005、OPS-001；替代 [自动化设计](automation.md) §5 的 GitHub App 服务端设计（不影响 ADR-005、ADR-006）

## 背景

原 SDD（[自动化设计](../automation.md) §5 与 [Roadmap](../roadmap.md) Phase 6）将 PR 检查与评论机器人设计为独立托管的 GitHub App webhook 服务（例如 Node.js / Cloudflare Worker）。如果采用外部 App 服务，必须通过 GitHub API 远程拉取文件，并用另一种语言重新实现一遍 workspace 发现、依赖图计算和 changeset 解析逻辑；同时用户需自行注册 App、部署 Worker 或依赖中心化托管服务，带来运维、Token 安全与 API 限流风险。

## 决策

1. **采用模块化 GitHub Action + 预编译 CLI 实现 Bot**：moonset 不提供 GitHub App，也不维护或托管任何中心化 webhook 服务。所有 PR 检查、评论更新、Release PR 创建和发布均以开源 Composite GitHub Action 形态交付，运行在用户自己仓库的 GitHub Runner 上。
2. **100% 复用现有核心逻辑**：PR 检查由 Action 调用预编译的 `moonset` 二进制（`moonset status --since <base> --output markdown` 与 `--output json`），直接读取本地 checkout 的文件与 Git 历史，保证本地 CLI、CI 与 PR Bot 的行为完全一致。
3. **以双 Job + 最小权限解决 Fork PR 安全性**：
   - 需要评论外部贡献者 Fork PR 时，使用 `pull_request_target` 触发，并拆分为两个独立 Job：
     - **Job 1（`pr-check`）**：仅申请 `contents: read`，以 `persist-credentials: false` checkout PR head，**仅运行可信的预编译 `moonset` 二进制**（或基于基础分支构建的可信二进制）静态分析文件与 `git diff`，通过 Job outputs 传出评论文本与状态；**严禁**执行目标仓库/PR 分支的任意脚本、`moon build` 或包管理器 install hooks。
     - **Job 2（`pr-comment`）**：**不 checkout 代码**，仅申请 `pull-requests: write`（加标签时按需增加 `issues: write`），使用隐藏 HTML 标记 `<!-- moonset-bot:changeset-check -->` 与可信 bot 作者校验幂等更新同一条评论。
4. **模块化组合入口**：在 `unmbt/moonset` 仓库内提供 `setup`、`pr-check`、`pr-comment` 与根 Action（`version-pr` / `publish`），并通过 tag 发布三平台预编译二进制与 `SHA256SUMS`。

## 原因

- 避免核心解析、依赖图与版本规划逻辑在 MoonBit 与 JS/TS 之间维护两套实现。
- 显著降低接入门槛：用户只需复制粘贴一个 `.github/workflows/*.yml` 文件，无需申请/部署 GitHub App。
- 零运维与零中心化成本/安全风险：每个仓库仅使用自己的 `GITHUB_TOKEN` 与 Runner 配额。

## 后果

- 必须通过 GitHub Releases 分发跨平台预编译 CLI 与 `SHA256SUMS`，并在 `setup` Action 中强制校验摘要。
- 在 `pull_request_target` 场景下引入了严格的安全红线（[SEC-005](../requirements.md)）与静态 workflow 检查脚本。
- 评论去重依赖固定的隐藏 HTML marker 与评论作者校验；如果未来需要跨组织统一仪表盘，可在不改变现有 CLI JSON/Markdown 输出契约的前提下在外部消费。
