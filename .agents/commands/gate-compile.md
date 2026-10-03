---
description: 跑交叉验收门禁并追加产品构建+单测+lang 同步（verify.ps1 全量，分钟级）
---
用 Bash 执行项目根下的门禁脚本（`-Compile` 追加权威验收腿 `AI_Script/verify.ps1`：构建 EDR + NetDiff 31 用例 + lang↔resx 同步 + 坑扫描；本工程编译腿只有这一条实现，无双通道）：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "AI_Script/verify-scope.ps1" -Compile
```

构建失败时从输出里的 `[FAIL]` 行定位（构建/单测/lang 同步/坑扫描各段分别汇报）；产物 exe 被常驻进程锁住导致部署类失败时，走 `/deploy`（构建→部署→重启一条龙）。退出码与判读见 `AI_Script/verify-scope.ps1` 与 `AI_Script/verify.ps1` 头注释。
