# 测试与验证策略

测试跟随 SDD 需求 ID 命名，避免只测试实现细节。

当前验证基线：`moon check --target native --deny-warn`、`moon check --target wasm-gc`、`moon test --target native`（覆盖 `model`/`engine`/`changelog`/`workspace`/`adapters`/`executor`/`cli`/`fixtures`）、`moon test --target wasm-gc`（验证纯计算核心无宿主依赖）、`moon run scripts/cli-integration.mbtx`（真实可执行文件黑盒），以及 `moon run scripts/embed-schema.mbtx --check`（编译内置 schema 与文档一致）。`.github/workflows/ci.yml` 在 Windows/Linux/macOS 固定 MoonBit 工具链执行 check/test/build、CLI、格式与接口检查。

这些测试覆盖 FR-001～FR-024 核心边界（含 FR-023 共存协调导出）、NFR-005 性能基准、PR Bot Action 与渲染契约（FR-014/015/SEC-005/OPS-001），以及 `fixtures/` 最小测试集和 `MIX-001`～`MIX-012` 关键场景；在线 GitHub Runner 的实际 PR/Release 触发待推送到 GitHub 后验证。

## 1. 测试层次

| 层次 | 内容 | 依赖 | 典型命令 |
|---|---|---|---|
| 纯单元 | SemVer、front matter、配置合并、依赖传播、pre 序号、tag 模板 | 无 I/O | `moon test --target wasm-gc` |
| Golden | `ReleasePlan` 和 changelog Markdown 的稳定 JSON/文本 | 固定 Clock | `moon test --update` 仅在规格变更时使用 |
| 适配器 | lossless manifest 编辑、原子写入、Git 参数、publisher dry-run | 临时目录/测试 double | `moon test --target native` |
| CLI 黑盒 | 退出码、人类输出、`--json` schema、交互禁用 | 构建出的 `moonset` | `moon run scripts/cli-integration.mbtx` |
| 集成 | init → add → status → version → pack → publish dry-run → tag | 临时 Git 仓库和 fake registry | CI native matrix |
| 自动化 | workflow 权限、`pull_request_target` 隔离、评论渲染快照与幂等 | `engine/pr_comment_test.mbt` + 静态 linter | `scripts/lint-workflows.mbtx`、`actionlint` |

## 2. 需求映射

- FR-001/002：`init_add_*` 黑盒和重复执行测试。
- FR-003/004：`workspace_discovery_*`、`changeset_parser_*` golden。
- FR-005/006：`planner_*`、`status_json_*` 和 fixed/linked/pre 矩阵。
- FR-007/008/010：`apply_plan_*`、原子写入、tag conflict 和恢复测试。
- FR-009/011：fake publisher/pack runner 的 dry-run、already-published、partial failure。
- FR-012/013/016：配置 schema、生成器 registry、JSONL 超时和 API `.mbti` diff。
- FR-014/015/SEC-005/OPS-001：`engine/pr_comment_test.mbt` 快照（5 种状态/转义/截断）、`scripts/cli-integration.mbtx`（`status --output markdown`）、`scripts/lint-workflows.mbtx`（静态权限与注入检查）与 `actionlint`。
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

## 5. 混合 workspace 验收矩阵（已落地关键用例，持续扩充）

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

---

## 6. `NFR-005` 性能基准与子进程瓶颈基线

为验证 **100 个包 + 1000 个 changeset** 规模下的性能指标，建立了两层可重复基准：

1. **纯计算核心基准（无 I/O）**：[engine/planner_bench_test.mbt](../engine/planner_bench_test.mbt)
   - 合成 100 个 MoonBit 单元（含链式依赖、扇出依赖与 2 个 `fixed` 组）与 1000 份 changeset 文本。
   - 测量 `parse_changeset` × 1000 + `build_plan` + `status_json` + `status_markdown` 全链路耗时，并配套等价正确性测试。
2. **CLI 端到端基准（真实 Git 仓库）**：[scripts/bench-status.mbtx](../scripts/bench-status.mbtx)
   - 在临时目录初始化包含 100 个成员的 `moon.work` 与 1000 个 `.changeset/cs-*.md` 文件及两条提交，编译 `--release` 二进制后预热 1 次、采样 3 轮取中位数。

### 关键优化手段

1. **批量 `git log` 与按需关闭**（[workspace/discovery.mbt](../workspace/discovery.mbt)、[cli/run.mbt](../cli/run.mbt)）：`changeset_commits` 收集改写为针对 `.changeset/` 目录的单次 `git log --diff-filter=A --name-only`；`status` 与 `publish-plan` 传入 `include_commits=false` 完全跳过提交历史查询。
2. **`git cat-file --batch` 分批预读与缓存**（[workspace/reader.mbt](../workspace/reader.mbt)、[workspace/discovery.mbt](../workspace/discovery.mbt)）：`Reader::prefetch(paths)` 按每批最多 200 个路径通过 stdin 喂给 `git cat-file --batch` 并按字节长度精确切片缓存至 `Reader.sources`，将 `status --since` 所需 `git` 子进程从 2100+ 次降至 ~12 次。

### 实测数据与冻结预算（2026-11-18，Windows `--release`）

| 测试项 | 指标 | 实测结果 | 冻结预算（`NFR-005`） |
|---|---|---|---|
| `moon bench engine --target native` (`nfr005-100u-1000cs`) | mean ± σ（10 × 4 runs） | `27.36 ms ± 223.74 µs`（min `26.97 ms`, max `27.69 ms`） | p50 `< 1 s` |
| `moonset status --output json`（100 包 / 1000 changesets） | 3 次中位数 | `411 ms`（样本 `[395, 411, 421]` ms） | p50 `< 5 s` |
| `moonset status --since main --output json`（同规模） | 3 次中位数 | `1494 ms`（样本 `[1487, 1494, 1499]` ms） | p50 `< 5 s` |
| `moonset status --since main --output markdown`（同规模） | 3 次中位数 | `1495 ms`（样本 `[1493, 1495, 1502]` ms） | p50 `< 5 s` |
