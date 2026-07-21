# JWT P0 — Residual Risks (backlog)

> Status: registered after Phase 1 cryptographic JWT fix.  
> **Do not** promote into the official product roadmap until the agreed final phase.  
> Date: 2026-07-21

## P0/P1 imediato — AAL2 em `reveal-webhook-signing-secret`

Revelação de segredo de assinatura de webhook é operação sensível. A rota ainda
não exige AAL2 (comentário TODO / Fase 11 legada).

**Ação:** exigir `requireAAL2: true` (ou equivalente) em
`supabase/functions/reveal-webhook-signing-secret/index.ts` via
`handleWithSecurity`, com testes unitários de rejeição `aal1` em produção.

## P1 arquitetural — Revogação pré-`exp` com `getClaims`

`auth.getClaims` valida assinatura/claims locais e **pode não refletir**
logout, ban ou revogação de sessão até o `exp` do access token.

Opções a decidir (não implementadas nesta fase):

1. TTL curto de access token + refresh controlado;
2. `getUser` / introspection nas rotas privilegiadas (SA, reveal, MFA gates);
3. Denylist de `session_id` (ou `jti`) para revogação imediata no Edge.

## Referência

Validator SSOT: `supabase/functions/shared/jwt_auth_validator.ts` (comentário Residual).
