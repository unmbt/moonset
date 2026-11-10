# 需求规格

> 状态：Draft 0.1。需求已按 SDD 编号，第一阶段实现前需将相关条目改为 Accepted。

## 1. 问题与目标

MoonBit workspace 可以包含多个 `moon.mod`、`moon.pkg` 和 `moon.work`，但现有版本修改、变更记录、发布和 Git 标签流程分散在人工脚本中。moonset 要把“贡献者记录变更意图”和“维护者生成可审阅发布计划”连接起来，同时保留 MoonBit 清单的格式和注释。

目标：

- 让每个需要发布的改动以可审阅的 changeset 文件进入 Git。
- 从 workspace 依赖图计算确定性的版本和 changelog 变更。
- 支持稳定版、预发布版、快照版和多包协同发布。
- 让本地命令、GitHub Actions、GitHub App 和 MoonBit 编程 API 使用同一套核心规划器。
- 让注册表发布和 Git 操作可替换、可模拟、可重试。
- 支持 MoonBit 与 npm/pnpm workspace 分区共存，并分阶段支持统一发布；架构从第一阶段纳入跨生态身份、清单所有权和构建依赖。详见 [混合 workspace 设计](mixed-workspaces.md)。

## 2. 非目标

- 不实现 Mooncakes 注册表或 GitHub App 的托管服务。
- 不替代 `moon` 编译器、依赖解析器和包发布权限系统。
- 不默认修改没有 release 的包版本。
- 不在核心库中执行任意 shell 字符串；外部命令必须通过参数数组或明确的插件协议调用。
- 不把 Changesets 的 Node.js 包加载模型直接搬进 MoonBit；自定义生成器使用编译期 API 或受限进程协议。

## 3. 用户与使用场景

| 角色 | 场景 | 主要入口 |
|---|---|---|
| 贡献者 | 说明一个 PR 需要发布哪些包以及变更级别 | `moonset add` |
| 维护者 | 检查待发布内容和依赖联动 | `moonset status`、`publish-plan` |
| 发布负责人 | 生成版本、更新 changelog、提交审阅 | `moonset version` |
| CI | 在合并后发布 Mooncakes 并创建标签 | `publish`、`tag` |
| GitHub App | 对缺少 changeset 的 PR 提示或加标签 | `status --since` + webhook |
| MoonBit 集成作者 | 复用解析、规划、生成或发布能力 | `@moonset/*` API |

## 4. 功能需求

| ID | 需求 | 验收条件 | 状态 |
|---|---|---|---|
| FR-001 | 初始化 | `init` 创建 `.changeset/`、默认 `config.json` 和 README；重复运行不覆盖用户文件，并给出可机器读取结果。 | Proposed |
| FR-002 | 记录变更 | `add` 支持交互式和非交互式输入，生成唯一 Markdown changeset；支持 `major/minor/patch/none`，禁止未知包名和空摘要（除非显式 `--empty`）。 | Proposed |
| FR-003 | 发现 workspace | 按 release domain 发现已授权的 workspace；MoonBit adapter 读取 `moon.work` 成员和单模块项目，输出稳定排序的 ReleaseUnit，区分编译包和发布模块。 | Implemented (MoonBit) |
| FR-004 | 解析 changeset | 解析平面 YAML front matter 子集和 Markdown 摘要，报告文件路径、行号、包名和版本类型；任何一个文件无效时规划失败且不写盘。 | Implemented |
| FR-005 | 生成 release plan | 合并 changeset、fixed/linked 组、内部依赖和预发布状态，输出 old/new version、原因和受影响文件；同样输入必须得到同样计划。 | Implemented (analysis) |
| FR-006 | 查看状态 | `status` 显示待处理 changeset、预计版本、缺失 changeset 和配置错误；支持 `--since`、`--verbose`、`--output json`。 | Implemented |
| FR-007 | 应用版本 | `version` 原子更新 `moon.mod`、相关依赖范围、各包 `CHANGELOG.md`，消费已应用 changeset，并保留可审阅 diff。 | Proposed |
| FR-008 | 预发布 | `pre enter <tag>`、`pre exit` 管理 `.changeset/pre.json`；重复进入、错误退出和标签非法时给出明确错误。 | Proposed |
| FR-009 | 发布 | `publish` 只发布计划中有新版本且允许发布的模块，支持 `--dry-run`、自定义 registry/publisher 和失败重试；默认不自动执行 `version`。 | Proposed |
| FR-010 | 标签 | `tag` 根据当前版本创建确定性 Git 标签，支持单模块 `vX.Y.Z` 与 workspace `name@X.Y.Z`，支持预览和可选推送。 | Proposed |
| FR-011 | 打包与计划 | `pack` 调用 MoonBit 打包流程；`publish-plan` 输出不改盘的发布 JSON，供 CI 和外部工具消费。 | Proposed |
| FR-012 | 配置 | `.changeset/config.json` 支持版本策略、fixed/linked、ignore、私有包、changelog、tag、publisher、GitHub 和格式化器；未知顶层字段默认报错。 | Proposed |
| FR-013 | 自定义 changelog | 内置生成器覆盖纯文本、Git、GitHub 三类；MoonBit API 和受限 JSONL 进程协议都能提供自定义 release line。 | Proposed |
| FR-014 | GitHub Action | 提供 PR 检查、版本 PR/提交、发布和标签四种可组合 job 的参考工作流；权限最小化，并支持 OIDC 或显式令牌。 | Proposed |
| FR-015 | GitHub App | 定义 webhook、去重、评论和标签策略；机器人默认只读检查和评论，不直接改版本或发布。 | Proposed |
| FR-016 | 编程 API | 核心模型、解析器、规划器、执行器和适配器接口有稳定的 MoonBit 公共包；I/O 通过注入接口可测试。 | Proposed |
| FR-017 | 环境诊断 | `doctor` 只读检查 MoonBit、Git、workspace、配置、publisher 和必要权限，输出可修复建议。 | Proposed |
| FR-018 | 混合 workspace 与所有权 | 同级、嵌套、同目录双清单均可表达；按声明发现 npm/pnpm 与 MoonBit 成员；工具清单、生成目录、嵌套仓库不被默认接管；重复所有权在写入前报错。 | Proposed |
| FR-019 | 跨生态身份 | 使用生态前缀 UnitId；同名跨生态单元可区分；混合 changeset、选择器、pre 状态和计划使用相同 ID；旧记录迁移提供可审阅映射。 | Proposed |
| FR-020 | 跨生态依赖与版本组 | 包依赖、build bridge 和 fixed/linked 分开；bridge 提升 consumer 的最低 bump 并进入闭包；环与不完整 `--only` 选择在写入前失败。 | Proposed |
| FR-021 | 原生清单和锁文件 | adapter 保留依赖种类、协议、版本继承及发布禁令；用固定包管理器在 staging 校验/更新锁文件；不得用通用文本替换重写 `workspace:`。 | Proposed |
| FR-022 | 构建产物与多目标发布 | 计划声明 JS 主包、平台包及其他 artifact；先验证产物再按图发布；分别记录每个 registry 结果，失败重试不重复已确认的发布、不自动撤销成功版本。 | Proposed |
| FR-023 | 与已有工具共存 | Changesets 等工具和 moonset 分区管理，changeset/版本字段/锁文件只有一个写入者；不互相消费记录或静默迁移配置；跨分区关系只读导出。 | Proposed |
| FR-024 | Adapter 能力契约 | 接口涵盖 discovery、编辑、range、lockfile、pack 和 publish；未知能力在 apply 前明确失败；Cargo/Tauri 作为后续适配，不宣称已支持。 | Proposed |

## 5. 非功能需求

| ID | 需求 | 验收条件 | 状态 |
|---|---|---|---|
| NFR-001 | 跨平台 | Windows、Linux、macOS native 构建；Git 和路径处理不依赖 POSIX shell。 | Proposed |
| NFR-002 | 确定性 | 相同 Git 树、时间输入和配置产生相同计划；发布时间由 `Clock` 注入，默认使用 UTC。 | Proposed |
| NFR-003 | 可恢复 | 文件替换、Git 标签和发布步骤有阶段状态；失败结果包含已完成步骤和下一条恢复命令。 | Proposed |
| NFR-004 | 可观测 | 人类输出可读；`--json` 使用版本化 schema，日志不泄露 token。 | Proposed |
| NFR-005 | 性能 | 100 个包、1000 个 changeset 的 `status` 和规划在普通开发机上完成；具体预算在基准测试后冻结。 | Proposed |
| NFR-006 | 兼容性 | 只使用当前 MoonBit 工具链验证过的 API；依赖升级必须记录 ADR 和回归结果。 | Proposed |

## 6. 安全需求

| ID | 需求 | 验收条件 | 状态 |
|---|---|---|---|
| SEC-001 | 命令注入防护 | Git、Moon 和 publisher 命令使用可执行文件加参数数组；插件命令明确显示并可禁用。 | Proposed |
| SEC-002 | 发布确认 | 真实发布前显示 registry、包、版本、访问级别和标签；CI 必须显式设置非交互模式。 | Proposed |
| SEC-003 | 最小权限 | GitHub Action/App 文档只申请必须的 contents、pull-requests、issues 权限；发布 token 不进入日志。 | Proposed |
| SEC-004 | 工作区安全 | 默认拒绝脏工作树、未跟踪 `.changeset` 和发布中间状态；绕过必须是显式 flag 且记录。 | Proposed |

## 7. 退出码契约

- `0`：成功，包含没有待发布变更的成功查询。
- `1`：可修复的用户或策略问题，例如缺少 changeset、验证失败或需要确认。
- `2`：配置、changeset 或 workspace 无效。
- `3`：外部工具、Git、网络或注册表失败；结果包含恢复提示。

## 8. 验收场景

1. 单模块项目添加一个 patch changeset，`status --output json` 能看到预计版本，`version` 只修改该模块和 changelog。
2. 两个互相依赖的模块中只修改被依赖者，规划器按配置判断是否提升依赖者并更新范围。
3. fixed 组中一个包有 major changeset，组内全部包得到同一目标版本。
4. 预发布模式进入 `next` 后连续两次版本，序号单调递增；退出后下一次稳定版不带预发布后缀。
5. 一个 changeset front matter 损坏时，`version` 不改任何 manifest/changelog。
6. `publish --dry-run` 调用 publisher 的验证路径但不创建注册表版本或 Git 标签。
7. GitHub PR 没有 changeset 时，App 能幂等地评论一次并添加标签；添加 changeset 后评论被更新或关闭。
8. 自定义生成器超时或输出非法 JSON 时，发布计划失败且不写入 changelog。
9. 一个目录内 `moon.mod` 与 `package.json` 版本不同，只配置 MoonBit 分区时，JS 版本和锁文件保持原状。
10. 统一配置下 MoonBit producer 升级触发 npm consumer 的 patch bridge；npm `private: true` 始终禁止发布，即使可以更新其版本。
11. 平台包成功发布但 JS 主包失败时，保留成功凭据并仅重试主包；不创建“整个产品已发布”的标签。


