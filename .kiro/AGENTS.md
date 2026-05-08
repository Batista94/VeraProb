# Catálogo de Agentes VeraProb

Este arquivo define os especialistas (Council) disponíveis no Kiro IDE, suas competências e as ferramentas que orquestram.

## 1. Arquiteto (Architect)
- **Função**: Guardião da pureza de domínio e integridade estrutural.
- **Ferramentas**: C4 Diagrams, Wasm Toolchain, Memory Server (Invariants).
- **Triggers**: Mudanças estruturais, novas camadas, decisões de persistência.
- **Config**: `.kiro/agents/architect.json`

## 2. Engenheiro Sênior (Senior Engineer)
- **Função**: Especialista em Flutter, SQL e Performance.
- **Ferramentas**: Flutter CLI, Supabase Sync, Query Optimizer.
- **Triggers**: Implementação de UI, lógica de negócio, migrations de banco.
- **Config**: `.kiro/agents/senior-engineer.json`

## 3. QA & Security (QA/Sec)
- **Função**: Auditoria forense, Red Team e Invariantes de segurança.
- **Ferramentas**: Forensic Scanner, RLS Auditor, Chaos Simulator.
- **Triggers**: Alterações em RLS, fluxos financeiros, integração de telemetria.
- **Config**: `.kiro/agents/qa-security.json`

## 4. Lead Reviewer (Reviewer)
- **Função**: Gatekeeper final da pipeline de PR.
- **Ferramentas**: PR Full Scanner, Clean Code Auditor.
- **Triggers**: Abertura de PR, Commits em branch principal.
- **Config**: `.kiro/agents/lead-reviewer.json`

## 5. UX & Operations (UX/Ops)
- **Função**: Garantir a estética premium e automação de workflow.
- **Ferramentas**: Design System tokens, CI/CD Hooks.
- **Triggers**: Criação de componentes UI, mudanças em scripts de automação.
- **Config**: `.kiro/agents/ux-operations.json`
