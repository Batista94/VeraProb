---
name: veraprob-pr-scanner
description: >
  VeraProb forensic PR scanner. Invoke BEFORE any code review starts. Executes the static scanner
  script first (WASM/Financial/UTC/DB/Linter binary checks), then performs neural Clean Code audit
  (SRP violations, Leaky Abstractions, DDD nomenclature drift, CQRS layer separation).
---

# VeraProb PR Scanner

Reference: file://.kiro/steering/forensic-standards.md

For the full PR scanner guide, see: file://.claude/skills/veraprob-pr-scanner/SKILL.md
