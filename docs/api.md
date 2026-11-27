# 编程 API

> API 目标：让 MoonBit 库、CI action 和外部工具复用同一个模型与 planner。所有公开声明均以各包生成的 `pkg.generated.mbti` 为准。

稳定原生入口位于 `unmbt/moonset/api`，由根包 `unmbt/moonset` 对等重导出；纯核无 I/O 双目标（`native` + `wasm-gc`）入口位于 `unmbt/moonset/core`。公共 API 当前遵循 [ADR-008](decisions/008-v030-api-and-adapter-convergence.md) 收敛至 **`api_version = "2.0.0"`**，所有公开函数签名涉及的类型均从门面完整重导出。

```text
core / api / root:
  parse_config(source, path?) -> Config
  parse_changeset(source, id~, path~, mixed?, in_pre_dir?) -> Changeset
  parse_pre_state(source, path?) -> PreState
  build_plan(snapshot, changesets, pre?, generated_at?, snapshot_mode?, snapshot_tag?, timestamp_ms?) -> ReleasePlan
  build_version_plan_with_metadata(snapshot, analysis, options, ...) -> VersionPlan
  status_json(snapshot, plan, changeset_directory?) -> Json
  status_markdown(snapshot, plan, options?) -> String
  render_with_line_hooks(context, hooks) -> String

api / root (native):
  discover(cwd, config_path?, since?, include_commits?) -> LoadedWorkspace         // async
  apply_version_plan_with(host, root, plan, keep_journal?) -> ApplyResult          // async
  finalize_version_journal_with(host, root) -> Unit                                // async
  format_files_with(host, root, config, paths, no_format?) -> FormatResult         // async
  pack_artifacts_with(host, loaded, options) -> Array[PackResult]                  // async
  publish_release_with(host, loaded, options) -> PublishResult                     // async
  create_tags_with(host, loaded, options) -> TagResult                             // async
  run_doctor_with(host, cwd, config_path?, loaded?, check_registry?, fix?) -> DoctorReport // async
```

纯函数使用 `MoonsetError` 报告输入错误；I/O 层使用 `ExecutionHost` 注入宿主文件、进程、环境变量与时钟能力。`PublishOptions::new()`、`PackOptions::new()`、`TagOptions::new()`、`VersionOptions::default()` 采用带默认值的关键字构造器，避免函数签名组合爆炸。

## 1. 公共包

| 包 | 责任 | 支持目标 | 稳定性 |
|---|---|---|---|
| `@moonset/core` | 纯核统一门面（重导出 `model` + `engine` + `changelog`） | `native` + `wasm-gc` | v2.0 |
| `@moonset/api` / `@moonset` | 完整对等原生门面与 `api_version = "2.0.0"` | `native` | v2.0 |
| `@moonset/model` | 强类型枚举、嵌套 `Config`、领域类型与统一 `ReleaseState` 编解码 | `native` + `wasm-gc` | v2.0 |
| `@moonset/engine` | 纯规划器、Changesets v3 `pre`/统一 `snapshot`、SemVer/Glob/Markdown 渲染 | `native` + `wasm-gc` | v2.0 |
| `@moonset/changelog` | 内置生成器、`ChangelogGenerator`、`ChangelogLineHooks`、registry、release-notes 提取 | `native` + `wasm-gc` | v2.0 |
| `@moonset/adapters` | 能力契约、JSONL 进程插件协议、`PublisherRegistry`、`PublisherPort`/`RegistryHost` | `native` | v2.0 |
| `@moonset/executor` | `ExecutionHost`、异步生态驱动（MoonBit/npm/pnpm/yarn/Cargo）、journal、staging、pack、publish、tag、doctor | `native` | v2.0 |

CLI 通过 `@workspace.discover` 读取输入，再调用同一个 `@engine` planner 与 `@executor` 执行层，不复制规划逻辑。

## 2. 宿主抽象与可扩展接口

- **`ExecutionHost`（`@moonset/executor`）**：集中封装文件系统（`exists`/`is_dir`/`readdir`/`read_text`/`read_binary`/`write_text`/`write_binary`/`mkdir`/`remove`/`rename`/`tmpdir`/`rmdir`）、参数化子进程执行（`run`/`run_with_env`，均内置超时保护与硬取消）、环境变量（`getenv`）与时钟/休眠（`now`/`sleep_ms`）。默认实现为 `NativeHost`（`native_host()`）；单测与嵌入方均可替换为内存实现。
- **`ApiPublisher` / `ApiPublisherRegistry` / `PublisherPort` / `RegistryHost`**：支持按自定义发布器名、规范 `UnitId`、生态名或全局 `"default"`/`"api"` 路由注册表查重（`already_published`）、预检（`preflight`）与发布（`publish`）。
- **`ChangelogGenerator` / `ChangelogLineHooks` / `GeneratorRegistry`**：支持编译期纯函数生成器注册，以及兼容原版 Changesets 的行级钩子（`get_release_line` / `get_dependency_release_line`）。
- **`AdapterRegistry`**：管理 `MoonBit` / `Npm` / `Cargo` 的能力矩阵与契约校验（`validate_conformance`）。

## 3. 版本与兼容性策略

- `model` 结构体只增量追加字段或通过默认构造函数兼容演进；破坏性变更升级 `api_version` 主版本号。
- `ReleasePlan` / `ReleaseState` / `PublishResult` 的 `schemaVersion` 独立于 CLI 版本号维护。
- 所有公开声明由 `moon info` 固化在各包 `pkg.generated.mbti` 并受 CI 门禁校验。

## 4. API 安全边界

- 核心 API 与执行器不接收原始 shell 字符串、不输出凭据、不允许纯规划器或 generator 直接写文件。
- JSONL 插件运行器（`adapters.run_jsonl`）与 `command` publisher 均支持宿主机环境变量白名单 `MOONSET_ALLOWED_PLUGIN_PROGRAMS`（逗号分隔）；设置后强制覆盖配置白名单，拒绝任何未登记的可执行程序。
- 纯计算与规划逻辑全部收敛在 `model` / `engine` / `changelog` / `core`，可在 `wasm-gc` 沙箱环境中无宿主 I/O 直接复用。
