---
description: 日终批量门禁（时间窗内提交逐笔静态审计 + HEAD 重量段）
---
用 Bash 执行项目根下的日终批处理门禁（默认窗口 = 今天 00:00 起；重量段只对 HEAD 跑一次）：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "AI_Script/verify-day.ps1"
```

- 逐提交只做**静态审计**（禁改区/范围 + 台账同笔，纯 git 读，不需要 checkout/构建）；**不做逐提交编译**——同一 HEAD 重复编译无增量信息，而逐提交编译要为每个提交建临时 worktree 并串行构建，代价不成比例。
- HEAD 重量段：`verify-scope.ps1 -Compile`（即 `verify.ps1` 全量）；只要静态审计就加 `-SkipCompile`（秒级）。
- 指定窗口：`-Since <yyyy-MM-dd>`（git 可解析的日期/时间）。判读与退出码见 `AI_Script/verify-day.ps1` 头注释（0 = 无 FAIL / 1 = 有 FAIL / 2 = 环境错误）。
- 报告四项：逐提交 PASS/WARN/FAIL 清单 / FAIL 明细 / HEAD 重量段结论 / 未验证风险。
