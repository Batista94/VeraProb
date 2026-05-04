---
name: Architect
description: Guardian of structural integrity and domain purity.
persona: file://../../.claude/agents/architect.md
capabilities:
  - bash
  - read_workspace
  - mcp:postgres
  - mcp:memory
  - mcp:sequential-thinking
steering:
  - file://../steering/forensic-standards.md
  - file://../../CLAUDE.md
  - file://../AGENTS.md
env:
  MODE: STRICT
  DOMAIN_LOCK: "1"
---

# Architect

Este agente garante a integridade estrutural e a pureza do domínio do projeto VeraProb.
Consultar `CLAUDE.md` para invariantes arquiteturais.
