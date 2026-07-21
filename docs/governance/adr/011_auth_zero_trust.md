# ADR 011: Auth Zero-Trust — Sessões Revogáveis e Migração Gradual

**Date:** 2026-07-21
**Status:** Proposed
**Context:** Phase 11 Etapa -1

## Context

VeraProb exige isolamento multi-tenant fail-fast (INV-1, INV-2, INV-22),
MFA em transições sensíveis e anti-oracle (INV-26). O baseline atual —
**JWT P0 na stack Supabase** (`supabase/functions/shared/jwt_auth_validator.ts`)
— é **temporário**: corrige validação criptográfica imediata, mas **não** é
o desenho final de autenticação em Go do candidato self-host
(ver [ADR 010](./010_exit_supabase.md)). “JWT próprio no Go” **não** é
decisão suficiente; este ADR define o lifecycle completo de identidade,
sessão, chaves e revogação.

Riscos residuais já registrados:

- [JWT P0 residual risks](../../../forensic_records/plans/20260721000000_jwt_p0_residual_risks.md)
  - **P0/P1:** AAL2 ainda não obrigatório em
    `reveal-webhook-signing-secret`
  - **P1:** `auth.getClaims` pode não refletir logout/ban/revogação até
    `exp` do access token

Esta ADR propõe o contrato Zero-Trust de autenticação/autorização para a
Phase 11, compatível com dual-run gradual fora do Supabase Auth, sem
consumar a migração.

Documentos irmãos:

- [Proposta canônica Phase 11](../proposals/phase11_enterprise_pivot.md)
- [Threat model](../proposals/phase11_threat_model.md)
- [Parity checklist](../proposals/phase11_parity_checklist.md)
- [ADR 010 — Exit Ramp Supabase](./010_exit_supabase.md)
- [ADR 012 — RLS / connection lifecycle](./012_rls_connection_lifecycle.md)
- [ADR 013 — Strangler Fig](./013_strangler_fig.md)
- [Riscos residuais JWT P0](../../../forensic_records/plans/20260721000000_jwt_p0_residual_risks.md)

## Alternatives Considered

### A) Permanecer só no Supabase Auth + remediações pontuais

Fechar AAL2 no reveal e encurtar TTL / introspectar rotas privilegiadas,
sem servidor de sessão próprio.

- **Prós:** menor escopo; aproveita provedor.
- **Contras:** revogação pré-`exp` continua limitada; pouco controle de
  `jti`/denylist; não prepara candidato Go.

### B) Sessões server-side revogáveis + JWT curto (proposta)

Access JWT de vida curta; refresh com rotação; store de sessão no servidor
(revogável); dual-run com Supabase Auth até parity gates verdes.

- **Prós:** logout/ban/revoke-all imediatos; alinhado a Zero-Trust;
  compatível com exit ramp ADR 010.
- **Contras:** complexidade de dual-run; exige testes adversarial e
  runbooks.

### C) mTLS / API keys como principal de UI humana

Rejeitado para sessões interativas de OCC/CFO: API keys permanecem para
ingest de dispositivos (INV-17), não como substituto de identidade humana
com MFA/AAL2.

## Decision

**Recommended direction under evaluation:** adotar, como contrato-alvo sob
avaliação, um modelo Zero-Trust com **sessões server-side revogáveis**,
**access JWT de curta duração**, **refresh com rotação e detecção de
replay**, cookies **HttpOnly + Secure + SameSite=Strict** para mutações da
SPA, MFA/AAL2 com step-up obrigatório em revelação de segredos, e
**migração gradual dual-run** a partir do baseline JWT P0 (temporário)
em direção ao auth do candidato Go — sem declarar cutover consumado.

## Contrato de autenticação (proposta)

### Sessões server-side revogáveis

- Toda autenticação interativa materializa um registro de sessão no
  servidor (`session_id`), referenciado pelo refresh e, quando aplicável,
  pelo claim `jti` / `sid` do access token.
- Estados: `active` | `revoked` | `expired` | `banned_principal`.
- Revogação é **imediata** no store (antes de `exp`); validadores
  privilegiados **não** confiam apenas em assinatura local se a política
  da rota exigir sessão viva (fail-closed).

### Access JWT curto

- Access token: TTL curto (valor exato = pendência operacional; ver
  P-AUTH-TTL).
- Validação: assinatura + claims obrigatórios + allowlist de `alg` +
  `kid` via JWKS; **sem coerção ambígua** de tipos/claims.
- Baseline JWT P0 atual permanece até o dual-run atingir parity gates;
  não é o endpoint final Go.

### Refresh com rotação

- Cada uso de refresh emite novo par access/refresh e **invalida** o
  refresh anterior (rotation).
- Reuso de refresh já rotacionado = **replay** → revogar a família de
  sessão (detection) e forçar re-login (fail-closed).

### Detecção de replay

- Tracking de `jti` / refresh token hash; janela de graça mínima apenas se
  documentada e testada; default = rejeitar e revogar família.

### Logout

- Logout de dispositivo: revoga sessão corrente + invalida refresh +
  access torna-se inutilizável nas rotas que introspectam sessão
  (não basta esperar `exp`).
- Logout deve ser idempotente (`session_id` já revogado → 204/equivalente
  sem vazar existência cross-tenant).
- Em dual-run: logout deve invalidar coerentemente sessão Supabase Auth
  **e** session store candidato (ou documentar ordem canônica única).

### Ban de principal

- Ban marca o sujeito (`sub`) como banido; todas as sessões ativas do
  principal são revogadas; novos logins fail-closed até remoção do ban
  por fluxo privilegiado com AAL2.

### Account recovery

- Recovery via canal out-of-band verificado; tokens de recovery de uso
  único, TTL curto, rate-limited.
- Sucesso de recovery: **revoke-all sessions** do principal + step-up MFA
  obrigatório antes de operações sensíveis.
- Anti-oracle: respostas de “e-mail enviado” / “se existir” sem distinguir
  tenant alheio nem enumerar usuários (INV-26).

### Revoke-all sessions

- Endpoint autenticado (self) e endpoint admin (SuperAdmin / security
  role) com AAL2.
- Efeito: todas as `session_id` do `sub` → `revoked`; refresh family
  invalidada; denylist/introspection passa a falhar **antes** de `exp`.

### Concorrência e idempotência

- Rotação de refresh, logout, ban e revoke-all são **idempotentes** por
  chave (`session_id`, `jti`, `idempotency_key` de escrita).
- Corridas: uma rotação vence; a perdedora trata-se como replay ou no-op
  seguro — nunca cria segunda família ativa silenciosa.

### Cookies: HttpOnly, Secure, SameSite=Strict

- Tokens de sessão/refresh em cookie: `HttpOnly`, `Secure`,
  `SameSite=Strict` para a SPA que realiza mutações same-site.
- **Escolha:** `Strict` (não `Lax`) para reduzir CSRF em POST/PUT/PATCH/DELETE
  da OCC; documentar que navegação cross-site top-level não reenviará o
  cookie (trade-off aceito para superfície forense).
- Access JWT em memória da SPA é aceitável se o refresh permanecer no
  cookie Strict; não armazenar refresh em `localStorage`.

### CSRF

- Com `SameSite=Strict` + mutações same-origin, CSRF clássico é mitigado;
  ainda assim exigir CSRF token **vinculado à sessão** (double-submit ou
  header custom `X-Requested-With` / token dedicado) em mutações
  state-changing enquanto dual-run com clientes legados existir.
- Rejeitar requests sem origem/header esperados (fail-closed).

### MFA / AAL2 / step-up / anti-downgrade

- Login pode emitir AAL1; operações sensíveis exigem **step-up** para
  AAL2 (MFA satisfeito na sessão corrente).
- Claim `aal` obrigatório e verificado server-side; cliente não “promove”
  AAL.
- **Anti-downgrade:** sessão que atingiu AAL2 não pode ser rebaixada a
  AAL1 sem novo login; token com `aal` menor que o exigido pela rota →
  deny.

### AAL2 obrigatório em revelação de segredo

- `reveal-webhook-signing-secret` (e equivalentes) **MUST** exigir
  `requireAAL2: true` (ou paridade no auth Go).
- Rejeição explícita de `aal1` em produção com teste unitário/adversarial.
- Residual atual: ver plano JWT P0 — owner e gate `PG-AAL2` abaixo.

### Impersonação

- Impersonação é sessão **derivada** distinta: autorização explícita,
  TTL curto, revogável, auditada (append-only), com claims que
  distinguem identidade real (`actor`) vs identidade atuante (`sub`
  efetivo).
- Não herda refresh de longa duração do impersonator sem novo step-up.
- Hybrid principal proibido (abaixo).
- SuperAdmin impersonation → ainda falha se `organization_id` alvo não
  for explicitamente bound na sessão derivada.

### Claims obrigatórios

| Claim | Regra |
|-------|--------|
| `iss` | Allowlist de emissores (Supabase dual-run e/ou auth Go) |
| `aud` | Audience da API OCC/Edge; reject mismatch |
| `sub` | Identificador estável do principal |
| `exp` | Obrigatório; rejeitar expirado |
| `nbf` | Se presente, rejeitar antes de `nbf` |
| `iat` | Obrigatório; clock skew mínimo documentado |
| `jti` | Obrigatório em access; unicidade + denylist pós-revogação |
| `role` | Role RBAC tipada; nunca confiar só no client |
| `organization_id` | Tenant bind top-level (INV-1); fail-fast se ausente em fluxos tenant |
| `aal` | `aal1` \| `aal2`; step-up enforced server-side |

Validação **sem coerção ambígua** (tipos, strings vazias, arrays
inesperados → reject).

### Algoritmos e prevenção de algorithm confusion

- **Allowlist de `alg`:** apenas algoritmos aprovados (ex.: `ES256` /
  `RS256` conforme key set); **`none` proibido**.
- `alg` do header deve bater com o JWK do `kid`; rejeitar tokens que
  tentem trocar família assimétrica↔simétrica (algorithm confusion).
- Não aceitar chave embutida no token (reject `jwk` header).

### `kid`, JWKS, geração e rotação de chaves

- Validação via JWKS; `kid` desconhecido → reject fail-closed.
- Geração/armazenamento de signing keys em vault/KMS (nunca em repo);
  rotação com **overlap** seguro de chaves; cache JWKS com TTL curto e
  refresh explícito.
- Indisponibilidade de JWKS (timeout, 5xx, parse error) → **deny**
  (fail-closed); sem fallback permissivo para “assinatura local apenas”
  em rotas privilegiadas.

### Separação tenant / SuperAdmin

- Principal de tenant e SuperAdmin são **espaços distintos** de sessão e
  claims.
- Escapes multi-tenant apenas via `SuperAdminBypassTenantValidator` (ou
  equivalente Go) com MFA.
- SuperAdmin orgless **somente** em fluxos explicitamente allowlisted e
  auditados; nunca via `SET` de tenant do usuário (ADR 012).
- **Proibido hybrid principal:** mesmo token/sessão não pode carregar
  simultaneamente poderes de tenant arbitrário e SuperAdmin sem actor
  model explícito e auditado.

### Rate limit, credential stuffing, anti-oracle

- Rate limit por IP + identificador normalizado em login, recovery e MFA.
- Mitigação de credential stuffing e enumeração de usuários (mensagens/
  timing homogêneos).
- Respostas de autenticação homogêneas para not-found vs wrong-org vs
  wrong-password onde aplicável (INV-26).
- Lockout progressivo sem vazar se a conta existe em outro tenant.

### Logs sem segredos

- Logs/auditoria: `sub`, `session_id`, `jti`, `organization_id`, `aal`,
  `iss`, resultado — **nunca** access/refresh tokens, cookies, MFA
  secrets, webhook signing secrets, recovery tokens, nem PII
  desnecessária.
- Mascaramento obrigatório em Edge/API e SIEM pipelines.

### Fail-closed

- Qualquer falha de JWKS, store de sessão indisponível, claim obrigatório
  ausente, `alg` fora da allowlist, AAL insuficiente, tenant ausente/
  inválido, timeout de introspecção → **deny**.
- Não degradar para “assinatura local apenas” em rotas privilegiadas
  (SA, reveal, MFA gates) quando a política exige sessão viva.

### Timeouts / AbortSignal

- Chamadas de introspecção, JWKS fetch e store de sessão usam timeout +
  `AbortSignal` (ou equivalente Go `context.WithTimeout`).
- Estouro de prazo / cancelamento / verificador indisponível = fail-closed
  (deny), nunca allow-by-timeout nem bypass.

### Migração gradual Supabase Auth (dual-run)

1. Manter JWT P0 como baseline temporário.
2. Introduzir session store + refresh rotation atrás de flag.
3. Emitir/validar tokens do emissor candidato em shadow mode (log-only).
4. Rotas privilegiadas: introspecção real (`getUser` / session store)
   antes de cortar confiança exclusiva em `getClaims`.
5. Logout/ban/revoke-all coerentes entre stacks durante dual-run.
6. Cutover por rota quando gates `PG-AAL2` e `PG-REVOCATION` estiverem
   verdes; rollback = flag off + emissor anterior (ADR 013).

### Testes obrigatórios (proposta de aceitação técnica)

| Classe | Escopo |
|--------|--------|
| **Crypto** | Allowlist `alg`, reject `none`, algorithm confusion, kid rotation, assinatura inválida, JWKS indisponível → deny |
| **Contract** | Claims `iss aud sub exp nbf iat jti role organization_id aal` sem coerção ambígua |
| **Adversarial** | Replay de refresh; CSRF sem token; AAL1 em reveal; AAL downgrade; hybrid principal; wrong-org → parity 404; ban mid-session; revoke-all sob concorrência; impersonation sem actor; SuperAdmin orgless fora da allowlist |
| **Timeout** | JWKS/session store abort → deny |

## Gates de paridade e riscos residuais

| Gate ID | Objetivo | Critério verde (proposta) |
|---------|----------|---------------------------|
| `PG-AAL2` | Paridade AAL2 em revelação de segredo | `reveal-webhook-signing-secret` (e sucessor Go) rejeita `aal1`; testes adversarial passando |
| `PG-REVOCATION` | Paridade de revogação pré-`exp` | Logout/ban/revoke-all invalida access em rotas privilegiadas **antes** de `exp`, com evidência de teste |

### Owners de risco residual

| ID | Risco | owner role | prazo | impacto | gate afetado | status |
|----|-------|------------|-------|---------|--------------|--------|
| P-AUTH-AAL2 | AAL2 ausente em `reveal-webhook-signing-secret` | QA/Security + Senior Engineer | 2026-08-08 | Revelação de segredo com sessão AAL1 | `PG-AAL2` | pending |
| P-AUTH-REV | `getClaims` sem revogação pré-`exp` | Architect + Senior Engineer | 2026-08-15 | Logout/ban ineficazes até TTL | `PG-REVOCATION` | pending |
| P-AUTH-TTL | TTL numérico do access JWT / refresh | Security Lead | 2026-08-15 | Sem número medido; só política “curto” | `PG-REVOCATION` | pending |
| P-AUTH-DUAL | Plano dual-run iss/aud/JWKS + logout coerente | Architect | 2026-08-29 | Drift de emissores / hybrid principal | security go/no-go (ADR 010) | pending |
| P-AUTH-COOKIE | Rollout SameSite=Strict + CSRF token bound à sessão | UX/Operations + Senior Engineer | 2026-08-22 | Quebra de fluxos cross-site legítimos | reliability | pending |

Cada residual exige: owner, controle, teste verificável e parity gate
associado antes de promoção a `Accepted`.

## Consequences

- **Positive:** contrato Zero-Trust explícito; JWT P0 delimitado como
  temporário; caminho dual-run alinhado ao exit ramp ADR 010; gates
  `PG-AAL2` / `PG-REVOCATION` tornam-se critérios objetivos de go/no-go.
- **Negative:** dual-run aumenta complexidade transitória; `SameSite=Strict`
  exige validação de fluxos OCC; pendências TTL/quotes não inventadas
  bloqueiam `Accepted`.
- **Security:** fail-closed e anti-oracle passam a ser requisito de
  aceite, não “best effort”; residuals AAL2/revogação ficam rastreáveis.
- **Não-consequência:** esta ADR **não** substitui o Supabase Auth em
  produção nem aprova o auth Go como implementado — apenas recomenda o
  contrato sob avaliação.
