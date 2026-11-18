# 参考实现与依赖评估

本文件记录 `moonset` 在架构设计阶段对相关上游与同组织项目的调研评估与取舍。它是设计输入，不等于对外部包未来 API 的承诺。

## 1. 相关参考项目

| 项目 | 上游仓库 | 可复用内容 | moonset 取舍 |
|---|---|---|---|
| `moon-bump` | <https://github.com/unmbt/moon-bump> | 版本计算、配置优先级、Git 生命周期、跨平台安装脚本（`~/.unmbt`）与错误恢复思路；使用 `mizchi/semver`、`moonbitlang/async`、`moon-manifest`。 | 复用纯算法、安装脚本结构与 CI 发布经验；不直接依赖其 CLI 内部包。SemVer API 在接入前用 `moon ide doc` 验证，异步 I/O 收敛至 `moonbitlang/core/async`。 |
| `moon-manifest` | <https://github.com/unmbt/moon-manifest> | `Kind::Mod/Pkg/Work`、`Document::module_name/version/members/dependency_version`、`find_string` 和无损 `replace_string`；解析委托 `moonbitlang/moon_config`。 | 作为 MoonBit manifest adapter 的直接依赖（当前锁定 `unmbt/moon-manifest@0.2.0-alpha.2`）。 |
| `native-toolchain` | <https://github.com/unmbt/native-toolchain> | `Toolchain`、Windows/POSIX 工具发现、`MOON_CC/MOON_LINK/MOON_AR/MOON_NM` 覆盖和诊断。 | 只在外部构建插件或需要显式编译器发现的扩展场景按需使用，不让发布主流程依赖本机 C 工具。 |
| `changesets` | <https://github.com/changesets/changesets> | Changesets v3 的 docs、parser、release plan、pre state、changelog 和 GitHub automation 行为参考。 | 保留 changeset Markdown/front matter、`fixed`/`linked`/`pre` 的用户心智模型；不复制 npm `package.json` 占位语义与 Node 动态插件模型。 |

## 2. 当前工具链验证

已运行验证以下命令的精确输出与签名：

```text
moon version --all
moon ide doc '@async' --no-registry
moon ide doc '@fs' --no-registry
moon ide doc '@process' --no-registry
moon ide doc '@shell' --no-registry
moon publish --help
moon package --help
moon view --help
```

确认：

- `@async` 对应 `moonbitlang/core/async`，可用 `all`、`with_timeout`、`TaskGroup`、`sleep` 等 API。
- 文件 API 在 `moonbitlang/core/async/fs`，包含 `read_text`、`write_text`、`rename`、`walk`。
- 进程 API 在 `moonbitlang/core/async/process`，shell API 在 `moonbitlang/core/async/shell`，均提供参数数组和结构化结果。
- 当前 `moon publish` 发布当前 module，支持 `--dry-run`；`moon package` 生成当前 module 的包归档；`moon view <module@version> --json` 可查询 Mooncakes 远端已发布版本状态。

这些命令是精确 API 的验证来源；实现时始终在 `moonset` 的 [moon.mod](../moon.mod) 中显式锁定兼容依赖版本，确保 `moon check --target native --deny-warn` 与 `moon publish --dry-run` 在干净环境直接通过。

## 3. 依赖分层

1. **必须**：MoonBit core、JSON、字符串/数组、Git adapter 所需的 `core/async`。
2. **核心**：已发布的 `unmbt/moon-manifest` 与 `mizchi/semver`。
3. **可选**：`mizchi/tui`（交互式 `add`）、`native-toolchain` 与第三方扩展；核心规划器保持无平台依赖。

不把依赖版本写进规格的行为语义；升级时在 ADR 中记录 API 差异和测试结果。

## 4. 混合生态与外部分发参考

- 同目录同时存在 `package.json` 与 `moon.mod` 的原生绑定项目（如 `napi-mbt` 模式）表明：同目录双清单不能自动等同于同一版本权威，且存在平台二进制子包与 `optionalDependencies` 分发需求。
- [Changesets Beyond npm](https://github.com/changesets/changesets/blob/main/docs/beyond-npm.md) 仍常借助占位 `package.json` 管理版本；`moonset` 的混合 workspace 设计直接支持各生态原生清单（`moon.mod`、`package.json`、`Cargo.toml`），并保留独立字段所有权。
- 面向普通用户的本地安装脚本（[install.sh](../scripts/install.sh) 与 [install.ps1](../scripts/install.ps1)）参考了 [moon-bump](https://github.com/unmbt/moon-bump) 的 `~/.unmbt` 分发约定，并额外强制执行 `SHA256SUMS` 校验，与专用于 GitHub Actions 的 [setup/install.sh](../setup/install.sh) 保持解耦。
