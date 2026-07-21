# ADR 011: Auth Zero-Trust — Sessões Revogáveis (A portável)

**Date:** 2026-07-21
**Status:** Accepted
**Context:** Phase 11 Etapa −1 — revisão H2.1 (A portável)

### Decision record

| Campo | Valor |
|-------|-------|
| Status anterior | Proposed (revisão H2.1 — A portável) |
| Status atual | **Accepted** |
| Authority | Fundador |
| Confirmed | 2026-07-21 |
| Council | H2.1 PASS (Architect, Senior, QA/Security) + Lead PASS_DOCUMENTAL |
| Scope of acceptance | Contrato Zero-Trust / registro PG / wiring Edge+RLS; `P-REV-IMPL-01` permanece OPEN (runtime) |
| Explicitly not authorized | Proposta canônica, roadmap, Etapa 0, commit, implementação |
| Residual sync | `forensic_records/plans/20260721000000_jwt_p0_residual_risks.md` ratificado excepcionalmente pelo fundador |

## Context

VeraProb exige isolamento multi-tenant fail-fast (INV-1, INV-2, INV-22),
MFA em transições sensíveis e anti-oracle (INV-26). O baseline atual —
**JWT P0 na stack Supabase** (`supabase/functions/shared/jwt_auth_validator.ts`)
— é **temporário** para validação criptográfica, mas **não** basta para
revogação pré-`exp`.

Sob **A portável**, Supabase Auth continua responsável por identidade, MFA
e refresh; um **registro server-side no PostgreSQL** torna-se a autoridade
de revogação para Edge e RLS/Data API. Go auth / dual-run é contrato
**condicional** (ADR-010 B/C), não próximo passo aprovado.

Riscos residuais:

- [JWT P0 residual risks](../../../forensic_records/plans/20260721000000_jwt_p0_residual_risks.md)
  - **AAL2 reveal:** CLOSED (2026-07-21)
  - **Revogação pré-`exp`:** design neste ADR; implementação `P-REV-IMPL-01`

Documentos irmãos:

- [Proposta canônica Phase 11](../proposals/phase11_enterprise_pivot.md)
- [Threat model](../proposals/phase11_threat_model.md)
- [Parity checklist](../proposals/phase11_parity_checklist.md)
- [ADR 010 — A portável / exit ramp](./010_exit_supabase.md)
- [ADR 012 — RLS / connection lifecycle](./012_rls_connection_lifecycle.md)
- [ADR 013 — Strangler Fig](./013_strangler_fig.md)

## Alternatives Considered

### A) Só Supabase Auth + remediações pontuais (sem registro PG)

- **Prós:** menor escopo.
- **Contras:** revogação pré-`exp` continua limitada a TTL; rejeitado como
  destino Zero-Trust.

### B) Sessões server-side revogáveis + JWT curto sobre Supabase Auth (proposta)

Access JWT curto; refresh com rotação (Supabase Auth); registro PG como
autoridade de revogação para Edge/RLS/Data API.

- **Prós:** logout/ban/revoke-all imediatos; alinhado a A portável.
- **Contras:** implementação Etapa 1 (`P-REV-IMPL-01`); testes adversarial.

### C) Auth Go como principal imediato

Rejeitado nesta fase (sem go/no-go B/C). Dual-run futuro permanece
condicional.

## Decision

Adotar, como **contrato-alvo Accepted sob A portável**, Zero-Trust com:

1. Supabase Auth = identidade, MFA, refresh.
2. Registro PostgreSQL = autoridade de revogação (Edge + RLS/Data API).
3. Access JWT curto + claims de versão; fail-closed.
4. Dual-run / emissor candidato = **condicional** a B/C (ADR-010).

## Contrato de autenticação

### Autoridade

| Superfície | Autoridade |
|------------|------------|
| Identidade / MFA / refresh | Supabase Auth |
| Revogação efetiva (Edge, RLS, Data API) | Registro server-side PostgreSQL |
| Indisponibilidade PG ou Auth | **Fail-closed** (deny); sem fallback permissivo |

Baseline nota: `jwt_expiry = 300` e rotação de refresh já configurados no
provedor são **baseline**, **não** evidência suficiente de revogação
pré-`exp`.

### Enforcement sob A portável (PostgREST / Edge) — contrato de wiring

Sem este wiring, `PG-REVOCATION` **não** pode ser `CONTRACT COMPLETE`.
Implementação = `P-REV-IMPL-01` (Etapa 1 A portável); aqui fica o mecanismo
obrigatório:

1. **Registro** (tabela PostgreSQL, nome canônico na Etapa 1): colunas
   mínimas `session_id` (PK opaca), `principal_id` (`sub`), `user_version`,
   `session_version`, `status` (`active`\|`revoked`\|`expired`\|`banned_principal`),
   `refresh_family_id`, `revoked_at`, `expires_at` (absoluta/idle),
   timestamps UTC. Grants: sem `SELECT` amplo a `authenticated` na tabela
   crua; acesso só via funções abaixo.

2. **Função fail-closed** `app.session_is_live()` (SECURITY INVOKER ou
   equivalente documentado): lê claims `session_id`, `user_version`,
   `session_version`, `jti` de `auth.jwt()`; compara ao registro; retorna
   `true` só se status=`active` e versões iguais; em ausência de claim,
   divergência, linha ausente, ou erro de leitura → `false` (nunca
   “allow on error”).

3. **Data API / RLS:** policies de tabelas sensíveis (e, no mínimo, todas
   as mutações tenant-scoped) **MUST** incluir
   `AND app.session_is_live()` (ou predicado equivalente). Predicado de
   org (`organization_id` / INV-2) permanece; o check de sessão é
   **adicional**, não substituto. Catálogos globais read-only podem
   listar exceção explícita no inventário de policies da Etapa 1.

4. **Edge:** `handleWithSecurity` / validadores privilegiados **MUST**
   consultar o mesmo registro (RPC/`session_is_live` ou SELECT via
   service path com os claims do caller) **antes** do handler; deny =
   401/404 INV-26 conforme rota. Não basta `getClaims` local.

5. **RPCs de revogação** (logout, revoke-one, revoke-all / bump
   `user_version`, ban): SECURITY DEFINER com checagem de principal/org,
   idempotentes, audit append-only sem tokens. Refresh replay → revoga
   família (`refresh_family_id`) inclusive sucessor.

6. **Proibido:** cache positivo de `session_is_live`; confiar só em TTL
   do JWT; bypass Data API sem predicado de registro em tabelas
   sensíveis.

> **Supersessão documental:** o trecho “Opções a decidir” em
> `forensic_records/plans/20260721000000_jwt_p0_residual_risks.md` §P1
> fica **superseded** por este ADR (design). A sincronização literal do
> residual é track `DOC-RESIDUAL-SYNC-01` (editável com autorização;
> não bloqueia o contrato se a supersessão estiver explícita aqui).

### Claims obrigatórios (além do conjunto JWT P0)

| Claim | Regra |
|-------|--------|
| `session_id` | Opaco; referencia registro PG |
| `jti` | Obrigatório em access; unicidade + denylist pós-revogação |
| `user_version` | Inteiro; divergência vs registro → deny |
| `session_version` | Inteiro; divergência vs registro → deny |
| `iss` / `aud` / `sub` / `exp` / `iat` / `role` / `organization_id` / `aal` | Como JWT P0 + INV-1 |
| `actor` | Obrigatório em impersonação; separado de `sub` efetivo |

Ausência de claim obrigatório, divergência de versão ou store indisponível
→ **fail-closed**.

### Revogação

| Ação | Efeito |
|------|--------|
| Individual | Marca a sessão `revoked` no registro |
| Global (revoke-all) | Incrementa `user_version`; invalida todas as sessões do principal |
| Logout / ban / recovery / mudança de senha / role / tenant | Idempotentes + auditados; efeito imediato no registro |

Staleness máxima de revogação após commit no registro: **zero**.
Sem cache positivo de autorização nesta fase.

### TTLs

| Token / sessão | TTL |
|----------------|-----|
| Access JWT | **5 minutos** |
| Idle | **24 horas** |
| Sessão absoluta | **30 dias** |
| Step-up AAL2 | **15 minutos** |
| Impersonação | **30 minutos**, **sem refresh**, `actor` separado |

### Refresh — rotação, concorrência e replay

- Rotação **atômica** e **serializada pelo cliente**.
- Um commit vence; qualquer uso posterior do refresh já consumido é
  **replay**.
- Replay **revoga toda a família** — inclusive o sucessor emitido — e
  força reautenticação de **todos** os concorrentes.

### Rate limiting e anti-oracle

Obrigatório em login, recovery, MFA, refresh e revogação, por combinação
de IP + principal normalizado + sessão quando aplicável. Excesso → **429**
sem revelar existência da conta (INV-26).

A stack A herda os limites configurados do Supabase Auth e **registra
valores/fontes** na implementação (`P-REV-IMPL-01`). Contrato futuro (B/C)
deve ser igual ou mais restritivo. Ausência de limite em endpoint sensível
**reprova** `PG-REVOCATION` / `PG-AUTH`.

### Logout, ban, recovery

- Logout: revoga sessão corrente; idempotente.
- Ban: marca principal; revoke-all; novos logins fail-closed até unban
  privilegiado com AAL2.
- Recovery: token one-shot, TTL curto, rate-limited; sucesso → revoke-all
  + step-up MFA antes de operações sensíveis; anti-oracle INV-26.

### MFA / AAL2 / step-up / anti-downgrade

- Operações sensíveis exigem step-up AAL2.
- Anti-downgrade: AAL2 não rebaixa a AAL1 sem novo login.
- **`reveal-webhook-signing-secret` MUST `requireAAL2: true`** — **CLOSED**
  em código (2026-07-21).

### Impersonação

Sessão derivada: TTL 30 min, sem refresh, auditada, `actor` ≠ `sub`
efetivo; hybrid principal **proibido**.

### Cookies / CSRF (SPA)

Quando cookies forem usados: `HttpOnly` + `Secure` + `SameSite=Strict`;
CSRF token vinculado à sessão em mutações. Refresh não em `localStorage`.

### Algoritmos / JWKS

Allowlist `alg` (ex. ES256/RS256); `none` proibido; algorithm confusion
rejeitada; JWKS indisponível → deny.

### Separação tenant / SuperAdmin

Espaços distintos; escapes só via `SuperAdminBypassTenantValidator` (ou
equivalente futuro) com MFA. Hybrid principal proibido.

### Logs e retenção

- Logs/auditoria: `sub`, `session_id`, `jti`, `organization_id`, `aal`,
  `iss`, resultado — **nunca** tokens, cookies, MFA secrets, recovery
  tokens.
- Estado operacional terminal (sessões revogadas/expiradas): **90 dias**.
- Auditoria append-only: arquivada ≥ **1 ano** em pré-produção.

### Fail-closed / timeouts

Qualquer falha de JWKS, store, claim, AAL, tenant, timeout/AbortSignal →
**deny**. Sem allow-by-timeout.

### Dual-run futuro (condicional B/C)

- Um único issuer por rota.
- Sincronização de revogações por **outbox idempotente**.
- Hybrid principal proibido.
- **Rollback:** mantém Supabase Auth como autoridade primária; invalida
  sessões emitidas pelo candidato **antes** de desligar a flag do
  emissor candidato.

### Testes obrigatórios (aceitação técnica — Etapa 1)

| Classe | Escopo |
|--------|--------|
| Crypto | alg allowlist, JWKS down → deny |
| Contract | claims + versões sem coerção ambígua |
| Adversarial | replay refresh; AAL1 reveal; ban mid-session; revoke-all concorrente; impersonation sem actor; wrong-org → 404 |
| Revocation | individual/global antes de `exp` em Edge **e** Data API/RLS; store down → deny; rate limit; audit sem tokens |
| Dual-run (se B/C) | rollback emissor candidato |

## Gates e pendências

| Gate ID | Objetivo | Estado documental | Runtime |
|---------|----------|-------------------|---------|
| `PG-AAL2` | Reveal exige AAL2 | **CLOSED** (evidência) | PASS (código atual) |
| `PG-REVOCATION` | Revogação pré-`exp` | **CONTRACT COMPLETE** | **NOT RUN** até `P-REV-IMPL-01` |

| ID | Risco | status |
|----|-------|--------|
| P-AUTH-AAL2 / P-AAL2-01 | AAL2 reveal | **CLOSED** |
| P-AUTH-REV / P-REV-01 | Design revogação | **CLOSED** (decisão arquitetural) |
| **P-REV-IMPL-01** | Implementação registro PG + wiring | **OPEN** — não bloqueia PASS documental −1; **bloqueia primeiro piloto** e qualquer `PG-REVOCATION PASS` |
| P-AUTH-TTL | TTLs numéricos | **CLOSED** (tabela acima) |
| P-AUTH-DUAL | Dual-run iss/aud | **conditional_future** (não pré-requisito de A) |
| P-AUTH-COOKIE | SameSite/CSRF rollout | track Etapa 1 se cookies forem usados |

Evidência AAL2: `forensic_records/plans/20260721000000_jwt_p0_residual_risks.md`;
`supabase/functions/reveal-webhook-signing-secret/index.ts`;
`supabase/functions/tests/reveal_webhook_signing_secret_unit_test.ts`.

## Consequences

- **Positive:** autoridade de revogação explícita; TTLs fechados; AAL2
  fechado; design P-REV fechado sem fingir mitigação runtime.
- **Negative:** Etapa 1 obrigatória antes do piloto; rate limits e wiring
  RLS/Data API a implementar.
- **Não-consequência:** não substitui Supabase Auth agora; não aprova auth
  Go; não declara `PG-REVOCATION PASS`.
