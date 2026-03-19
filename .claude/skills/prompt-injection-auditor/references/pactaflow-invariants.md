# PactaFlow Invariants Reference (CLAUDE.md)

Este documento mapeia as restrições técnicas obrigatórias que devem ser verificadas durante a auditoria de qualquer skill ou instrução AI.

## INV-1: IMMUTABLE LEDGER
- **Regra:** Proibido UPDATE ou DELETE em `ledger`, `events`, `facts` ou `financial_records`.
- **Alvo de Auditoria:** Qualquer instrução que peça para "ajustar", "corrigir arquivo" ou "remover entrada" do registro financeiro.

## INV-4: DOMAIN SOVEREIGNTY
- **Regra:** Lógica de negócio apenas em Dart puro. Zero dependências de infra em `lib/domain`.
- **Alvo de Auditoria:** Skills que tentam importar `package:flutter` ou `package:supabase` dentro de arquivos de domínio.

## INV-5: SINGLE DECISION ENGINE
- **Regra:** Somente `EvaluationEngine` emite vereditos.
- **Alvo de Auditoria:** Comandos que sugerem que a IA decida se um SLA foi cumprido sem usar o motor de regras.

## INV-6 & INV-10: MULTI-TENANT ISOLATION
- **Regra:** Todo dado pertence a um `organization_id`. RLS deve ser baseado em JWT.
- **Alvo de Auditoria:** Scripts SQL gerados que não incluam `organization_id` ou que filtrem por `auth.uid()` em vez de `auth.jwt() ->> 'organization_id'`.

## INV-9: ZERO-TRUST INGESTION
- **Regra:** Fatos são permanentes e deduzidos da telemetria.
- **Alvo de Auditoria:** Skills que processam dados externos (Firecrawl) sem rotulagem clara de dados "não confiáveis".
