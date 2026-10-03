---
name: bom-encoding-gate
description: UTF-8 BOM 编码漂移的归一与门禁负测试流程，含逐字节实测现状、区分"含非 ASCII 的 .ps1 必须有 BOM"与"文档 md/json 必须无 BOM"两个方向、带断言的字节手术或整份重写归一、规则成文加门禁机检、收尾负测试闭环。当出现 git diff 无端多出一行首行被改、Write 整写后 BOM 丢失、.ps1 在 Windows PowerShell 5.1 下中文乱码或 ParserError、需要为编码口径新增机检规则、或需要验证门禁编码规则真的会拦截时使用。
---

本文件是薄指针：读取内容遵循 `.agents/skills/bom-encoding-gate/SKILL.md`（唯一事实源）。
