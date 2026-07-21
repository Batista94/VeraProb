# ADR 013: Strangler Fig — Ordem de Fatias, Dual-Run e Cutover

**Date:** 2026-07-21
**Status:** Proposed
**Context:** Phase 11 Etapa -1

## Contexto

**Se** o go/no-go de ADR-010 aceitar o candidato self-host, a Phase 11 migra **gradualmente** (Strangler Fig) a superfície Flutter + Supabase Edge Functions + Supabase Auth para Go (`apps/api`) + Postgres 16 + React (`apps/web`), preservando o motor forense e o schema via lift-and-shift. Enquanto este ADR estiver `Proposed`, Flutter/Supabase permanecem a stack de produção.

**Big-bang** (desligar Flutter/Supabase e ligar React/Go no mesmo instante) é **proibido**: risco inaceitável para INV-22 (isolamento), INV-9/28 (evidência/HMAC), INV-26 (anti-oracle) e continuidade B2B.

Este ADR define a ordem Strangler Fig, o mapeamento **candidato** das 22 Edge Functions reais, flags, dual-run/shadow, critérios objetivos de paridade, rollback e decommission. Status: **Proposed** — não Accepted.

### Artefatos relacionados

| Artefato | Papel |
|----------|-------|
| [../proposals/phase11_enterprise_pivot.md](../proposals/phase11_enterprise_pivot.md) | Plano canônico Phase 11 |
| [../proposals/phase11_edge_functions_inventory.md](../proposals/phase11_edge_functions_inventory.md) | Inventário 1:1 (destino handler/worker/storage/defer) |
| [../proposals/phase11_threat_model.md](../proposals/phase11_threat_model.md) | STRIDE por superfície |
| [../proposals/phase11_parity_checklist.md](../proposals/phase11_parity_checklist.md) | Gates de paridade e evidência |
| [010_exit_supabase.md](010_exit_supabase.md) | ROI / exit ramp |
| [011_auth_zero_trust.md](011_auth_zero_trust.md) | Sessão, MFA, impersonation |
| [012_rls_connection_lifecycle.md](012_rls_connection_lifecycle.md) | `SET LOCAL`, pool, fail-closed |

## Decisão

Migrar por **fatias ordenadas** atrás do mesmo contrato OpenAPI, com **dual-run** até gates PASS, feature flags por rota/função, e preservação do stack legado até cutover explícito por superfície.

---

## 1. Proibição de big-bang

| Proibido | Obrigatório |
|----------|-------------|
| Cutover único de todo o produto | Cutover por fatia / rota / função |
| Remover Flutter ou Supabase Auth antes dos gates da fatia | Manter dual-stack até critérios §8–§11 |
| Reescrever UI React antes da paridade da API correspondente | React só após fatia API PASS (etapa 7) |
| Redesign de schema “no mesmo PR do strangler” | Lift-and-shift + ADR-012 apenas |

Violação = VETO de Lead Reviewer / QA-Sec.

---

## 2. Ordem fixa de fatias (7)

Ordem **inegociável** (primeira superfície = maior risco forense):

| # | Fatia | Objetivo de risco |
|---|-------|-------------------|
| **1** | Health + Auth / session | Estabelecer identidade Zero-Trust, MFA step-up, revogação (ADR-011) antes de qualquer dado sensível |
| **2** | Ingest + HMAC (INV-28) | Telemetria não confiável até normalizada; segredo por org; selagem |
| **3** | Evidence | Proxy/hash/upload; anti-oracle INV-26; sealing INV-9 |
| **4** | Read APIs | OCC / Fila Auditora / Contracts / projeções de leitura |
| **5** | Webhooks / workers | Outbox, Telegram, notificações; side-effects únicos |
| **6** | SuperAdmin | Escopo privilegiado separado; nunca misturar com tenant pool comum sem audit |
| **7** | React route-by-route | UI somente após paridade da API daquela rota |

Nenhuma fatia N+1 entra em dual-run de escrita sem a fatia N ter critérios de enable satisfeitos (§8), salvo dependência explícita documentada no inventário (ex.: health sempre ligado).

---

## 3. Mapeamento candidato: inventário real (22 funções)

Fonte: diretórios `supabase/functions/*/index.ts` (exclui `shared/`, `tests/`, `node_modules/`).  
**Isto não presume buckets fechados** — é mapeamento **candidato** com justificativa; o inventário canônico 1:1 em [phase11_edge_functions_inventory.md](../proposals/phase11_edge_functions_inventory.md) pode refinar destino (`apps/api` | worker | storage | defer) sem alterar a **ordem** das fatias.

| Função | Fatia candidata | Justificativa |
|--------|-----------------|---------------|
| `revoke-user-sessions` | **1** Auth | Revogação de sessão; pré-requisito Zero-Trust |
| `issue-impersonation-jwt` | **1** Auth (com gate SuperAdmin) | Emite JWT de impersonation; contrato Auth antes de proxy privilegiado; cutover de *uso* operacional amarra-se à fatia **6** |
| `revoke-impersonation` | **1** Auth (com gate SuperAdmin) | Par simétrico de impersonation; mesma dualidade 1↔6 |
| `generate-org-secret` | **2** Ingest/HMAC | Segredo HMAC por org (INV-28); necessário antes/durante ingest confiável |
| `verify-ledger-hmac` | **2** Ingest/HMAC | Verificação HMAC on-read do ledger; mesma família criptográfica INV-28 |
| `ingest-sascar` | **2** Ingest | ACL hardware → seal SHA-256 → canonical facts; idempotência |
| `ingest-omnitracs` | **2** Ingest | Par de ingest Omnitracs; mesmo pipeline Zero-Trust |
| `secure-evidence-proxy` | **3** Evidence | Proxy de evidência com binding de `organization_id` |
| `verify-evidence-hash` | **3** Evidence | Integridade de hash de evidência (INV-9) |
| `get-justification-upload-url` | **3** Evidence | URL assinada de upload; storage path |
| `portal-finalize-upload` | **3** Evidence | Finaliza upload (quarantine → seal); side-effect de storage |
| `portal-submit-request` | **3** Evidence / portal | Submissão de portal ligada a evidência/fila; candidata a API atrás do mesmo contrato |
| `dispute-portal-evidence` | **3** Evidence | Evidência de disputa no portal |
| `auditor-dispute-evidence` | **3**–**4** Evidence→Read | Leitura/serving de evidência para auditor; pode habilitar read após seal path estável — **não** fechar bucket sem inventário |
| `notify-invite` | **5** Workers | Notificação transacional; side-effect de email |
| `notify-sla-breach` | **5** Workers | Alerta de breach; worker/outbox |
| `dispatch-carrier-notifications` | **5** Workers | Drena `carrier_notification_outbox` |
| `dispatch-verdict-webhooks` | **5** Webhooks | Webhooks de veredito; exatamente-um side-effect owner |
| `telegram-webhook` | **5** Webhooks | Ingress Telegram + binding org; evidência/chat |
| `reveal-webhook-signing-secret` | **5**–**6** Webhooks/SuperAdmin | Reveal de segredo de webhook; privilegiado — exigir MFA/step-up (ADR-011) |
| `log-security-incident` | **1** ou **6** (transversal) | Logging de incidente de qualquer autenticado; deploy cedo (Auth) com retenção SuperAdmin — candidata transversal, não bucket rígido |
| `super-admin-proxy` | **6** SuperAdmin | Proxy service-role; audit log; última fatia de API privilegiada |

**Health:** endpoint novo em Go (sem Edge Function homônima no inventário atual) — fatia **1**.

**Read APIs OCC (fatia 4):** hoje majoritariamente PostgREST/Flutter repositories, não Edge Functions. A fatia 4 cobre projeções/queries já usadas pelo OCC; Edge Functions da tabela acima que forem predominantemente leitura podem *habilitar* na 4 após 3, conforme inventário — sem presumir lista fechada.

---

## 4. Feature flag por rota / função

| Regra | Detalhe |
|-------|---------|
| Granularidade | Flag por rota OpenAPI **e/ou** por função Edge espelhada |
| Default seguro | **OFF** para stack nova (tráfego permanece no legado) |
| Owner | Nomeado no inventário / checklist (default sugerido: Engineering owner da fatia + aprovação QA-Sec para fatias 2, 3, 6) |
| Mudança de estado | enable / pause / revert / decommission com critérios §8 |
| Audit | Mudança de flag registrada (quem, quando UTC, reason) |

---

## 5. Dual-run e shadow comparison

### 5.1 Modo default

- Shadow **read-only** por default: stack nova executa em paralelo para comparação; **não** é owner de side-effect.
- Um único **side-effect owner** por operação (legado **ou** novo — nunca ambos escrevendo).
- Write suppression / sandbox / idempotency keys obrigatórios quando a stack nova estiver em shadow perto de mutações (webhooks, notificações, storage, ledger).

### 5.2 Canonicalização para comparação

Antes do diff, normalizar:

| Dimensão | Regra |
|----------|-------|
| Money | Centavos inteiros (INV-4); sem float |
| UTC | Instantes em UTC / `TIMESTAMPTZ` (INV-6); rejeitar offset local ambíguo |
| IDs | UUIDs canônicos; order-insensitive onde aplicável |
| Hashes | Hex lowercase; comparar digest, não payload cru variável |
| Errors | Classe de erro / status INV-26; **não** comparar strings de infra (`$e`, stack) |
| Ordering | Ordenação determinística de coleções antes do diff |

### 5.3 Critérios objetivos de paridade (definição)

Paridade de uma fatia = **PASS** somente se:

1. Diff shadow (após canonicalização) dentro da tolerância **documentada no checklist** (sem inventar limiares numéricos neste ADR).
2. Matriz INV-26 (not found vs wrong org) idêntica em status.
3. Red-Team cross-tenant da fatia PASS (inclui pool bleed onde houver DB — ADR-012).
4. Idempotência de escrita preservada nos casos de ingest/outbox cobertos pelos testes existentes portados.
5. Nenhum side-effect duplicado sob falha injetada.
6. Critérios de segurança e capacidade da fatia atendidos conforme gates do checklist (valores numéricos = `pending_baseline` até medição).

Números de SLO/error budget/performance: **`pending_baseline`** (§6) — não bloquear definição qualitativa acima.

---

## 6. Observabilidade: SLO / error budget — `pending_baseline`

| Item | Estado neste ADR |
|------|------------------|
| SLOs de latência/disponibilidade por fatia | **`pending_baseline`** — medir em dual-run antes de fixar números |
| Error budget / divergence budget | **`pending_baseline`** — sem percentuais inventados |
| Período mínimo de estabilidade pré-cutover | **`pending_baseline`** — duração só após fonte/medição no checklist |
| Performance / capacity budgets | **`pending_baseline`** — ver PG-PERFORMANCE / PG-CAPACITY |
| Instrumentação mínima | Traces por request id / correlation id; logs sem PII; métricas de shadow diff count / side-effect owner |

Qualquer número publicado depois deve vir de medição registrada em [phase11_parity_checklist.md](../proposals/phase11_parity_checklist.md) ou relatório anexo — não neste ADR Proposed.

Error/divergence budgets **nunca** toleram: bypass auth, tenant/pool bleed, principal híbrido, falha AAL2 no reveal, revogação inválida, mutação append-only, quebra INV-26 ou INV-28 — esses gates são binários (zero falha aceita).

---

## 7. Rollback < 15 minutos

| Elemento | Requisito |
|----------|-----------|
| Objetivo | Reverter tráfego da fatia para stack legado em **< 15 min** |
| Mecanismo | Flag/DNS/route switch — sem migrate destrutiva |
| Exercício | Rollback **exercitado** em staging (ou drill) antes do cutover prod da fatia |
| Autoridade | Owner da flag + on-call; lista no runbook |
| Comms | Canal #incident / stakeholders B2B notificados no drill e no real |
| Preservação de dados | Rollback de rota **não** apaga dados; append-only preservado (INV-3); evidências seladas intactas; sessão/side-effects coerentes com retorno ao legado |

Teste de aceite do drill: cronômetro < 15 min do decisão→tráfego legado; checklist de comms assinado. Gate: `PG-ROLLBACK`.

---

## 8. Critérios enable / pause / revert / decommission (por função ou rota)

| Estado | Critérios |
|--------|-----------|
| **Enable** (tráfego real na stack nova) | Gates de paridade §5.3 PASS; Red-Team PASS; flag owner aprova; shadow estável pelo período definido no checklist (`pending_baseline`, sem inventar duração aqui); rollback drill feito |
| **Pause** | Shadow diff acima do limiar do checklist; incidente de segurança; erro budget estourado (quando baseline existir); owner ou QA-Sec |
| **Revert** | Pause + flag OFF em < 15 min; postmortem se dados/side-effects; proibido “consertar só em prod” sem teste |
| **Decommission** (desligar rota/função legada) | Ver §11 |

---

## 9. Preservação Flutter + Supabase durante dual-run

- Flutter Web permanece cliente de produção das rotas não migradas.
- Edge Functions e Supabase Auth permanecem owner de side-effect até enable da fatia correspondente.
- Instruções de agentes (Etapa 0+) devem manter **dual-stack** (“legado” vs “alvo”) — não apagar regras Flutter/Supabase neste ADR nem antes do cutover da fatia.
- Retorno à stack antiga permanece possível enquanto compatível (sessão, dados, side-effects).
- Postgres legado e Postgres alvo (quando em dual) seguem contrato ADR-012 no alvo; legado mantém RLS JWT até desligamento.

---

## 10. React (fatia 7) — regra de ouro

- Nenhuma rota React em produção sem API Go daquela capacidade em paridade PASS.
- Migração **tela a tela** (Dashboard, Fila Auditora, Tenant Admin, etc.) espelhando OpenAPI.
- CSRF header em mutações (ADR-011).
- Design tokens: portar de `.kiro/steering/ux-standards.md` — sem reinventar tema.

---

## 11. Desligar rota / função legada

Somente quando **todos** forem verdadeiros:

1. Gates de paridade §5.3 **PASS** para a superfície (evidência registrada).
2. Período de estabilidade em produção com flag ON (duração = `pending_baseline` no checklist; **não inventada aqui**).
3. Rollback **exercitado** com sucesso (< 15 min) para aquela superfície.
4. Aprovação explícita do **owner** da flag + QA-Sec (fatias 2, 3, 6) + Lead Reviewer no cutover amplo.
5. Inventário atualizado: destino `decommissioned` com data UTC.

“A nova funciona” **nunca** é evidência suficiente. Até lá: legado permanece disponível para revert.

---

## Alternativas consideradas

| Alternativa | Motivo de rejeição |
|-------------|-------------------|
| Big-bang cutover | Risco forense e de continuidade B2B inaceitável |
| UI-first (React antes da API) | Duplica contratos; atrasa parity gates; viola ordem de risco |
| Migrar SuperAdmin primeiro | Amplia blast radius privilegiado antes de Auth/RLS/ingest estáveis |
| Dual-write permanente | Dois side-effect owners; risco de divergência de ledger (INV-3/15) |

## Consequências

- **Positivas:** Risco forense priorizado; rollback rápido; inventário rastreável; Flutter/Supabase como rede de segurança.
- **Custo:** Dual-run e shadow exigem canonicalização e disciplina de flags; fatia 4 (reads) precisa de inventário além das Edge Functions.
- **Dependências:** ADR-011 (Auth) e ADR-012 (RLS/pool) são pré-requisitos duros das fatias 1–3.

Status deste documento: **Proposed**. Budgets numéricos de SLO/performance/estabilidade: `pending_baseline` até fonte medida no checklist.
