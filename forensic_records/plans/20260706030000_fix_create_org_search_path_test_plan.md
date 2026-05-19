# Forensic Test Plan — Migration `20260706030000_fix_create_org_search_path`

> **Classificação:** Engineering Study / Fix / Search Path Hardening
> **Emitido por:** QA/Security Council Persona
> **Data de emissão:** 2026-05-19
> **Migração alvo:** `supabase/migrations/20260706030000_fix_create_org_search_path.sql`
> **Operações:** `CREATE OR REPLACE FUNCTION super_admin_create_organization`
> **Invariantes cobertos:** INV-28 (Atomicity on secret generation), INV-DB (Zero-Downtime Pattern), INV-7 (Strict Types)

---

## Contexto da Investigação

Em ambientes locais e de CI com Supabase, a função `super_admin_create_organization` falhava em resolver as funções de hashing do `pgcrypto` (`gen_random_bytes` e `digest`) se a extensão não estivesse explicitamente no `search_path` ou se as chamadas não estivessem qualificadas com o esquema `extensions.`.

**Correção:**
1. Garantir que a extensão `pgcrypto` está ativa no esquema `extensions`.
2. Atualizar a declaração do RPC `super_admin_create_organization` definindo `SET search_path = public, auth, extensions` e qualificando as chamadas para as funções criptográficas como `extensions.gen_random_bytes` e `extensions.digest`.

---

## Pré-condições de Ambiente

| Item | Valor esperado |
|------|----------------|
| PostgreSQL | ≥ 14 |
| Supabase local | `supabase start` ativo |

---

## Grupo 1 — Verificação do RPC redeclarado

### Objetivo

Confirmar que a função RPC foi recriada com o `search_path` correto e que ela funciona adequadamente usando `pgcrypto`.

### Casos de Teste

| # | Caso | Setup | Resultado esperado |
|---|------|-------|--------------------|
| 1.1 | Happy Path: Criar Organização com credenciais de super admin | Chamar `public.super_admin_create_organization` com dados válidos | Transação conclui com sucesso, inserindo a organização e gerando o segredo da API usando as funções qualificadas. |
| 1.2 | Search Path correto | Consultar `pg_proc` para a função | O campo `proconfig` deve conter `search_path=public, auth, extensions` |

**Script de verificação (CT-1.2):**

```sql
SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'super_admin_create_organization'
      AND array_to_string(p.proconfig, ',') LIKE '%search_path=public, auth, extensions%'
  ),
  'super_admin_create_organization: search_path contains extensions'
);
```

---

## Grupo 2 — Zero-Downtime (INV-DB)

### Objetivo

Confirmar que a migração não bloqueia a execução do banco de dados de produção.

### Justificativa de Zero-Downtime

| Operação | Lock adquirido | Escopo | Bloqueia INSERTs? |
|----------|----------------|--------|-------------------|
| `CREATE OR REPLACE FUNCTION` | `AccessExclusiveLock` em `pg_proc` | Catálogo (~ms) | Não |

A redeclaração de funções não bloqueia DML (INSERT/UPDATE/SELECT) em tabelas operacionais.
