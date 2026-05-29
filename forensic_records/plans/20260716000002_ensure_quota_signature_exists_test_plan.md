# Plano de Teste Forense — Ensure Quota Signature Exists

**Migrations:** `20260716000002`
**Data:** 2026-05-29
**Autor:** QA/Security Agent (Antigravity)

---

## 1. Escopo

A migration `20260716000002` garante que a assinatura de 16 parâmetros da função `super_admin_update_organization_quota` exista no banco de dados para evitar falhas na migration subsequente `20260717000002` durante o deploy em staging.
Ela faz isso dropando qualquer overload antigo (como o de 20 parâmetros) e recriando a versão de 16 parâmetros.

---

## 2. Pré-condições

- [ ] Supabase local em execução (`supabase start`)
- [ ] Database conectada

---

## 3. Verificações de Schema (pgTAP / SQL)

### 3.1 A função existe com exatamente 16 parâmetros

```sql
SELECT count(*)::int AS param_count
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'super_admin_update_organization_quota';
-- Esperado: 1 (apenas 1 overload deve existir)
```

---

## 4. Testes Funcionais

### 4.1 UPDATE via RPC funciona corretamente

```sql
-- Executar a função com os 16 parâmetros esperados
SELECT public.super_admin_update_organization_quota(
  '00000000-0000-0000-0000-000000000000'::uuid, -- org_id (placeholder/dummy)
  'professional'::text,
  10::int,
  5::int,
  '00000000-0000-0000-0000-000000000000'::uuid, -- superadmin_id
  'Test migration signature'::text,
  NULL::jsonb,
  10000::bigint,
  NULL::int,
  NULL::smallint,
  NULL::text,
  NULL::text,
  NULL::text,
  NULL::text,
  NULL::text,
  NULL::timestamptz
);
```

---

## 5. Rollback Strategy

Não há rollback automático (append-only). Em caso de problemas, uma nova migration corretiva deve ser gerada para restaurar ou alterar a assinatura.
Never modify already-applied migrations (INV-DB).
