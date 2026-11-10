# Phase 1 可执行契约

本文件冻结 Phase 1 验收边界；较早的未来功能草案不代表已有能力。

## 发布规划

- `build_plan` 是纯函数。输出 `schemaVersion: 1`、`stage: "analysis"`、`executable: false`，包含版本及依赖更新意图，不生成文件补丁。
- `updateInternalDependencies` 为 `patch`（默认）或 `minor`：已发布单元更新依赖声明的上游最低 bump。越界声明总是更新。
- `updateInternalDependents` 为 `out-of-range`（默认）或 `always`：是否将尚未发布的运行依赖者带入 patch 发布。
- MoonBit 使用 Moon 940aa18 的 MVS：candidate >= required，且 major < 2 的版本在同一兼容集合，否则 major 必须相同。不是 npm caret。
- fixed 以组内最高当前版本及最高 bump 统一全部成员；linked 仅统一已有发布理由的成员。每轮从原始版本计算，至约束闭包稳定。
- 预发布读取 active/exit 状态，返回下一状态意图，绝不写回状态。重复规划不消费 changeset。

## 输入与隔离

- 发现 `moon.work` 显式成员或独立 `moon.mod`；`moon.pkg` 不是版本单元。
- 同目录其他生态清单仅报告 unmanaged。显式配置 npm/Cargo adapter、build bridge 等未实现能力时失败。
- front matter 是平面字符串映射，支持空映射；不支持 YAML 锚点、嵌套对象。未知单元、重复键和无效 bump 均报错。
- 默认值集中定义；精确名称版本组可用，glob 版本组尚不支持。
- 原始 manifest 字节用于指纹；诊断包含 code/path/line/column，配置诊断补充 JSON path。

## CLI

- `status` 不带 `--since` 读取工作目录；无 Git 仓库也可使用。
- `--since ref` 使用 merge-base(ref, HEAD)..HEAD 和 HEAD 文件快照。未提交文件不参与，显式报告警告。新增、修改、重命名 changeset 均计入，删除的不计入。
- 有相关文件变化且没有 changeset 时 status 返回 1；空 changeset 可以放行，不逐模块强制覆盖。
- 退出码 0 成功，1 策略不满足，2 无效输入，3 I/O 或 Git 失败。
- stdout JSON 不混入日志。publish-plan 默认 stdout；仅显式输出文件允许原子写入，不得覆盖输入。

## 验收矩阵

解析：UTF-8/BOM/CRLF、重复字段、无效 front matter、空 changeset。
规划：单模块、依赖链/环、版本组、ignore、MVS、两种传播策略、预发布、稳定输出。
集成：工作目录/HEAD 隔离、分叉历史、重命名、无效 ref、退出码、文件覆盖保护、失败无写入。
CI：Windows/Linux/macOS native check/test/build；生成接口、格式、schemaVersion 1 契约检查。

共享库先发布 alpha 并从注册表验证安装；moonset 稳定版等待完整发布工作流，不随 Phase 1 发布。
