# 未完成工作收口与性能优化记录

> 记录日期：2026-11-18  
> 关联需求：`FR-014`、`FR-015`、`FR-023`、`NFR-005`、`SEC-003`、`SEC-005`、`OPS-001`；关联审查：[SDD 符合性与代码审查报告](sdd-review.md)

---

## 1. 未完成工作收口清单

在将 PR Bot 从 GitHub App 切换为模块化 GitHub Action（[ADR-007](decisions/007-pr-bot-as-action.md)）的同时，对仓库内发现的存量缺陷、文档偏差与阶段遗留项进行了集中收口：

### 1.1 存量工作流与仓库卫生修复

| 事项 | 原问题 | 修复方式 | 位置 |
|---|---|---|---|
| 发布工作流确认门禁缺失 | `publish` 步骤未传 `--yes`，会被 `SEC-002` 门禁拦截返回退出码 `1`；另含与 PR Bot 重复的 `changeset-check` Job | 补齐 `--yes --no-tag`（由独立 `tag` Job 统一打标），移除旧 `changeset-check` | [.github/workflows/moonset-release.yml](../.github/workflows/moonset-release.yml) |
| 缺少跨平台预编译产物发布 | Action `setup` 需要随 tag 分发预编译二进制与校验文件 | 新增四目标构建矩阵（`ubuntu-22.04` / `ubuntu-22.04-arm` / `macos-15` / `windows-latest`）、冒烟测试与 `SHA256SUMS` 上传工作流 | [.github/workflows/release-binaries.yml](../.github/workflows/release-binaries.yml) |
| `README.md` 符号链接损坏 | 在 Windows（`core.symlinks=false`）下被追加普通文本，导致 Git index（`120000`）指向带额外文本的无效目标 | 重建纯 `README.mbt.md` 内容并以 `git update-index --cacheinfo 120000` 修复 | [README.md](../README.md) |
| 忽略规则缺失 | 本地参考目录 `/changesets/` 与运行期 `.moonset/version-journal.json` 未加入忽略规则 | 补充到忽略列表 | [.gitignore](../.gitignore) |
| 文档状态滞后 | `README.mbt.md`、`docs/README.md`、`docs/architecture.md`、`docs/decisions/006-mixed-workspaces.md` 仍标注“Phase 1 alpha / 尚未实现” | 同步为 Phase 1～5 核心能力、混合 workspace 与 PR Bot Action 的实际状态 | [README.mbt.md](../README.mbt.md)、[docs/README.md](README.md) |

### 1.2 `FR-023` 共存模式只读跨分区协调导出

- **实现位置**：[engine/coexistence.mbt](../engine/coexistence.mbt)、[engine/status.mbt](../engine/status.mbt)、[workspace/discovery.mbt](../workspace/discovery.mbt)
- **关键设计**：
  1. `workspace.discover` 在检测 `unmanaged` 清单时，同步识别非当前配置路径的外部 `.changeset/config.json`（以 `changeset-config:` 标记记入 `unmanaged`），但不解析或消费外部 `.changeset/*.md`。
  2. 新增纯函数 `coexistence_json(snapshot, changeset_directory~)`：在配置了 `mode: "coexist"` 或存在 `unmanaged` / 外部分区时，向 `status --output json` 向后兼容地附加 `coexistence` 字段（含 `mode`、`managedWorkspaces`、`unmanaged`、`foreignChangesetDirectories`、`changedUnowned` 与只读 `advice`）；普通单生态仓库保持返回 `None`，不改变既有 JSON 结构。
  3. 计算 `changedUnowned` 时排除已识别的 `unmanaged` 清单本身及其非根目录分区，避免对同一外部改动重复发出 `cross-partition-change` 与 `unowned-shared-change`。
- **验证测试**：[engine/coexistence_test.mbt](../engine/coexistence_test.mbt)、[workspace/integration_test.mbt](../workspace/integration_test.mbt)（MIX-004 扩展用例）。

### 1.3 仍保持 `Partial` / `Deferred` 或待线上验证的事项

| 事项 | 当前状态 | 说明 |
|---|---|---|
| `FR-022` 多平台二进制产物矩阵 | `Partial` | 单目标 `source` 打包、发布与内容摘要校验已实现；原生多平台二进制衍生包矩阵校验留待后续阶段 |
| 非 `crates.io` Cargo registry 与 Tauri | `Deferred` | Cargo 目前仅接入 `crates.io`；其他 Cargo registry 与 Tauri 同步明确延后 |
| 在线 GitHub Runner 演练 | 待线上触发 | 本机无 `actionlint` 与 `bash`，CI `rhysd/actionlint`、真实 Fork PR `pull_request_target` 触发及 `v*` tag 发布流程待推送到 GitHub 后验证 |

---

## 2. `NFR-005` 性能基准与子进程瓶颈优化

### 2.1 基准测试载体

为验证 **100 个包 + 1000 个 changeset** 规模下的性能指标，建立了两层可重复基准：

1. **纯计算核心基准（无 I/O）**：[engine/planner_bench_test.mbt](../engine/planner_bench_test.mbt)
   - 合成 100 个 MoonBit 单元（含链式依赖、扇出依赖与 2 个 `fixed` 组）与 1000 份 changeset 文本。
   - 测量 `parse_changeset` × 1000 + `build_plan` + `status_json` + `status_markdown` 全链路耗时，并配套等价正确性测试。
2. **CLI 端到端基准（真实 Git 仓库）**：[scripts/bench-status.mbtx](../scripts/bench-status.mbtx)
   - 在临时目录初始化包含 100 个成员的 `moon.work` 与 1000 个 `.changeset/cs-*.md` 文件及两条提交，编译 `--release` 二进制后预热 1 次、采样 3 轮取中位数，分别测量：
     - `moonset status --output json`
     - `moonset status --since main --output json`
     - `moonset status --since main --output markdown`

### 2.2 基准暴露出的性能瓶颈

初次运行 `scripts/bench-status.mbtx` 时，命令在 Windows 开发机上阻塞超过 10 分钟，定位到两处按资源数量线性放大的子进程开销：

1. **`changeset_commits` 逐文件执行 `git log`**：
   - [workspace/discovery.mbt](../workspace/discovery.mbt) 原逻辑对每个 changeset 文件单独启动 1～2 次 `git log --diff-filter=A -n 1 -- <path>`。在 1000 个 changeset 场景下，单次运行即触发 1000+ 次 `git` 子进程启动，而 `status` 与 `publish-plan` 根本不消费 `changeset_commits`。
2. **`--since` 模式下逐文件执行 `git show`**：
   - [workspace/reader.mbt](../workspace/reader.mbt) 的 `Reader::read` 对 `HEAD` 快照中每个文件单独调用一次 `git show <head>:<path>`，且未复用已读缓存。在 100 个包 + 1000 个 changeset 场景下，单次 `status --since` 需启动 1100+ 次 `git show` 进程。

### 2.3 优化措施

1. **批量 `git log` 与按需关闭（[workspace/discovery.mbt](../workspace/discovery.mbt)、[cli/run.mbt](../cli/run.mbt)）**：
   - 将 `changeset_commits` 收集改写为针对 `.changeset/` 目录执行**单次** `git log --diff-filter=A --name-only --format=__MOONSET_COMMIT__%H`（仅对少量未命中的重命名文件执行一次全量兜底扫描），将 O(N) 次子进程降为最多 1～2 次。
   - 为 `workspace.discover` 新增向后兼容的可选参数 `include_commits~ : Bool = true`；`cli/run.mbt` 中的 `status` 与 `publish-plan` 传入 `include_commits=false`，完全跳过提交历史查询。
2. **基于 `git cat-file --batch` 的分批预读与缓存（[workspace/reader.mbt](../workspace/reader.mbt)、[workspace/discovery.mbt](../workspace/discovery.mbt)）**：
   - 新增 `Reader::prefetch(paths)`：过滤 `reader.tree` 中确实存在且未缓存的普通文件（`100644`/`100755`），按每批最多 200 个路径通过 `@shell.Stdin::Text` 喂给 `git cat-file --batch`（`max_output_bytes=33554432`），按字节长度精确切片解码后写入 `Reader.sources`。
   - `Reader::read` 优先命中 `self.sources` 缓存；`discovery.mbt` 在读取成员 `moon.mod`、未受管探测文件、`CHANGELOG.md` 预加载与 changeset 文件前均先调用 `reader.prefetch(...)`。
   - 效果：100 个包 + 1000 个 changeset 的 `status --since` 所需 `git` 子进程从 2100+ 次降至 ~12 次。

### 2.4 实测数据与冻结预算

> 测试环境：Windows 本地开发机，`moon build --target native --release`（2026-11-18 实测）。

| 测试项 | 指标 | 实测结果 | 冻结预算（`NFR-005`） |
|---|---|---|---|
| `moon bench engine --target native` (`nfr005-100u-1000cs`) | mean ± σ（10 × 4 runs） | `27.36 ms ± 223.74 µs`（min `26.97 ms`, max `27.69 ms`） | p50 `< 1 s` |
| `moonset status --output json`（100 包 / 1000 changesets） | 3 次中位数 | `411 ms`（样本 `[395, 411, 421]` ms） | p50 `< 5 s` |
| `moonset status --since main --output json`（同规模） | 3 次中位数 | `1494 ms`（样本 `[1487, 1494, 1499]` ms） | p50 `< 5 s` |
| `moonset status --since main --output markdown`（同规模） | 3 次中位数 | `1495 ms`（样本 `[1493, 1495, 1502]` ms） | p50 `< 5 s` |

---

## 3. `0.1.0` 正式发版前收口（2026-11-19）

在进入 `0.1.0` 正式发版阶段前，围绕 Mooncakes 干净发布、CLI 版本单一事实源、普通用户安装体验与自举发布流完成了最后一批收口：

| 事项 | 原问题 | 修复与设计决策 | 位置 |
|---|---|---|---|
| 干净包发布传递依赖报错 | `mizchi/tui@0.10.2` 默认解析到旧格式 `mizchi/css@0.2.0`（含已废弃 `moon.mod.json`），导致 `moon publish --dry-run` 解压校验失败并依赖本地 Python 迁移脚本 | 在 [moon.mod](../moon.mod) 显式锁定新格式兼容传递依赖（`mizchi/css@0.7.4`、`moonbitlang/async@0.22.5` 等），删除临时迁移脚本与 CI 重试循环 | [moon.mod](../moon.mod)、[.github/workflows/ci.yml](../.github/workflows/ci.yml) |
| CLI 版本号硬编码与缺少 `-V` | [cli/run.mbt](../cli/run.mbt) 硬编码 `"moonset 0.1.0-alpha.1"` 且未支持 `-V` | 通过 [cli/moon.pkg](../cli/moon.pkg) 的 `:embed` + `dev_build` 规则将 [moon.mod](../moon.mod) 编译期嵌入 [cli/embedded_version.mbt](../cli/embedded_version.mbt)，由 `@manifest.parse` 读取统一版本并支持 `-V`/`--version` | [cli/moon.pkg](../cli/moon.pkg)、[cli/arguments.mbt](../cli/arguments.mbt)、[cli/run.mbt](../cli/run.mbt) |
| Mooncakes 已发布幂等查询与发布后 `tag` 冲突 | `moonbit` 生态 `registry_lookup` 固定返回 `"absent"`；`publish` 写入的 `.moonset/publish-state.json` 会使紧随其后的 `tag` 判定工作树脏 | 接入 `moon view <name>@<version> --json` 预检及 `409 Conflict` 识别；在 [executor/host.mbt](../executor/host.mbt) 过滤 `.moonset/publish-state.json` / `pack-results.json` / `version-journal.json` 并补充 `.gitignore` | [executor/publish.mbt](../executor/publish.mbt)、[executor/tag.mbt](../executor/tag.mbt)、[.gitignore](../.gitignore) |
| 普通用户安装方式与 CI Action 解耦 | 仅有依赖 `gh` 与 `$RUNNER_TOOL_CACHE` 的 [setup/install.sh](../setup/install.sh)，缺少普通开发者安装脚本 | 参考 [moon-bump](https://github.com/unmbt/moon-bump) 新增零 `gh` 依赖的 [scripts/install.sh](../scripts/install.sh) 与 [scripts/install.ps1](../scripts/install.ps1)（安装至 `~/.unmbt` 并校验 `SHA256SUMS`），保持 `setup/install.sh` 专供 GitHub Actions | [scripts/install.sh](../scripts/install.sh)、[scripts/install.ps1](../scripts/install.ps1)、[README.mbt.md](../README.mbt.md) |
| 自举 `0.1.0` 发布与凭证挂载 | 缺少根 `.changeset/config.json`，且根 `action.yml` 未挂载 `~/.moon/credentials.json`，`GITHUB_TOKEN` 打 tag 不自动触发二进制工作流 | 补齐 `.changeset/config.json` 与 Phase 6 changeset；为 `action.yml` 增加 `mooncakes-credentials` 输入；将 `.github/workflows/moonset-release.yml` 升级为 `version-pr -> publish -> release-binaries`（`workflow_call`）自举流水线 | [.changeset/config.json](../.changeset/config.json)、[action.yml](../action.yml)、[.github/workflows/moonset-release.yml](../.github/workflows/moonset-release.yml) |
| 文档残留本地磁盘路径 | [docs/references.md](references.md) 残留本地文件路径与外部相对链接 | 全部替换为 GitHub 上游仓库 URL | [docs/references.md](references.md) |
