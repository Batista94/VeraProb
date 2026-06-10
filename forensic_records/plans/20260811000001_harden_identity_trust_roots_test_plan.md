# Plano de Testes — 20260811000001_harden_identity_trust_roots

**Migração:** `supabase/migrations/20260811000001_harden_identity_trust_roots.sql`
**Invariantes:** INV-1 (integridade do claim de org), INV-2 (integridade da fonte do claim no RLS), INV-22 (isolamento de tenant), INV-DATA-API-GRANT (CI block #13). INV-DB: só `REVOKE` de privilégio.
**Risco:** Reduz resíduo — endurece a raiz de confiança do claim `organization_id`. Sem quebra (writers são SECURITY DEFINER).
**pgTAP:** `supabase/tests/20260811000001_harden_identity_trust_roots_test.sql` (12 testes).

---

## Contexto — o resíduo do veredito CIA

O isolamento de tenant (RLS) confia no claim `organization_id`. Esse claim é injetado na emissão do token por `public.custom_access_token_hook` (SECURITY DEFINER), derivado da tabela `user_roles`. Logo, a integridade de todo o modelo RLS reduz à integridade de `user_roles`: **se um cliente pudesse gravar a própria linha de `user_roles`, ele se auto-atribuiria qualquer `organization_id` e o hook emitiria token com o tenant da vítima.**

### Red-team (2026-06-09, runtime)
Como `authenticated` (claim org A), tentativas de auto-elevação em `user_roles`:
- INSERT self-row (org B) → **negado** (RLS sem policy de INSERT).
- UPDATE `organization_id` → **0 linhas** (RLS sem policy de UPDATE).

Auto-elevação **já bloqueada hoje** — mas só pela *ausência* de policy de escrita. O GRANT morto de `authenticated` (INSERT/UPDATE/DELETE, herdado do `ALTER DEFAULT PRIVILEGES` legado) é um primitivo de escalonamento latente: uma única policy permissiva de escrita adicionada por engano no futuro vira exploit imediato. Defesa em profundidade = remover o grant.

### Escopo (raízes de identidade)
| Tabela | Papel no trust-root | Ação |
|--------|---------------------|------|
| `user_roles` | fonte direta do claim `organization_id` | REVOKE INSERT/UPDATE/DELETE de `authenticated` |
| `organizations` | registro raiz do tenant (mesmo padrão de grant morto) | REVOKE INSERT/UPDATE/DELETE de `authenticated` |
| `super_admin_users` | god-mode (lido pelo hook) | **já sólida** — sem grant de cliente + policy `deny-all authenticated USING(false)`. Sem mudança. |

`authenticated` mantém SELECT (policies org-scoped). `anon` já não tinha grant em nenhuma.

### Segurança (sem quebra)
Todos os writers legítimos são SECURITY DEFINER (owner `postgres`) e rodam com checagem própria — verificado:
- `user_roles`: accept_invitation, deactivate_member, reactivate_member, update_member_role, super_admin_toggle_member_status, super_admin_archive/unarchive_organization.
- `organizations`: super_admin_create_organization, super_admin_archive/unarchive, super_admin_update_allowed_domains/quota, accept_invitation.

Rodam como definer → não dependem do grant de `authenticated`. `service_role` intocado.

## Nota INV-DB
`REVOKE` é metadata de privilégio (instantâneo, sem scan, sem perda). O keyword `DELETE` é nome de **privilégio**, não DML. Anotado `-- INV-DB: zero-downtime-verified`; requer ack do Council na revisão.

## Idempotência
`REVOKE` de privilégio ausente = no-op. Seguro re-rodar via `supabase db push`.

---

## Verificação (psql)
```sql
SELECT has_table_privilege('authenticated','public.user_roles','SELECT');   -- true
SELECT has_table_privilege('authenticated','public.user_roles','UPDATE');   -- false
SELECT has_table_privilege('authenticated','public.organizations','DELETE');-- false
SELECT has_table_privilege('authenticated','public.super_admin_users','SELECT'); -- false
SELECT has_table_privilege('service_role','public.user_roles','INSERT');    -- true
```

---

## Resíduo remanescente (NÃO fixável em código — ação do owner)

Após este fix, sobra a parte **irredutível/plataforma** do resíduo:

1. **Assinatura do JWT (caminho de forja).** RLS confia no claim assinado pela Supabase Auth. O esquema legado HS256 usa um **segredo simétrico compartilhado** (o mesmo que assina o `service_role` key) — qualquer vazamento permite forjar tokens. **Redução senior = migrar para chaves de assinatura assimétricas (ECC P-256 / RS256 + JWKS público)** no Dashboard → Authentication → JWT Keys → "Migrate/Rotate signing key". Chave privada nunca sai da Supabase; verificação usa chave pública. Elimina a classe de forja por segredo compartilhado. **Ação do owner** (config de plataforma, não código).
2. **`auth.uid()` vs claim (INV-2).** Tornar o RLS independente do claim (re-derivar org de `user_roles` via `auth.uid()`) eliminaria a confiança no claim, mas **viola INV-2** (decisão arquitetural deliberada por performance). Mudança requer Architect/Council — não unilateral.
3. **TTL do token.** Janela de claim obsoleto após mudança de org = TTL do JWT (default 1h). Encurtar reduz a janela. Config de Auth (owner).

Este fix fecha o **caminho 3 (envenenar a fonte do claim)** — o único elemento do resíduo corrigível em código. Caminhos 1–2 são plataforma/arquitetura (owner/Council).
