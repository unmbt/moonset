# ADR-009：向 Changesets v3 极简预发布与统一快照模型靠拢

- 状态：Accepted
- 日期：2026-11-20
- 关联：FR-005、FR-007、FR-008、FR-028、FR-029；补充 ADR-001、ADR-002

## 背景

`0.2.0` 的 `pre` 与 `snapshot` 实现存在两类根源性缺陷：

1. **双轨 `pre` 状态冗余与冲突**：`pre.json` 同时保存 `mode: "active" | "exit"`、`initialVersions`、`nextNumbers`、`consumed`，又把已消费 changeset 移入 `.changeset/pre/`；退出毕业时忽略 `initialVersions` 且硬编码 `"0.0.0"` 哨兵，导致跳号或 `0.0.0-alpha.0` 算错；更严重的是 `init` 与 `doctor --fix` 把 `pre.json` 写进 `.changeset/.gitignore`，导致自动提交在 `pre` 模式下必崩且与 CI 共享状态契约矛盾。
2. **事后补丁式 `snapshot` 断链**：`snapshot` 在 `build_plan` 之后才由 `build_version_plan` 覆写版本号，导致原本 in-range 的内部消费者既未被带入快照发布也未更新依赖范围，被更新的依赖也被改写成 `^0.0.0-snap-...` 而非精确锁定；且因跳过写入 `.moonset/release-state.json`，`moonset publish` 根本无法发布快照版本。

## 决策

1. **采用 Changesets v3 极简 `pre.json` 模型**：
   - 新写入的 `.changeset/pre.json` 仅包含 `{ "mode": "pre" | "exit", "tag": "<tag>" }`。
   - **单一消费事实源**：在 `mode: "pre"` 下，已消费 changeset 原子迁入 `pre.directory`（默认 `.changeset/pre`）；规划器仅消费尚未迁入隔离目录的 changeset；在 `mode: "exit"` 下合并读取两个目录的全部非 `ignore` changeset，毕业后原子清理两个目录的已消费文件与 `pre.json`，但**绝不删除 `ignore` 包专属 changeset**。
   - **预发布计数纯推导**：每个单元的下一个预发布序号直接从其当前清单版本解析（无预发布后缀为 `0`，已有 `.<n>` 则为 `n + 1`，`fixed`/`linked` 组取组内最大值），并复用标准 SemVer `inc` 规则自然支持 `pre` 推进与 `exit` 毕业。
   - **向后兼容旧版 `pre.json`**：`parse_pre_state` 读取旧版 `{ "mode": "active", "initialVersions", "nextNumbers", "consumed" }` 时自动映射为 `PreMode::Pre`（并保留 `legacy_consumed` 避免重复消费），产出迁移提示，下次 `version` 或 `pre exit` 写回纯净 v3 格式。
   - **Git 跟踪契约**：从 `init`、`doctor --fix` 与本仓库的 `.changeset/.gitignore` 中移除 `pre.json`。
2. **将 `snapshot` 并入纯规划器 `build_plan` 并打通发布闭环**：
   - `snapshot.enabled` 默认改为 `true`（显式设为 `false` 仍可禁用）；支持无 tag 的 `moonset version --snapshot` 及 `{tag}`/`{datetime}`/`{timestamp}`/`{commit}`/`{commit-short}`/`{version}` 占位符。
   - 禁止在 `Pre` 模式下执行 `--snapshot`。
   - `build_plan` 直接计算快照版本、自动带入越界内部消费者，并将内部依赖精确锁定为快照版本号。
   - `version --snapshot` 仍不消费稳定 changeset、不自动提交、不创建 Git tag，但写入标记 `isSnapshot: true` 的 `.moonset/release-state.json`，使 `moonset publish` 可安全发布快照版本（自动跳过打标）。
3. **补齐关键依赖策略对齐原版语义**：
   - npm `workspace:*` / `workspace:^` / `workspace:~` / `workspace:^1.0.0` 参与依赖传播与范围更新；外部非 SemVer 协议（`catalog:`、`npm:` 别名、`github:`、`git+`、`latest`、`""`）免于内部 SemVer 报错。
   - `peerDependencies` 越界（及默认未开启 `onlyUpdatePeerDependentsWhenOutOfRange` 时）将消费者升为 `Major`；`devDependencies` 与被跳过单元采用 `Bump::None` 仅更新依赖范围且豁免循环依赖报错。

## 后果

- 彻底消除 `pre` 双轨状态不一致、毕业跳号与自动提交崩溃。
- `version --snapshot` -> `publish` 形成完整端到端闭环，且符合 Changesets v3 行业直觉。
- `publish-state.json`、`version-journal.json` 与 `pack-results*.json` 继续保留在 `.moonset/.gitignore` 中作为本地瞬态恢复文件。
