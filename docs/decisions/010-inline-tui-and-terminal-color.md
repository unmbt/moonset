# ADR-010：内联 TUI 与终端颜色策略

- 状态：Accepted
- 日期：2026-11-20
- 关联：FR-036、FR-033

## 背景

当前交互式 `add` 在主屏反复执行全屏清除和重绘，逐键输入会把完整帧推入终端 scrollback。渲染器也没有将 `Options.no_color` 接入样式输出，CLI 与 TUI 的人类输出无法呈现语义颜色。TUI 现有逐包选择流程也与 Changesets CLI 的分阶段多包交互差异较大。

## 决策

- TUI 保持在主屏，不进入 alternate screen，不执行全屏清除。渲染器记录当前活动提示框前一帧的实际视觉行数，将光标上移、回车、清除至屏底与新帧合并为单次写入以消除闪烁；每确认一个阶段即永久提交单行 `✓` 摘要并重置 `prev_lines = 0`，避免已完成步骤随交互推进溢出屏幕高度进入 scrollback。
- TUI 按 changed/unchanged 分组选择包（基于 Git 相对 `--since`/`baseBranch` 与工作区修改做最长前缀归属，无变更时省略分组标题），依次选择 major 和 minor，未分配的已选包自动归为 patch。单包直接选择 bump，`0.x` major 拒绝后返回重选。摘要确认后先恢复终端模式再执行写盘、格式化与提交。
- 视觉行数按终端列宽计算，CJK 全角字符及 Emoji Presentation / `U+FE0F` 序列占两列，`✓`/`✗` 等窄符号占一列，组合字符和 SGR 控制序列不占显示列。
- 人类输出仅在对应流连接 TTY 且终端支持 VT 时着色（Windows 主动启用 `ENABLE_VIRTUAL_TERMINAL_PROCESSING`）。遵循 `no-color.org` 规范：非空 `NO_COLOR`、`--no-color` 与 `TERM=dumb` 禁用样式，JSON/Markdown 协议输出不包含 ANSI。

## 后果

- 内联重绘需要统一行尾和软件折行规则，并在每次帧更新中准确维护 `prev_lines`。
- 输出颜色必须通过共享 CLI 辅助函数接入，避免污染 JSON、Markdown 或重定向结果。
- TUI 分阶段流程不支持已确认步骤回退；用户可取消整个流程或在摘要编辑阶段修改文本。
