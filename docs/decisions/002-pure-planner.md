# ADR-002：纯 release planner 与适配器分离

- 状态：Accepted
- 日期：2026-11-10

## 决策

planner 只接收 `WorkspaceSnapshot`、changesets、配置和 pre state，返回不可变 `ReleasePlan`。文件系统、Git、Moon 命令、registry、提示和时钟通过适配器注入。

## 原因

规划需要可重复、可预览、可在 CI/App/API 中复用；I/O 混入规划会让 dry-run、测试和失败恢复不可控。

## 后果

需要额外的 snapshot/fingerprint 和 adapter 类型，但可以用固定 fixture 测试全部版本传播规则。
