# JWT P0 — Residual Risks (backlog)

> Status: registered after Phase 1 cryptographic JWT fix.  
> **Do not** promote into the official product roadmap until the agreed final phase.  
> Date: 2026-07-21
> Updated: 2026-07-21 — P-AAL2-01 remediado (missão isolada; **não** implica PASS Etapa −1).

## P0/P1 imediato — AAL2 em `reveal-webhook-signing-secret`

**Status: CLOSED (2026-07-21)** — `REVEAL_REQUIRE_AAL2 = true` em
`supabase/functions/reveal-webhook-signing-secret/index.ts` via
`handleWithSecurity(..., requireAAL2)`. Em produção, `aal1` → 404 INV-26;
handler não executa. Evidência: `tests/reveal_webhook_signing_secret_unit_test.ts`
(`reveal AAL2 wiring`, `aal1` reject, `aal2` allow).

Remediação **não** autoriza Etapa 0 nem altera `docs/governance/roadmap.md`.

## P1 arquitetural — Revogação pré-`exp` com `getClaims`

`auth.getClaims` valida assinatura/claims locais e **pode não refletir**
logout, ban ou revogação de sessão até o `exp` do access token.

Opções a decidir (não implementadas nesta fase):

1. TTL curto de access token + refresh controlado;
2. `getUser` / introspection nas rotas privilegiadas (SA, reveal, MFA gates);
3. Denylist de `session_id` (ou `jti`) para revogação imediata no Edge.

## Referência

Validator SSOT: `supabase/functions/shared/jwt_auth_validator.ts` (comentário Residual).
