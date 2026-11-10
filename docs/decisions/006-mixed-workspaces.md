# ADR-006：以发布单元管理混合生态 workspace

- 状态：Proposed
- 日期：2026-11-10
- 关联：FR-018 至 FR-024；补充 ADR-002、ADR-004、ADR-005

## 背景

原方案以 `moon.mod` 模块名为全局身份，以单一 Mooncakes publisher 为默认。MoonBit + JS 仓库可以同目录有两个清单、不同版本，以及只通过构建产物相连的关系；仅注入 Publisher 不足以支持这种仓库。

## 决策草案

使用 `ReleaseDomain -> EcosystemWorkspace -> ReleaseUnit` 模型，UnitId 为生态与原始名称的组合。显式支持分区共存与统一管理，声明清单字段、changeset 目录、锁文件的唯一所有者。

由 EcosystemAdapter 处理原生发现、版本语义、无损编辑、包管理器和打包；纯 planner 处理规范化的版本约束、依赖闭包和显式 bridge。固定版本组、构建依赖、发布顺序分别表达。

初期支持 MoonBit 和 npm/pnpm，Cargo/应用发布保留接口并延后实现。保留统一 changeset 的文本形式，不承诺 Node Changesets 可以读写混合配置或带生态前缀的 ID。

## 后果

数据模型、CLI 选择器、tag 命名、pre 状态、JSON schema 和恢复记录都使用 UnitId。多 registry 发布只能做可恢复的部分成功，不能保证原子发布。每个 adapter 必须通过 capability 和 conformance 检查。

完整契约和例子见 [混合 workspace 设计](../mixed-workspaces.md)。
