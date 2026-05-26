# Forensic Test Plan: 20260710000001_pdf_dossier_logs

## Objetivo
Validar a criação da tabela `pdf_dossier_logs` e a correta aplicação do RLS baseada em `organization_id` do JWT (`app_metadata.org_id`), conforme INV-1 e INV-2.

## Invariantes Garantidas
- **INV-1:** Tenant isolation na tabela (RLS ativa).
- **INV-2:** Identidade organizacional via `auth.jwt()`.
- **INV-9:** Hash guardado na persistência (`document_hash_sha256` NOT NULL).

## Cenários de Teste (pgTAP)

| # | Cenário | Asserção |
|---|---------|----------|
| P1 | `pdf_dossier_logs` tem as colunas corretas | `has_column(...)` para cada coluna requerida |
| P2 | Tentar inserir com `organization_id` diferente do JWT atual | Erro RLS (`new row violates row-level security policy`) |
| P3 | Tentar inserir com `generated_by` nulo | Falha na constraint `NOT NULL` |
| P4 | Tentar ler registros de outro tenant | Retorna 0 linhas (Isolamento de tenant - INV-22) |
