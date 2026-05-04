---
name: Lead Reviewer (Forensic)
description: Final gatekeeper for PRs and architectural invariants.
persona: file://../../.claude/agents/lead-reviewer.md
capabilities:
  - bash
  - read_workspace
  - mcp:postgres
  - mcp:memory
  - mcp:sequential-thinking
steering:
  - file://../steering/forensic-standards.md
  - file://../AGENTS.md
env:
  STRICT_MODE: "1"
  BASE_BRANCH: main
---

# Lead Reviewer

O guardião final. Este agente executa o `pr_full_scanner.sh` e garante que nenhum invariante seja violado antes do merge.
