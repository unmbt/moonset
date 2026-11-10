# ADR-001：changeset 是发布意图的源数据

- 状态：Accepted
- 日期：2026-11-10

## 决策

贡献者提交 `.changeset/*.md` 作为“需要发布什么、为什么发布”的源数据。Git commit、diff 和 Conventional Commit 只能作为辅助信息，不能单独决定版本。

## 原因

changeset 能在改动发生时由作者表达语义，适用于 squash merge、跨包改动和非代码文档。它也能在版本生成前被审阅、修改和自动检查。

## 后果

需要严格解析、唯一 ID、`status --since` 和消费策略；没有 changeset 的内部改动可以显式使用 `none` 或 `--empty`。
