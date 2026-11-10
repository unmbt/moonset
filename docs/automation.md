# GitHub 自动化设计

## 1. 推荐流水线

将发布拆成四类 job，避免一个 token 同时拥有 PR 写权限和注册表发布权限：

1. **PR check**：`moonset status --since=$BASE_SHA --output json`；缺 changeset 时按仓库策略 warning 或失败。
2. **Release plan**：默认分支合并后运行 `moonset version --dry-run`，生成并审阅 plan；可由机器人创建 release PR。
3. **Version apply**：在受保护的 release PR 中运行 `moonset version`，提交 manifest/changelog/changeset 消费结果。
4. **Publish and tag**：release PR 合并后运行 `moonset publish --yes`，成功后 `moonset tag --push`。

每个 job 都固定 MoonBit 版本，缓存 MoonBit 依赖，并上传 `publish-plan.json` 作为 artifact。

## 2. 参考 workflow

以下仅为单 MoonBit 生态的设计模板，混合发布使用第 7 节的图和 target 路由，不能把全部包交给同一个 moon publisher。发布 action 和安装方式稳定后把 `moonset/setup` 替换为正式 action；在此之前可使用仓库自己的安装步骤。

```yaml
name: moonset
on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  pull-requests: read

jobs:
  changeset-check:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: moonbitlang/setup@v1
      - run: moonset status --since="${{ github.event.pull_request.base.sha }}" --output json > status.json
      - uses: actions/upload-artifact@v4
        with: { name: moonset-status, path: status.json }

  publish:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: write
      id-token: write
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: moonbitlang/setup@v1
      - run: moonset publish --dry-run --yes
      - run: moonset publish --yes
        env:
          MOONSET_REGISTRY_TOKEN_ENV: MOONCAKES_TOKEN
          MOONCAKES_TOKEN: ${{ secrets.MOONCAKES_TOKEN }}
      - run: moonset tag --push --yes
```

`moonbitlang/setup@v1` 和 action 版本是示意依赖，正式接入前必须以实际发布的 action 为准。Workflow 必须 pin major 或 commit，并在仓库中记录升级策略。

## 3. 权限与机密

- PR check 只读 `contents` 和 `pull-requests`。
- 版本 PR 机器人需要 `contents: write`、`pull-requests: write`，不需要 registry token。
- 发布 job 使用 OIDC（若 registry 支持）或只读到发布步骤的短期 secret；不把 token 作为命令参数。
- `pull_request_target` 只运行受信任分支的脚本，不能直接执行贡献者分支中的任意 publisher 配置。
- 日志中只打印 registry 名、包名、版本和脱敏 external id。

## 4. 发布 PR 与并发

- 以 `release/<baseBranch>` 为默认分支，使用 concurrency group `moonset-release-${{ github.ref }}`，取消过时的 plan。
- plan artifact 包含 workspace/config/changesets fingerprint；apply 前重新验证，防止旧 PR 覆盖新改动。
- 发布 job 使用 `concurrency: moonset-publish` 且不取消正在发布的任务。
- 部分发布失败时保留 artifact 和失败包列表；重试只调用 publisher 的 `already_published` 检查。

## 5. GitHub App 机器人

### 事件

- `pull_request.opened|synchronize|reopened`：检查变化。
- `pull_request.closed`：关闭或更新机器人评论，不发布。
- `installation_repositories`：刷新可访问仓库缓存。

### 行为

1. 使用 base SHA 和 head SHA 构建只读 snapshot。
2. 调用 `moonset status --since=<base>`，判断 changed package、changeset 和策略例外。
3. 使用固定 marker `<!-- moonset-bot:changeset-check -->` 查找已有评论，幂等更新，不重复刷屏。
4. 缺失 changeset 时评论带 `moonset/missing-changeset` label 和 `moonset add` 建议链接；`--empty` 适用于明确不需要发布的 PR。
5. 解析错误以失败状态和文件位置报告；不执行 `version`、`publish`、`tag`。

### 权限

App 默认需要 `pull_requests: read/write`、`contents: read`、`metadata: read`。发布由 Action 完成，App 不持有 Mooncakes 发布 token。

## 6. 审计事件

Action 和 App 的 JSON 事件记录 `schemaVersion`、repository、run/installation id、plan fingerprint、command、result、duration 和 error code；删除 commit message、token、摘要中的敏感值。保留时间由仓库策略决定。

## 7. 混合发布与 native addon 流程

1. 版本 PR 更新所有受管清单和锁文件，持久化 release intent；合并后以 release commit 固定输入，不能依赖已消费 changeset 重新推导目标。
2. 按 ArtifactIntent 生成构建矩阵（OS/架构/ABI）。napi-mbt、napi-rs 或其他构建工具负责生成二进制，moonset 负责验证 UnitId、版本、commit、目标和 hash。
3. 必需平台包全部验证完成后才能开始相关发布；按 `waitFor(build|publish)` 和 registry 依赖执行图运行。多平台 build job 不持有发布凭据。
4. npm、Mooncakes 和未来 Cargo/GitHub 目标各用自己的 publisher、权限与凭据；OIDC 支持逐目标验证，不从 npm 能力推断其他 registry。
5. 单一 coordinator 管理 `(domain, planId)` 的 journal/concurrency。发布 job 不取消正在执行的旧计划；失败时持久化成功/失败/blocked 状态，可续跑但不自动撤回已发版本。
6. 只有全部必需目标成功才标记产品完成并生成汇总 tag/release。可选目标失败也必须显示；不得把网络超时当作“未发布”。

App 的检查结果展示 UnitId 和所属 domain，只评价自己管理的分区；提示 bridge 引起的 JS 重发及未归属共享文件。已有 Changesets bot 可以留在独立分区，但不能让两个 bot 为同一 changeset 目录执行版本更新。
