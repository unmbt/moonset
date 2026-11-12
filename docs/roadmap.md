# Roadmap

> Roadmap 只描述可交付能力，不承诺日历日期。每个阶段完成后必须满足退出条件，才能进入下一阶段。

## Phase 0 — 规格与探针（已建立基线）

交付：需求、命令契约、配置、数据模型、架构、API、自动化和 ADR；建立最小 fixtures 和工具链探针。

退出条件：

- `requirements.md` 中 FR-001 至 FR-006 的边界已 Accepted。
- 选定 `core/async`、manifest、Git 和 SemVer 的实际 API，并有 `moon ide doc` 或项目代码证据。
- 规划器输入/输出 fixture 能覆盖单模块、workspace、fixed、linked、pre。
- 补充评审 [混合 workspace 设计](mixed-workspaces.md) 与 ADR-006，明确共存分区和统一管理；不把“可换 publisher”当成已经支持混合 workspace。

## Phase 1 — 核心读模型与规划器

实现已落地；验收命令与边界见 [Phase 1 契约](phase-1-contract.md)。完整发布流程完成前保持 alpha。共享 manifest 依赖采用经过三平台 CI 的 0.2.0 alpha；`native-toolchain` 不属于此阶段依赖。

交付：workspace discovery、无损 manifest 读取、changeset parser、config loader、SemVer、依赖图和纯 release planner；实现 `status` 与 `publish-plan`。

退出条件：

- 规划器无 I/O 依赖，golden tests 在 native 通过。
- 错误定位包含文件和行列；无效输入不会产生写入。
- JSON 输出 schema 版本为 `1`，并有兼容性测试。
- 核心从开始使用 UnitId、ReleaseUnit、ownership 和分类型依赖；支持同目录双清单的共存边界，JS/Cargo 未接入时明确报 capability。覆盖 FR-018、FR-019、FR-023 的基础场景。

## Phase 2 — 贡献工作流

交付：`init`、`add`、`pre`、交互式摘要、格式化和 changeset README；补充 PR 检查脚本。

退出条件：

- 新建项目从 `init` 到 `status` 全流程可运行。
- 重复 `init` 不覆盖文件，`add` 生成 ID 不冲突。
- CI 能使用 `status --since` 判断是否需要 changeset。

## Phase 3 — 版本与 Changelog（实现中：核心流程已落地）

交付：`version`、内置 changelog 生成器、依赖范围更新、fixed/linked/private 策略、原子写盘、`tag`。

退出条件：

- 当前已实现 version-plan、内置 changelog、MoonBit/npm 版本编辑、release state、journal 恢复和 tag CLI；锁文件 staging 与真实 registry 发布仍属于后续增量。

- 版本前后所有 manifest 的语法仍可被 MoonBit 解析。
- 失败演练后工作区可按恢复指令回到一致状态。
- 生成的 changelog 有稳定格式、日期和链接策略。
- 接入 npm/pnpm workspace discovery、JSON 编辑和锁文件 staging；用混合计划验证 bridge、fixed/linked、private 发布禁令和跨生态 tag/changelog 冲突（FR-018 至 FR-021）。

## Phase 4 — 发布与官方自动化

交付：`pack`、`publish`、Mooncakes publisher、GitHub Actions 示例、OIDC/令牌文档、发布状态和重试。

退出条件：

- dry-run 不修改注册表和 Git 引用。
- 发布失败能区分已发布和未发布模块，重复执行不会错误重发。
- CI 参考 workflow 通过 YAML lint 和最小权限审查。
- MoonBit + npm 双目标发布和 native addon 平台包完成端到端验证；分离 build/publish DAG，支持按 target 续跑及凭据隔离（FR-022）。

## Phase 5 — 扩展生态

交付：`@moonset/api` 稳定接口、Git/GitHub changelog 生成器、JSONL generator/publisher 协议、第三方适配器示例。

退出条件：

- API 版本策略和兼容承诺写入文档。
- 一个外部 MoonBit 包和一个外部进程插件完成端到端测试。
- 插件超时、非法输出和权限拒绝均有测试。
- EcosystemAdapter/ArtifactProvider conformance suite 覆盖 discovery、range、ownership、lockfile、artifact、publish 能力。Cargo/Tauri 类适配在此后按需求接入，未完成前保持 Deferred（FR-024）。

## Phase 6 — GitHub App 与规模化治理

交付：App webhook 服务参考实现、PR 评论去重、标签策略、审计事件、1000 包/10000 changeset 基准和缓存。

退出条件：

- App 不保存长期 token，事件重放不会重复评论或触发发布。
- 性能、并发、失败恢复和升级路径有数据。
- 稳定版发布清单完成，Draft 需求全部处理。

## 暂缓项目

- Node Changesets 的配置、插件运行时及目录互写兼容：暂不承诺。npm/pnpm 混合 workspace 的原生支持已纳入 Phase 3/4，不再整体推迟。
- 任意动态 MoonBit 模块加载：由编译期 API 和 JSONL 协议覆盖，等工具链提供稳定模块加载机制后再评估。
- 自动提交/推送：保留显式开关；默认让 CI 或维护者控制 Git 提交边界。
