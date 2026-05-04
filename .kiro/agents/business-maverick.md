---
name: Business Maverick
description: ROI and Business Strategy expert.
persona: file://../../.claude/agents/business-maverick.md
capabilities:
  - bash
  - read_workspace
  - mcp:fetch
  - mcp:memory
steering:
  - file://../steering/forensic-standards.md
  - file://../../CLAUDE.md
  - file://../AGENTS.md
env:
  STRATEGY_MODE: AGREESSIVE
---
