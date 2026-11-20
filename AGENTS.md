# moonset 开发与 SDD 协作指南

本项目是采用 **Specification-Driven Development（SDD）** 开发的 [MoonBit](https://docs.moonbitlang.com) workspace 版本管理、Changelog 生成与多生态发布工具。

> 核心原则：**先有契约，后有代码**。规格文档是可评审、可追踪、可执行的产品契约，而非实现后的说明书。

## 1. 规格单一事实源（Source of Truth）

不要凭猜测修改行为，改动对应领域前必须先核对 `docs/` 下的权威契约：

| 变更范围 | 必读规格文档 |
|---|---|
| SDD 流程与不可变原则 | [docs/sdd.md](docs/sdd.md)、[docs/README.md](docs/README.md) |
| 需求 ID、验收条件与当前状态 | [docs/requirements.md](docs/requirements.md) |
| CLI 子命令、参数、JSON 信封与退出码 | [docs/commands.md](docs/commands.md) |
| `.changeset/config.json` 与 Schema | [docs/configuration.md](docs/configuration.md)、[docs/schema/config-v1.json](docs/schema/config-v1.json) |
| 核心领域模型与状态结构 | [docs/data-model.md](docs/data-model.md) |
| 包边界、I/O 分层与架构决策 | [docs/architecture.md](docs/architecture.md)、[docs/decisions/README.md](docs/decisions/README.md) |
| 混合生态（MoonBit / npm / pnpm / Cargo） | [docs/mixed-workspaces.md](docs/mixed-workspaces.md) |
| GitHub Actions、PR Bot 与权限隔离 | [docs/automation.md](docs/automation.md) |
| 扩展 API 与 JSONL 插件契约 | [docs/api.md](docs/api.md)、[docs/decisions/008-v030-api-and-adapter-convergence.md](docs/decisions/008-v030-api-and-adapter-convergence.md) |
| 测试分层、fixture 与交付检查 | [docs/test-strategy.md](docs/test-strategy.md) |

## 2. SDD 五步交付流程

每个功能切片或缺陷修复均须按以下顺序推进：

1. **冻结需求边界**：在 [docs/requirements.md](docs/requirements.md) 确认或新增需求 ID（`FR-*` / `NFR-*` / `SEC-*` / `API-*` / `OPS-*`），明确输入边界、成功可观察结果、失败处理与验证命令，状态从 `Proposed` 推进到 `Accepted`。
2. **契约与 ADR 先行**：若涉及命令参数、JSON schema、数据模型或跨阶段决策，先更新 `docs/` 对应文档。修改已接受的设计决策时必须新建 ADR，严禁直接覆写历史 ADR。
3. **纯核测试先行**：先在无宿主 I/O 的纯计算包（`model` / `engine` / `changelog`）编写同步单元测试或 golden 测试（确保 `native` 与 `wasm-gc` 双目标兼容），再接入 `workspace` / `adapters` / `executor` / `cli`。
4. **严格门禁验证**：运行最窄测试后，必须通过与 CI 等效的严格检查（严禁用不带 `--deny-warn` 的 `moon check` 冒充通过）。
5. **回写证据与变更集**：在 [docs/requirements.md](docs/requirements.md) 更新状态（`Implemented`）与测试映射；面向用户的改动需通过 `moonset add` 或新增 `.changeset/*.md` 记录，**严禁手工编辑 `.moonset/release-state.json` 或 `publish-state.json`**。

## 3. 不可变设计原则、兼容性与安全红线

### 设计不变量（v1 冻结）

- **规划阶段绝对只读**：`status`、`publish-plan`、`--dry-run` 不写工作区、不创建 Git 引用、不访问写操作注册表。
- **全量校验后写盘**：执行前解析并校验所有配置文件与 `.changeset/*.md`；任一输入无效则整个计划中止，不得部分修改工作区。
- **原子替换与阶段恢复**：清单和 `CHANGELOG.md` 写入采用临时文件加原子重命名及 `.moonset/version-journal.json`；失败必须可恢复，不能留下半截文件。
- **`publish` 不隐式 `version`**：发布依赖已提交的 release commit 与 `.moonset/release-state.json`，`tag` 可独立重试。
- **机密隔离**：凭据仅从环境变量或 CI Secret/OIDC 注入，绝不写入 `.changeset/`、JSON 计划、Git 或日志。

### 公共 API 零破坏约束

- `model`、`engine`、`changelog`、`executor`、`api` 的公共接口以各包 `pkg.generated.mbti` 与 [fixtures/external-moonbit-api](fixtures/external-moonbit-api) 为准。
- **禁止向已有 `pub(all) struct` 直接增删字段或破坏性修改现有公开函数签名**（会导致外部构造字面量编译失败）。增量扩展应采用新增结构体、新增公开函数或从已有 `Config.raw` 解析，并在提交前审查 `pkg.generated.mbti` 差异。

### 安全红线（`SEC-001` ~ `SEC-005`）

- 外部进程调用必须分离可执行文件名与参数数组，**禁止把用户输入拼接进 `sh -c` / `cmd /c`**。
- `pull_request_target` 下的 `pr-check` Job 必须保持 `persist-credentials: false` 与只读权限，仅运行可信二进制静态分析，**绝对禁止运行 PR 分支的 `moon build` / `npm install` / `cargo build` 或自定义脚本**。
- Workflow 与 Action 中所有 `${{ github.event.* }}` 与 `${{ inputs.* }}` 必须先绑定至 `env:` 再在 shell 中以 `"$VAR"` 引用，禁止直接模板插值进 `run:`；PR 评论正文必须经纯渲染器转义并截断。

## 4. 包架构与跨目标边界

```text
cmd/moonset ──▶ cli ──▶ workspace + engine + executor + changelog + adapters ──▶ model
                                        │
                                  api / moonset.mbt（对外公共门面）
```

- **纯计算核心（无宿主 I/O，严禁声明 `supported_targets = "native"`）**：`model/`、`engine/`、`changelog/`。必须保持同步纯函数，同时通过 `native` 与 `wasm-gc` 编译与测试。
- **宿主能力层（`native`）**：`workspace/`、`adapters/`、`executor/`、`api/`、`cli/`、`cmd/moonset/`。异步文件与进程 I/O 基于 `moonbitlang/core/async` 与 `executor::ExecutionHost`。
- **GitHub Actions 薄壳**：`action.yml`、`setup/`、`pr-check/`、`pr-comment/`。**禁止在 YAML/shell 中重复实现 workspace 发现、changeset 解析、版本规划或 Markdown/Changelog 提取逻辑**，全部业务收口至 `engine`/`changelog` 与 `moonset` CLI。

## 5. MoonBit 编码与测试约定

- 代码采用 block 风格，每个顶层块使用 `///|` 分隔；已废弃代码保留在各包 `deprecated.mbt`。
- 使用 `moon ide`（`peek-def`、`outline`、`find-references`）辅助精确导航与重构。
- 稳定、确定的行为优先使用 `assert_eq` 或 `assert_true(val is Pattern(...))`；结构化输出快照测试应为类型派生 `Debug` 并使用 `debug_inspect`，仅在规格明确变更时执行 `moon test --update`。
- 可使用 `moon coverage analyze > uncovered.log` 检查未覆盖路径。

## 6. 强制验证矩阵

本地验证必须与 [.github/workflows/ci.yml](.github/workflows/ci.yml) 对齐：

```bash
# 基础必跑（每次提交前）
moon check --target native --deny-warn
moon test --target native
moon info && moon fmt --check
```

按改动范围追加以下专项验证：

| 改动内容 | 必须执行的验证命令 |
|---|---|
| 纯核心（`model/`、`engine/`、`changelog/`） | `moon check --target wasm-gc` 与 `moon test --target wasm-gc` |
| 配置 Schema（[docs/schema/config-v1.json](docs/schema/config-v1.json)） | 先运行 `moon run scripts/embed-schema.mbtx` 同步内嵌文本，再跑 `--check` |
| Actions / `.github/workflows/*` | `moon run scripts/lint-workflows.mbtx` |
| CLI / `executor/` / `workspace/` / 插件协议 | `moon build --target native --release` 与 `moon run scripts/cli-integration.mbtx` |
| `moon.mod` 或外部公共 API | `moon update`、`moon publish --dry-run`，并检查 `pkg.generated.mbti` 差异 |
