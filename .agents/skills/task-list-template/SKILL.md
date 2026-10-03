---
name: task-list-template
description: 子任务派发单与任务清单：派发前按 `TASK_LIST_TEMPLATE.md` 填写可验收的切片派发单（档位/目标/材料/范围/步骤/验收/回写），并维护任务清单与 §8 = 见 EXECUTION_PLAN.md 的任务队列节。Use when the user says 写派发单、列任务清单、派发子任务、派任务给子代理、task list, or needs to dispatch a subtask / create a dispatch order / maintain a task list.
---

完整模板与填写红线（唯一事实源）= `AI_docs/ORCHESTRATION/TASK_LIST_TEMPLATE.md`。读取该文件并按其整段填写。

约束摘要（细则以模板与 `AI_docs/ORCHESTRATION/MODEL_ROUTING.md`「派发纪律」为准）：

- 派发前先过派发判定：仅真正可并行且值得才派发；线性任务主会话直接做。
- 一份派发单 = 一个 `EXECUTION_PLAN.md` §8 切片；填不完 §F 不要派。
- 省档模型必须内联 dossier 与命令级步骤（§C/§E）。
- 用户在 `/task-list-template` 后的原文材料一并纳入，勿改写目标与范围。
