---
name: veraprob-mission-sync
description: "H-10 Lifecycle Hook: Sync project state with Knowledge Graph upon mission completion."
---

# VeraProb Mission Sync (H-10)

## Objective
Ensure all structural changes, invariant updates, and architectural decisions are persisted to the Memory Server (Knowledge Graph) before concluding a task.

## Trigger
Execute this skill whenever you are about to say "Task complete", "Mission accomplished", or provide the final answer to a complex engineering task.

## Mandatory Action
Call the following tool:

```json
{
  "ServerName": "memory",
  "toolAction": "sync_project_state",
  "toolSummary": "Sincronizando estado do projeto pós-missão."
}
```

> [!IMPORTANT]
> Failure to sync leads to "Decision Drift" (INV-30). Forensic truth must be shared across all agents.
