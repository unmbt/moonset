# moonset 文档与规范

> 状态：Phase 1 alpha 实现；完整产品规格仍按阶段推进。
>
> 本目录是 moonset 的规格、设计和交付契约。实现尚未开始前，需求 ID、命令契约和数据不变量优先于代码；实现过程中必须回写状态和验证证据。

## 阅读顺序

当前可执行边界先阅读 [Phase 1 契约](phase-1-contract.md)。后续命令、适配器、执行模型仍是设计契约，不能仅凭 schema 接受某字段就认为能力已实现。

1. [需求规格](requirements.md)：为什么做、做什么、不做什么，以及可验收条件。
2. [命令契约](commands.md)：CLI 的参数、输出、退出码和副作用。
3. [配置规范](configuration.md)：`.changeset/config.json` 的稳定字段和扩展边界。
4. [数据模型](data-model.md)：workspace、changeset、release plan、预发布状态和发布结果。
5. [系统架构](architecture.md)：MoonBit 包边界、I/O 边界、纯规划器和适配器。
6. [Changelog 规范](changelog.md)：生成格式和自定义生成器契约。
7. [自动化设计](automation.md)：GitHub Actions、GitHub App 机器人和权限模型。
8. [编程 API](api.md)：给 MoonBit 库和外部工具使用的 API。
9. [测试策略](test-strategy.md)：需求到测试的追踪、fixture 和交付前检查。
10. [参考实现评估](references.md)：`moon-bump`、`moon-manifest`、`native-toolchain` 与 Changesets 源码的取舍。
11. [Roadmap](roadmap.md)：按阶段交付和每个阶段的退出条件。
12. [混合 workspace 设计](mixed-workspaces.md)：MoonBit + npm/pnpm 的共存、统一管理、跨生态构建与发布；包含 napi-rs/Tauri 类型场景和后续 Cargo 边界。

设计决策记录在 [decisions/](decisions/)。

## SDD 工作规则

- 每个能力先建立一个带 ID 的需求（`FR-*`、`NFR-*`、`SEC-*`），再写设计和测试映射。
- 代码只能实现已接受（Accepted）的契约；发现实现与契约不一致时，先更新规格并记录 ADR。
- 纯计算必须可以在不访问文件系统、Git、网络的情况下测试；副作用集中在适配器。
- CLI 的人类输出和 `--json` 输出都属于接口。脚本只依赖 JSON，不解析人类文本。
- 每个命令都定义成功、用户输入错误、配置错误和外部工具失败的行为。
- 文档示例中的 MoonBit API 必须用当前工具链验证；本版本基线见 [参考实现评估](references.md)。
- 实现一个阶段前，维护 `requirements.md` 的状态；实现后补上验证命令和测试编号。
- 本地开发提交前必须使用与 CI 相同的严格检查：`moon check --target native --deny-warn`；同时运行受影响的 `moon test --target native --deny-warn`（若工具链不支持 test 的该参数，则至少执行前一条 check）。普通不带 `--deny-warn` 的检查不能作为 CI 通过依据。

## 状态标记

| 标记 | 含义 |
|---|---|
| Proposed | 已提出，尚未冻结 |
| Accepted | 可进入实现 |
| Implemented | 已实现并有验证证据 |
| Deferred | 明确延后，有替代方案或依赖 |
| Rejected | 不纳入产品范围 |

## 当前基线

- 工具链：`moon 0.1.20261104`、`moonc v0.10.20`（2026-11-10 本地验证）。
- 目标：`native`，因为 moonset 是跨平台的宿主 CLI；库层保持无平台状态。
- 异步：优先使用 `moonbitlang/core/async` 及其 `fs`、`process`、`shell` 子包。已用 `moon ide doc` 验证导出 API。
- 清单：优先复用 `unmbt/moon-manifest` 的无损读取和编辑能力，待该包发布可消费版本后再锁定依赖。
- 发布：默认面向 Mooncakes 的 `moon publish`；发布器是可替换适配器，不能把 Mooncakes 假设写进核心规划器。
- 混合生态：已补充 Proposed 规格与 [示例配置](examples/mixed-workspaces.json)，尚无实现。核心以 ReleaseUnit 建模；npm/pnpm 联合版本和发布纳入 Phase 3/4，Cargo/应用适配后续接入。


