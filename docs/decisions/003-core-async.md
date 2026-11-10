# ADR-003：迁移到 core/async

- 状态：Accepted
- 日期：2026-11-10

## 决策

新代码统一使用 `moonbitlang/core/async`、`moonbitlang/core/async/fs`、`moonbitlang/core/async/process` 和 `moonbitlang/core/async/shell`。不新增对旧 `moonbitlang/async` 的依赖。

## 依据

本地工具链 `moon 0.1.20261104` 通过 `moon ide doc` 导出了这些包和所需的文件/进程 API。

## 后果

`moon-manifest`、`native-toolchain` 的依赖升级要分别验证并发布；在迁移完成前不能把未发布版本写进 moonset 的稳定 `moon.mod`。
