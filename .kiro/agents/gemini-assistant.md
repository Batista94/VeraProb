---
name: Gemini Assistant
description: On-demand usage for simple bugs, documentation and context recovery.
persona: file://../../.claude/agents/senior-engineer.md
capabilities:
  - bash
  - read_workspace
  - mcp:gemini
  - mcp:memory
  - mcp:sequential-thinking
steering:
  - file://../steering/forensic-standards.md
  - file://../AGENTS.md
env:
  MODE: LIGHTWEIGHT
  TOKEN_PRESERVATION: "1"
---
