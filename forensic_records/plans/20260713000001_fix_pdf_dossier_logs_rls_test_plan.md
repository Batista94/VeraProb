# Forensic Test Plan: 20260713000001_fix_pdf_dossier_logs_rls

## Objetivo
Validar o hardening da política RLS na tabela `pdf_dossier_logs`, garantindo conformidade com a invariante INV-2 pelo uso do claim de nível superior `auth.jwt() ->> 'organization_id'`.

## Invariantes Garantidas
- **INV-1:** Tenant isolation na tabela (RLS ativa).
- **INV-2:** Identidade organizacional via claim `auth.jwt() ->> 'organization_id'`.

## Cenários de Teste (pgTAP)

| # | Cenário | Asserção |
|---|---------|----------|
| P1 | Tentar ler registros com JWT que possui `organization_id` correspondente | Sucesso e retorno dos registros |
| P2 | Tentar inserir com `organization_id` diferente do top-level `organization_id` do JWT | Erro RLS (`new row violates row-level security policy`) |
| P3 | Tentar ler registros de outro tenant (onde `organization_id` difere) | Retorna 0 linhas (Isolamento de tenant - INV-22) |
