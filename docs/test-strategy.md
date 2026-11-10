# 测试与验证策略

测试跟随 SDD 需求 ID 命名，避免只测试实现细节。

Phase 1 实际验证：`moon test --target native`（engine 解析/规划 golden 与 workspace 临时目录/Git 集成）、`moon run scripts/cli-integration.mbtx`（真实可执行文件黑盒），以及 `moon run scripts/embed-schema.mbtx --check`（编译内置 schema 与文档一致）。`.github/workflows/ci.yml` 在 Windows/Linux/macOS 固定 MoonBit 0.10.20 执行 check/test/build、CLI、格式与接口检查。

这些测试覆盖 FR-003/004/005/006，FR-011/012/016 的 Phase 1 子集，以及 FR-018/019/023 的共存边界。后续 init/version/publish、npm adapter 和 App 的测试矩阵尚未宣称通过。

## 1. 测试层次

| 层次 | 内容 | 依赖 | 典型命令 |
|---|---|---|---|
| 纯单元 | SemVer、front matter、配置合并、依赖传播、pre 序号、tag 模板 | 无 I/O | `moon test internal/...` |
| Golden | `ReleasePlan` 和 changelog Markdown 的稳定 JSON/文本 | 固定 Clock | `moon test --update` 仅在规格变更时使用 |
| 适配器 | lossless manifest 编辑、原子写入、Git 参数、publisher dry-run | 临时目录/测试 double | `moon test --target native` |
| CLI 黑盒 | 退出码、人类输出、`--json` schema、交互禁用 | 构建出的 `moonset` | `moon test cmd/moonset` |
| 集成 | init → add → status → version → pack → publish dry-run → tag | 临时 Git 仓库和 fake registry | CI native matrix |
| 自动化 | workflow 权限、App 事件去重、重放和失败恢复 | fixture webhook | Action/App 测试环境 |

## 2. 需求映射

- FR-001/002：`init_add_*` 黑盒和重复执行测试。
- FR-003/004：`workspace_discovery_*`、`changeset_parser_*` golden。
- FR-005/006：`planner_*`、`status_json_*` 和 fixed/linked/pre 矩阵。
- FR-007/008/010：`apply_plan_*`、原子写入、tag conflict 和恢复测试。
- FR-009/011：fake publisher/pack runner 的 dry-run、already-published、partial failure。
- FR-012/013/016：配置 schema、生成器 registry、JSONL 超时和 API `.mbti` diff。
- FR-014/015：workflow lint、最小权限审查、App webhook 幂等。
- FR-017：`doctor` 对缺工具、脏工作树、损坏配置和权限不足逐项给建议。
- FR-018、FR-019、FR-023：混合成员发现、UnitId 与共存边界，详见下方 MIX-001 至 MIX-004。
- FR-020、FR-021：bridge 闭包、原生协议与锁文件 ownership，MIX-005 至 MIX-008。
- FR-022、FR-024：artifact/publisher 能力与部分失败，MIX-009 至 MIX-012。
- NFR/SEC：跨平台路径、随机排序、shell metacharacter、凭据脱敏和 stale plan fixtures。

## 3. 最小 fixture 集

```text
fixtures/
  single-module/
  workspace-two-modules/
  fixed-and-linked/
  prerelease/
  invalid-frontmatter/
  private-and-ignore/
  stale-plan/
  partial-publish/
```

每个 fixture 固定 `moon.mod`/`moon.work`、`.changeset`、Git commit graph 和预期 plan。测试不得依赖本机用户名、时区、默认分支或 registry 网络。

## 4. 交付前检查

```text
moon fmt
moon check --target native
moon test --target native
moon info
```

变更公共 API 时审查 `pkg.generated.mbti`；文档中的 MoonBit 示例若放入 `.mbt.md`，必须用 `moon check --deny-warn` 验证。Markdown 交叉链接和 YAML workflow 也要在 CI 检查。

## 5. 混合 workspace 验收矩阵（待实现）

| 测试编号 | 输入 | 应观察结果 |
|---|---|---|
| MIX-001 | 根 pnpm workspace + 子目录 MoonBit workspace，含 root private 工具包 | 只发现声明成员；根工具包依 includeRoot 决定，不因存在 package.json 自动发布。 |
| MIX-002 | 同目录 moon.mod/package.json 不同版本 | 共存仅改归属字段；统一管理仍保留独立版本，除非 fixed。 |
| MIX-003 | 同名跨生态、同名同生态、symlink 重复路径、嵌套 Git checkout | 前者以 UnitId 区分，其余分别诊断重名、去重/拒绝越界、排除 checkout。 |
| MIX-004 | 已有 Changesets 管理根目录，moonset 管理 native 分区 | 不读删另一方 changeset，不修改其 lockfile；跨区只读建议。 |
| MIX-005 | MoonBit minor + npm consumer patch bridge；另加 consumer major | 前者 consumer patch，后者 major；不凭 bridge 生成虚假的 npm dependencies。 |
| MIX-006 | fixed 跨生态组与 build/publish 环；--only 遗漏 producer | fixed 扩展闭包；不可执行的环和不完整筛选在写入前失败。 |
| MIX-007 | workspace:^、workspace:*、peer/dev/optional、别名、未知协议 | 按 npm/pnpm profile 处理、保留协议；不支持时明确失败，不套用 MoonBit 范围逻辑。 |
| MIX-008 | root lockfile、生成 dist 清单、双写字段、stale hash | 一个 manager 更新锁文件；不重复发现 dist；写冲突/stale 阻止应用。 |
| MIX-009 | npm private=true + privatePackages.publish=true | 始终不允许 npm publish；MoonBit restricted visibility 独立校验。 |
| MIX-010 | 平台包构建缺失、commit/hash 不符、某平台包发布失败 | 主包阻塞，产品 tag 不创建，报告缺失节点与原因。 |
| MIX-011 | Mooncakes 成功、npm 失败后重试；远端同版本不同摘要 | 复用成功凭据、只补缺失目标；摘要冲突不覆盖、不 unpublish。 |
| MIX-012 | Cargo adapter 缺失、registry 不支持 next channel、同目录 changelog/tag 重名 | capability/ownership/ref 错误；不能以“未发现变化”退出成功。 |

分别对 npm 与 pnpm 维护固定 manager 版本的 fixtures。Cargo 和 Tauri 配置样例只作模型检验，真实支持需要额外 adapter conformance 证据。
