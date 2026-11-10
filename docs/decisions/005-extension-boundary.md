# ADR-005：扩展 API 与 JSONL 插件边界

- 状态：Accepted
- 日期：2026-11-10

## 决策

稳定扩展以编译期 MoonBit trait 和 registry 为主；需要独立进程的生成器/publisher 使用版本化 JSONL 协议，默认无文件写权限。v1 不支持从 JSON 配置动态加载任意 MoonBit 模块。

## 原因

MoonBit 没有与 Node `require` 等价的安全运行时模块加载模型；编译期类型能提供更强的错误检查，JSONL 则覆盖跨语言和独立发布插件。

## 后果

配置只引用已注册名称或显式允许命令；插件必须处理超时、schema 校验和崩溃。将来工具链提供稳定动态模块机制后可新增 adapter，不改变核心 planner。
