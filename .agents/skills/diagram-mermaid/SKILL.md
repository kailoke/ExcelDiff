---
name: diagram-mermaid
description: mermaid 图表通道：用本仓固定版官方 @mermaid-js/mermaid-cli 画/渲调用关系图、架构分层图、时序图、状态机、参数流转图，产物落项目根本地 Diagrams/（.mmd 源 + .svg 图，gitignored 不入库）。凡任务要画调用逻辑图 / 架构设计图 / 模块关系图 / 时序图 / 参数数据流图，或改 Diagrams/ 下产物，必须先读本技能。
---

# 图表（mermaid）工作流

## 机器事实

- 工具：官方 `@mermaid-js/mermaid-cli`，**固定 11.17.0**，装在本仓 `AI_Script/tools/mermaid/`（`package.json` + `package-lock.json` 入库；`node_modules` 经同目录 `.gitignore` 不入库）。
- 渲染引擎：headless Chromium（puppeteer 下载到 `%USERPROFILE%\.cache\puppeteer`，不入仓）。
- **唯一调用入口 = `AI_Script/mermaid-render.ps1`**（命令清单见 `AI_Script/README.md`）；不要直接调 `node_modules/.bin/mmdc`。
- 首次（新机 / 新克隆）：`.\AI_Script\mermaid-render.ps1 -Install`。npm 11 的 `allow-scripts` 默认拦 puppeteer 的 postinstall，封装里已显式补跑浏览器下载；只跑 `npm install` 会缺 Chromium。

## 产物纪律

- 落点 = 项目根 `Diagrams/`（**已 gitignore，不入库**）：`.mmd` 源 + `.svg` 渲染图都只本地生成、不进提交。
- **图是"另一种表现"，不是第二份事实源**：一个事实只在一处成文，图不得复制数值表/裁决文本；图里的关键结论必须能在代码或既有事实文档中查到。
- **与代码同源**：画前先按 `AI_docs/ROUTING.md` 读对应 DOSSIER，并对代码现场检索取证；禁止凭文档表述、会话记忆或"应该有"的关系作图。缺取证就在图里留 `UNKNOWN`，不编。
- 引用代码用稳定锚点或路径，**不写裸行号**（`AI_Script/lint-docs.ps1` 的 E4：裸行号检查，命中即拒提）。
- 因图不入库，**不要在入库的 `AI_docs` 文档里写指向图路径的引用**（避免新克隆悬空）；图只在本地看。

## 命令

```powershell
# 校验语法（渲到临时文件后删除，不留产物）：0 = OK，1 = FAIL
.\AI_Script\mermaid-render.ps1 <x.mmd> -Check

# 渲染：默认与输入同目录同名 .svg
.\AI_Script\mermaid-render.ps1 <x.mmd>
# 指定产物 / 格式 / 主题 / 背景
.\AI_Script\mermaid-render.ps1 <x.mmd> -Output <out.svg> -Format svg -Theme neutral -BackgroundColor transparent
```

渲染即语法校验；先 `-Check` 确认，再落盘。产物只本地留存，无需入库、不必跑 lint。

## 选型：画哪种图

| 想表达 | 图型 | 备注 |
|---|---|---|
| 调用关系 / 依赖方向 | `flowchart` | 用 `subgraph` 分程序集或分层（表现层/逻辑层/数据层） |
| 谁先调谁、回包 / 事件驱动、帧序 | `sequenceDiagram` | 网络、消息、帧循环 |
| 参数从哪来到哪去（数据流） | `flowchart LR`，边上标字段 | 参数流转图用这个 |
| 状态机 | `stateDiagram-v2` | 枚举态、effector 态 |
| 类 / 接口关系 | `classDiagram` | 代码已清楚时少用 |

## 仓库专属坑

- 中文与特殊字符标签**必须加引号**：`A["中文标签"]`，否则解析失败。
- `()` `[]` `{}` 在节点文字里是语法字符，放进引号；`-->` 会截断文字。
- 一张图只讲一件事；关系多就拆多张，别塞成线团。
- 文件名用 kebab-case，落在 `Diagrams/`；任务路由见 `AI_docs/ROUTING.md`。
