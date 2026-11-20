# ADR-008：v0.3.0 公共 API、Adapter 与轻量原生 TUI 收敛

- 状态：Accepted
- 日期：2026-11-20
- 关联：FR-016、FR-024、FR-031；演进替代 ADR-005 中 v1 实验性 adapter 草案边界

## 背景

在 `0.1.0`～`0.2.0` 期间，为了保持 `pub(all) struct` 零破坏，仓库出现了四类显著架构债务：

1. **扁平 `Config` 与 `Config.raw` 双事实源**：`model.Config` 膨胀为 40 字段扁平结构体，新特性（`snapshot`、`artifacts`、`mixedWorkspaces.mode`）被迫绕过强类型字段，在规划期反复从 `Config.raw : Json` 解析，导致代码构造的 `Config` 行为静默漂移；同时 `ecosystem`、`manager`、`visibility`、`PreState.mode` 等有限域均为裸字符串，造成 MoonBit `"restricted"` 与 `"private"` 校验脱节。
2. **选项结构僵化引发的函数组合爆炸**：`PublishOptions`/`PackOptions` 无法增字段，导致 `executor` 派生出 6 个 `publish_release*` 与 4 个 `pack_artifacts*`；`moonset.mbt` 与 `api/api.mbt` 双门面漂移，且两者均漏导出 `Config`/`PublishResult`/`Bump`/`Release` 等签名必需类型。
3. **空壳同步 Adapter Trait 与纯核解析污染**：`adapters/protocol.mbt` 定义的 10 个同步 `fn` Port/Trait 零实现、零调用（与异步宿主签名冲突），真实逻辑退化为散落全库的 `if ecosystem == ...` 硬编码；`ReleaseUnit` 缺少 `version_span` 迫使纯核 `engine/version_plan.mbt` 直接依赖 `@manifest` 并重复手写 JSON/TOML 扫描器。
4. **第三方 TUI 导致中文 Windows 乱码与依赖膨胀**：`mizchi/tui` 在 `tui_native.c` 中直接用 `WriteFile` 往 CP936 控制台输出 UTF-8（未切 `CP_UTF8`、未用 `WriteConsoleW`）且用 `_getch()` 读 GBK 字节按 UTF-8 解码，造成中文系统乱码、IME 失效、100% CPU 非阻塞忙等，并拖入 6 个 CSS/Layout 重型依赖。

## 决策

在 `v0.3.0`（`api_version = "2.0.0"`）完成一次收敛性整理：

1. **强类型模型与结构化配置**：
   - 将 `Config` 收敛为嵌套子配置结构（`ChangelogConfig`、`CommitConfig`、`PrivatePackagesConfig`、`PreConfig`、`SnapshotConfig`、`TagConfig`、`PublisherConfig`、`GithubConfig`、`MixedWorkspacesConfig`），消除 `Config.raw` 旁路解析。
   - 引入强类型枚举 `Ecosystem`、`PackageManager`、`Visibility`、`PreMode`、`UpdateDependents`、`Access`、`CommitMode`、`LockfileMode`、`BridgeWaitFor`、`TextSpan`。
   - `ReleaseUnit` 携带 `version_span : TextSpan?` 与 `publish_config : PublishConfig?`；`DependencyIntent` 携带 `kind : DependencyKind` 与 `producer_version : String`；`model` 提供唯一 `ReleaseState::from_json` 编解码器。
   - `engine/` 移除 `@manifest` 依赖及所有手写 JSON/TOML 字节扫描器，保持纯计算边界纯净。
2. **真实异步 Adapter 与 Builder 选项**：
   - 删除 `adapters/protocol.mbt` 中 10 个零实现同步空壳 Trait/Struct（`FileHost`、`ProcessHost`、`DiscoveryPort`、`RangePort`、`OwnershipPort`、`LockfilePort`、`ArtifactPort`、`OperationalAdapter`、`EcosystemAdapter`、`ArtifactProvider`）。
   - 保留并加固 `Capability`、`CapabilityReport`、`AdapterRegistry`、`PublisherPort`、`RegistryHost`、`PluginSpec`、`PublisherRegistry`、`JsonlRequest`/`JsonlResponse`，在 `executor/` 落地真实异步 `EcosystemDriver`（MoonBit、npm/pnpm、Cargo）。
   - 将 `PublishOptions`/`PackOptions`/`TagOptions`/`VersionOptions` 改为带默认构造与链式 setter 的结构体；合并 6 个 `publish_release*` 为 `publish_release`/`publish_release_with`，合并 4 个 `pack_artifacts*` 为 `pack_artifacts`/`pack_artifacts_with`；隐藏 `executor` 内部路径/工具函数。
   - 同步对齐 `moonset.mbt` 与 `api/api.mbt` 重导出列表，确保所有导出函数签名中的类型均可从门面直接引用。
3. **自研轻量原生 TUI 驱动**：
   - 卸载 `mizchi/tui` 及关联 6 个 CSS/Layout 传递依赖，在 `cli/` 内通过 MoonBit `native-stub`（`cli/tty_native.c`）实现 ~220 行零第三方依赖终端驱动：Windows 采用 `SetConsoleCP/OutputCP(CP_UTF8)` + `WriteConsoleW` + 阻塞式 `ReadConsoleInputW`（彻底根治中文显示/IME 乱码与 CPU 忙等），POSIX 保留 `OPOST` 与阻塞 `read()` + 20ms `select()` 转义消歧；完整保留并升级原版 Changesets 风格交互式 TUI。

## 原因

- `0.x` 阶段进行一次性收敛远比在历史补丁上继续叠加 `*_with_v2` 成本更低、长期可维护性更高。
- 面向 MoonBit 为主、npm/Cargo 为辅的定位，自包含 TOML 解析器 + 轻量原生 TUI C stub 使二进制更小、跨平台行为 100% 可控。

## 后果

- `api_version` 升级至 `"2.0.0"`，外部 MoonBit API 消费方需按 `pkg.generated.mbti` 迁移至结构化 `Config` 与新 `Options` 构造器；`fixtures/external-moonbit-api` 同步升级为全量签名回归测试。
- 面向 CLI 用户与 `.changeset/config.json` 配置保持高向后兼容性（见 ADR-009 迁移策略）。
