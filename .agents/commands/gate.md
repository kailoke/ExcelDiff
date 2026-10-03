---
description: 跑交叉验收门禁（SCOPE 范围 + ANCHORS 锚点 + 文档 lint）
---
用 Bash 执行项目根下的门禁脚本：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "AI_Script/verify-scope.ps1"
```

按段汇报 SCOPE / ANCHORS / LINT 结果；FAIL 时定位到具体文件/锚点/文档并给修复建议，等确认再改。退出码与各段判读标准见 `AI_Script/verify-scope.ps1` 头注释。

收货某个派发单时加 `-TaskBrief AI_docs/HANDOFFS/<日期>-<任务号>-brief.md`：追加 TASK SCOPE 段，校验"改动 ⊆ 该单的机读 `SCOPE:` 行 ∪ 台账面（`AI_docs/**`、`AI_Script/code-anchors.json`）"，越界即 FAIL。派发该单时先用同一参数加 `-WriteScopeBaseline` 把当时的改动清单记成基线（`<派发单>.scope-baseline`），否则并行会话的无关改动会被一起算进来。
