# ADR-004：标签与发布分离

- 状态：Accepted
- 日期：2026-11-10

## 决策

`publish` 负责 registry 发布，`tag` 负责 Git 标签；publish 成功后可以按配置自动调用 tag，但两者均可单独 dry-run 和重试。`git-tag` 只是兼容别名。

## 原因

有些团队使用其他 publisher 或只需要源码标签；将 Git 引用和 registry 状态耦合会增加部分失败的恢复难度。

## 后果

发布工作流必须明确调用 tag 或启用 `afterPublish`；tag 命名和已存在标签检查必须进入 release plan。
