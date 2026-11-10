# 参考实现与依赖评估

本文件记录 2026-11-10 在 `E:\project\moonbit\unmbt` 的本地检查结果。它是设计输入，不等于对外部包未来 API 的承诺。

## 1. 本地项目

| 项目 | 可复用内容 | moonset 取舍 |
|---|---|---|
| `moon-bump` | 版本计算、配置优先级、Git 生命周期、native CLI 文档和错误恢复思路；当前依赖 `mizchi/semver@0.1.2`、`moonbitlang/async@0.22.1`、`moonbitlang/x@0.5.5` 等。 | 复用概念和纯算法测试；不直接依赖其 CLI 内部包。SemVer API 在接入前用 `moon ide doc` 验证，异步依赖迁移到 core。 |
| `moon-manifest` | `Kind::Mod/Pkg/Work`、`Document::module_name/version/members/dependency_version`、`find_string` 和无损 `replace_string`；解析委托 `moonbitlang/moon_config`。 | 作为 manifest adapter 的首选依赖。等待它发布使用 `core/async` 的版本；必要时短期 vendoring 并保持相同 facade。 |
| `native-toolchain` | `Toolchain`、Windows/POSIX 工具发现、`MOON_CC/MOON_LINK/MOON_AR/MOON_NM` 覆盖和诊断。 | 只在 `doctor`、构建插件或需要编译器发现的场景使用，不让发布主流程依赖本机 C 工具。 |
| `moonset/changesets` | Changesets v3 的 docs、parser、release plan、pre state、changelog 和 GitHub automation 行为参考。 | 保留 changeset Markdown/front matter、fixed/linked/pre 的用户心智模型；不复制 npm package.json、Node 动态加载和 registry 语义。 |

## 2. 当前工具链验证

已运行：

```text
moon version --all
moon ide doc '@async' --no-registry
moon ide doc '@fs' --no-registry
moon ide doc '@process' --no-registry
moon ide doc '@shell' --no-registry
moon publish --help
moon package --help
```

确认：

- `@async` 对应 `moonbitlang/core/async`，可用 `all`、`with_timeout`、`TaskGroup`、`sleep` 等 API。
- 文件 API 在 `moonbitlang/core/async/fs`，包含 `read_text`、`write_text`、`rename`、`walk`。
- 进程 API 在 `moonbitlang/core/async/process`，shell API 在 `moonbitlang/core/async/shell`，均提供参数数组和结构化结果。
- 当前 `moon publish` 发布当前 module，支持 `--dry-run`；`moon package` 生成当前 module 的包归档。

这些命令是精确 API 的验证来源；实现时仍需在 moonset 的 `moon.mod` 中锁定实际依赖版本并运行 `moon check --target native`。

## 3. 依赖分层

1. **必须**：MoonBit core、JSON、字符串/数组、Git adapter 所需的 `core/async`。
2. **优先**：已发布的 `unmbt/moon-manifest`。
3. **候选**：SemVer 包、glob/Markdown/YAML 解析器、GitHub HTTP 客户端；必须先用 `moon add` 或 registry 文档确认可用版本。
4. **可选**：`native-toolchain`、TUI 和彩色输出；核心在无 TTY 环境仍可工作。

不把依赖版本写进规格的行为语义；升级时在 ADR 中记录 API 差异和测试结果。

## 4. 需要在实现前确认的事项

- `moon-manifest` 的下一个发布版本是否已切换全部文件 I/O 到 `moonbitlang/core/async/fs`。
- 当前 MoonBit 工具链对 YAML 的可用包和错误位置；若没有稳定 YAML 依赖，使用受限 front matter parser。
- SemVer、glob、GitHub API 客户端的 native 支持及许可证。
- Mooncakes registry 是否提供 OIDC、already-published 查询和 scoped/tag 语义。
- GitHub App 的部署位置、签名验证和持久化策略。

## 5. 混合仓库补充调查（2026-11-10）

- [napi-mbt/package.json](../../napi-mbt/package.json) 与 [moon.mod](../../napi-mbt/moon.mod)：前者 `napi-mbt@0.2.1` 且 private，后者 `unmbt/napi-mbt@0.3.7`。这证明同目录双清单不能自动等同于同一版本权威。
- [test-napi-mbt/package.json](../../test-napi-mbt/package.json) 与 [moon.mod](../../test-napi-mbt/moon.mod)：同目录 MoonBit 源码与 npm 包装层，可作为第一批混合 fixture 的来源。
- [napi-mbt README](../../napi-mbt/README.md) 描述平台二进制包及 optionalDependencies 分发，提示计划需要包含派生产物与构建矩阵。这是本地文档证据，不代表已验证其全部发布实现。
- [Changesets Beyond npm](../changesets/site/guide/beyond-npm.md) 仍以 `package.json` 管理版本；moonset 的混合设计直接支持各生态原生清单，不能仅复制其占位 package.json 方案。
- napi-rs/Tauri 用作原生绑定与桌面产品的结构示例；本次未验证它们的具体 CLI/API，也未承诺 Cargo/Tauri adapter 已实现。

上述相邻仓库和 Changesets checkout 链接用于本地研究，不是 moonset 运行依赖；独立 clone 后可通过对应上游获取参考材料。
