# Phase 5 API 与插件协议

Phase 5 将扩展面分成三个包：`unmbt/moonset/api` 提供稳定 facade，
`unmbt/moonset/changelog` 提供纯 changelog generator，
`unmbt/moonset/adapters` 提供能力声明与 JSONL runner。

`api_version` 当前为 `1.0.0`。公共 API 采用 SemVer：兼容新增使用 minor，删除或改变语义使用 major；ReleasePlan 的 `schemaVersion` 独立演进。adapter trait 在 v1 标记为 experimental。

## JSONL v1

插件通过 stdin/stdout 逐行通信。请求格式为：

```json
{"schemaVersion":1,"method":"generate","payload":{}}
```

响应格式为：

```json
{"ok":true,"result":"..."}
```

publisher 可使用 `preflight`、`publish` 和 `already-published` 方法。stderr 只作为诊断，不进入计划结果。每次调用默认 30 秒超时、1 MiB stdout 上限；非 JSON、错误 schema、超时、超限或非零退出都会在写入前失败。

命令必须通过 `PluginSpec.allowed_programs` 显式登记，并以 executable 与 argv 分开传入；runner 不启动 shell，也不继承环境变量，只接受 `PluginSpec.environment` 中明确列出的变量。v1 是受信任进程边界，不提供操作系统级文件或网络沙箱。

## Changelog

`builtin`、`git`、`github` 都是纯 renderer。Git/GitHub 链接和作者信息必须由调用方作为结构化上下文传入；缺少 repository 或 PR 时保留摘要，不猜测远端链接。生成器输出会进入 VersionPlan 的编辑内容和 fingerprint。
