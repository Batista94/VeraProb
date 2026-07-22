# ADR 012: Ciclo de Vida de Conexão, Tenant Context e RLS Fail-Closed

**Date:** 2026-07-21
**Status:** Accepted
**Context:** Phase 11 Etapa −1 — revisão H2.1 (A portável)

> **Contrato condicional de saída.** Este ADR **não** é migração aprovada nem
> Etapa 1 imediata. Sob **A portável**, o baseline operacional permanece
> Supabase/PostgREST (`auth.jwt() ->> 'organization_id'`, INV-2). O contrato
> `SET LOCAL` / pool / txn-per-request aplica-se **somente se/quando** B ou C
> for Approved após gatilho objetivo + go/no-go (ADR-010).

### Decision record

| Campo | Valor |
|-------|-------|
| Status anterior | Proposed (revisão H2.1 — A portável) |
| Status atual | **Accepted** |
| Authority | Fundador |
| Confirmed | 2026-07-21 |
| Council | H2.1 PASS (Architect, Senior, QA/Security) + Lead PASS_DOCUMENTAL |
| Scope of acceptance | Contrato condicional B/C; baseline A = PostgREST |
| Explicitly not authorized | Proposta canônica, roadmap, Etapa 0, commit, implementação, self-host agora |

## Contexto

Se o candidato self-host (Go API + Postgres 16) for **Approved** após go/no-go
(ADR-010 B/C), o isolamento multi-tenant deixa de depender de PostgREST
injetar `auth.jwt() ->> 'organization_id'` (INV-2 atual) e passa a depender
de **contexto de tenant amarrado à transação** via `SET LOCAL app.tenant_id`,
role `app_user` sem `BYPASSRLS`, e pool em **transaction mode**.

Enquanto A portável vigorar, este ADR permanece **Accepted** apenas como
contrato condicional de saída (B/C); Supabase/PostgREST permanece o baseline
operacional. Nenhum código Go de
pool é autorizado por este documento.

Um vazamento de tenant entre borrowers do mesmo connection pool é falha
forense crítica: Tenant-A nunca pode ler/escrever dados de Tenant-B
(INV-22), inclusive sob reuso físico da conexão.

Este ADR congela critérios **testáveis** do ciclo de vida da conexão e do
harness RLS **para a saída futura**. Não inicia self-host. Status do
documento: **Accepted** (condicional B/C) — ver Errata pós-aceite.

### Artefatos relacionados

| Artefato | Papel |
|----------|-------|
| [../proposals/phase11_enterprise_pivot.md](../proposals/phase11_enterprise_pivot.md) | Plano canônico Phase 11 |
| [../proposals/phase11_threat_model.md](../proposals/phase11_threat_model.md) | STRIDE (RLS/pool bleed, oracle INV-26) |
| [../proposals/phase11_parity_checklist.md](../proposals/phase11_parity_checklist.md) | Gates de paridade / PASS −1 |
| [../proposals/phase11_edge_functions_inventory.md](../proposals/phase11_edge_functions_inventory.md) | Inventário 1:1 das 22 Edge Functions |
| [010_exit_supabase.md](010_exit_supabase.md) | Motivo e exit ramp do pivot |
| [011_auth_zero_trust.md](011_auth_zero_trust.md) | Sessão, JWT curto, MFA, SuperAdmin separado |
| [013_strangler_fig.md](013_strangler_fig.md) | Ordem Strangler e dual-run |

## Decisão

**Condicional:** se/quando uma API própria assumir a Data API (alternativa
B ou C Approved), adotar o contrato abaixo para **toda** requisição
tenant-scoped no `apps/api` (Go) e para workers/jobs que toquem dados de
organização. Critérios são obrigatórios em testes automatizados (unitários
Go + pgTAP + Red-Team de pool) antes de qualquer cutover de fatia.

Até lá: PostgREST + RLS JWT continuam; Etapa 1 de A portável implementa
revogação/DR na stack atual (ADR-011 / ADR-010), **não** este pool Go.

---

## 1. Uma transação por requisição tenant-scoped

| Critério | Testável como |
|----------|---------------|
| Middleware abre **exatamente uma** transação por request HTTP tenant-scoped | Assert de span/trace: `BEGIN` uma vez; queries filhas usam o mesmo `tx` |
| Queries fora da transação do request são **proibidas** para paths tenant-scoped | Teste estático/CI + teste de integração que falha se driver executa sem `tx` |
| Commit somente no fim bem-sucedido do handler | Mock/spy: `Commit` chamado uma vez em sucesso; nunca em erro de domínio |
| Rollback em qualquer falha pós-`BEGIN` | Spy: `Rollback` em erro de validação pós-txn, panic recuperado, timeout |

**Fora do escopo tenant-scoped:** health checks sem DB, e paths autenticados que **não** tocam tabelas com RLS de org (se existirem) — devem ser listados explicitamente no OpenAPI e no threat model; default é tenant-scoped.

---

## 2. Validação de tenant UUID antes do DB; `SET LOCAL` só dentro da txn

### 2.1 Pré-DB (aplicação)

1. Extrair `organization_id` do principal autenticado (claims de sessão/JWT conforme [ADR-011](011_auth_zero_trust.md)).
2. Validar formato UUID (RFC 4122) **antes** de obter conexão/abrir transação.
3. Autorizar que o principal pode atuar naquela org (membership / escopo). Falha → fail-closed (§3).
4. Somente então: acquire connection → `BEGIN` → definir tenant.

### 2.2 Dentro da transação

- Usar **apenas** `SET LOCAL` (nunca `SET` de sessão) para `app.tenant_id`.
- Mecanismo seguro/parametrizado obrigatório — exemplos aceitos:
  - `SELECT set_config('app.tenant_id', $1, true)` com bind parameter UUID já validado; ou
  - wrapper equivalente do driver que impede concatenação de string não sanitizada.
- **Proibido:** `SET app.tenant_id = '...'` (session-level), interpolação de string no SQL, GUCs definidos fora da transação, ou reutilizar GUC de request anterior.
- **Proibido:** qualquer bypass SuperAdmin que dependa de `SET app.tenant_id` com UUID de usuário impersonado sem trilha explícita (ver §8).

### 2.3 Predicado RLS (destino)

Policies tenant devem avaliar semanticamente:

```sql
organization_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
```

com **fail-closed** se o setting estiver ausente/vazio/não-UUID (ver §3). Catálogos globais (`organization_id IS NULL`) seguem o Global Catalog RLS Pattern já usado no repo — sem `USING (true)` permissivo para roles de cliente.

---

## 3. Fail-closed: tenant ausente, inválido ou não autorizado / sem org

| Condição | Comportamento obrigatório | Código HTTP (API sensível) |
|----------|---------------------------|----------------------------|
| Claim/org ausente | Não abre txn; não define GUC | 401 ou 404 conforme contrato Auth (ADR-011); **sem** diferenciação oracle em recursos por ID (INV-26) |
| UUID malformado | Rejeição pré-DB | Mesma classe de erro que “não encontrado” em endpoints sensíveis (INV-26) |
| Principal sem membership na org | Rejeição pré-DB ou política RLS vazia + parity | 404 em endpoints sensíveis (INV-26) |
| `app.tenant_id` ausente/vazio **durante** query (bug de middleware) | Policy não libera linhas; preferir função helper que falha fechado | Operação não retorna dados de outro tenant; incidente de segurança se detectado em CI |
| SuperAdmin / worker sem escopo explícito | Ver §8 — **não** converte silenciosamente para principal de tenant | 403/404 conforme superfície; nunca bleed |

Testes: matriz de casos (ausente / inválido / org errada / org correta) com asserts de status e de zero linhas cruzadas.

---

## 4. Pool transaction-mode, reset e ausência de estado de tenant entre borrowers

| Requisito | Critério de aceite |
|-----------|-------------------|
| Modo do pool | **Transaction mode** (conexão devolvida ao pool ao fim da txn) |
| Reset | Ao retornar ao pool: sem GUC `app.tenant_id` residual observável na próxima txn |
| Isolamento | Borrower N+1 nunca herda `app.tenant_id` de N |
| Prova | Teste com **pool size = 1** (§5) |

`DISCARD ALL` / reset do pooler (quando aplicável) não substitui `SET LOCAL`: o contrato primário é GUC **local à transação**.

---

## 5. Red-Team adversarial A↔B na mesma conexão física (pool size 1)

Harness obrigatório (**pós-aprovação B/C** / CI self-host) — **pool bleed tests**
(não confundir com Etapa 1 A portável = revogação + backup/restore):

1. Configurar pool com **tamanho 1**.
2. Tenant A: request de sucesso (leitura/escrita autorizada) → commit.
3. Tenant B: na **mesma** conexão física, request de sucesso → commit; assert de que só dados B são visíveis.
4. Bidirecional: A→B e B→A.
5. Estados de **falha** intercalados: A sucesso → B tentativa cross-tenant (deve falhar/404/zero rows) → A sucesso novamente; e simétrico.
6. Após rollback/panic/timeout/cancel de A, B não vê estado de A (§11 / máquina de estados §16).
7. Após conn broken + discard, próximo borrower obtém conexão limpa sem GUC residual.

Evidência: log de teste + (opcional) `pg_backend_pid()` estável entre requests sob pool size 1, com asserts de isolamento. Gate checklist: `PG-POOL-BLEED` / `PG-CROSS-TENANT` em [phase11_parity_checklist.md](../proposals/phase11_parity_checklist.md).

---

## 6. Roles: `app_user`, migrator, break_glass; least privilege

| Role | Privileges | BYPASSRLS | Uso |
|------|------------|-----------|-----|
| `app_user` | DML necessário em tabelas de aplicação via grants explícitos | **NÃO** | Path normal da API e workers tenant-scoped |
| `migrator` | DDL / replay de migrations | Conforme necessidade de migração; **não** usado em runtime de request | CI/CD e bootstrap |
| `break_glass` | Escopo mínimo documentado para emergência | Somente se inevitável e auditado; default preferir role sem bypass + policy explícita | Procedimento break-glass (§7) |

- Runtime de produto **nunca** conecta como `migrator`.
- `app_user` **não** possui `BYPASSRLS` (teste: `rolbypassrls = false`).
- Grants: tabelas `public` exigem grants explícitos a `app_user` (padrão INV-DATA-API-GRANT do repo); sem restaurar `ALTER DEFAULT PRIVILEGES` globais permissivos.
- Nenhuma herança indevida de privileges entre roles.

---

## 7. Break-glass

Ativação de `break_glass` (ou equivalente operacional) exige **todos**:

| Controle | Critério |
|----------|----------|
| Autorização | Dual-control / role operacional aprovada (definida no runbook; dono: Security/QA) |
| Limite de tempo | Sessão/credencial com TTL curto; expiração automática |
| Reason code | Código de motivo obrigatório (catálogo versionado; sem texto livre como único registro) |
| Audit append-only | Evento imutável (INV-3 spirit): quem, quando (UTC INV-6), reason code, escopo, ticket |
| Alerta | Notificação imediata ao canal de segurança (Pager/Slack/Sentry) na ativação e no término |

Teste: tentativa sem reason code / sem authz → negada; ativação válida → linha de audit + alerta mock assertado.

---

## 8. SuperAdmin, workers, jobs e outbox

| Superfície | Regra |
|------------|-------|
| SuperAdmin | Role/conexão **separada** e escopo explícito por ação; **proibido** `SET LOCAL app.tenant_id` com UUID de um tenant “como se fosse” o usuário impersonado sem trilha de impersonation (ADR-011) |
| Impersonation | Token/sessão de impersonation com target org explícito + revoke; audit append-only |
| Workers / jobs / outbox | Role dedicada (ou mesmo `app_user` com claim de job) + **escopo de org por mensagem** (campo `organization_id` no outbox); processar uma org por unidade de trabalho dentro de uma txn |
| Conversão silenciosa | **Proibido** promover service account / SuperAdmin a “principal de tenant” sem marcação e audit |

Inventário de funções Edge que migram para estas superfícies: ver [phase11_edge_functions_inventory.md](../proposals/phase11_edge_functions_inventory.md) e ordem em [ADR-013](013_strangler_fig.md).

---

## 9. Prepared statements e transaction pooling

| Regra | Detalhe |
|-------|---------|
| Compatibilidade | Com transaction-mode pooling, **não** depender de prepared statements nomeados que sobrevivam entre borrowers |
| Preferência | Protocolo extended com statement **unnamed** por execução, ou prepare+execute+deallocate **dentro da mesma txn**, ou desabilitar prepares nomeados no driver |
| Teste | Sob pool size 1, sequência A→B de queries preparadas não gera `prepared statement does not exist` nem reutiliza plano/sessão com GUC errado |
| Referência interna | Skill Supabase Postgres: `conn-prepared-statements` |

---

## 10. Retries somente em fronteiras idempotentes

- Retry automático de request **não idempotente** após `COMMIT` incerto é **proibido** sem chave de idempotência.
- Retry **não** reutiliza `app.tenant_id` / GUC / conexão da tentativa anterior — nova unidade de trabalho = nova txn + novo `SET LOCAL` a partir do principal autenticado.
- Ingest/telemetria: manter semântica atual (ex.: `ON CONFLICT DO NOTHING` / 200 ignored) — INV-15/idempotência de ingest.
- Outbox/webhooks: retry no worker com dedupe por id de outbox; não duplicar side-effects.
- Critério de teste: falha injetada pós-commit não gera segunda escrita financeira (INV-3).

---

## 11. Nested transactions / savepoints

**Decisão (Proposed):** nested transactions de aplicação são **proibidas** no middleware tenant.

- Um request = uma txn (§1).
- Savepoints: **proibidos** no path padrão; se um caso futuro exigir, exige ADR aditivo + testes de rollback parcial + prova de que `app.tenant_id` permanece estável — fora do escopo deste ADR.
- Teste de regressão: tentativa de `SAVEPOINT` / segunda `BEGIN` no request path falha em CI (lint ou assert de driver).

---

## 12. Adaptação de policies + harness pgTAP (`auth.jwt` → `app.tenant_id`)

Não é “troca de string”.

| Aspecto legado | Aspecto destino | Equivalência semântica |
|----------------|-----------------|------------------------|
| `auth.jwt() ->> 'organization_id'` | `NULLIF(current_setting('app.tenant_id', true), '')::uuid` | Mesmo predicado de igualdade em `organization_id` |
| Setup pgTAP: injeção de `request.jwt.claims` | Setup: `BEGIN`; `SELECT set_config('app.tenant_id', '<uuid>', true)` | Tenant efetivo idêntico ao claim de org do teste legado |
| Claims extras (role, aal) | Validados na **aplicação** (ADR-011); RLS foca org | Não empurrar MFA para GUC sem ADR |
| Ausência de claim | Fail-closed JWT | Fail-closed GUC vazio |

Harness: portar suíte existente com asserts de isolamento preservados (mesmas expectativas de PASS/FAIL), não apenas reescrever helpers.

---

## 13. Views `security_invoker`, RLS em partições, grants explícitos

Durante o replay lift-and-shift (sem redesign de schema):

| Tema | Critério |
|------|----------|
| Views `public` | `WITH (security_invoker = true)` (ci-blocks #11) |
| Partições | Cada `PARTITION OF` com `ENABLE ROW LEVEL SECURITY` + policy espelhada (ci-blocks #12) |
| Grants | Grants explícitos a roles de runtime (ci-blocks #13) |
| Policies permissivas | Proibido `USING (true)` para roles de cliente; Global Catalog Pattern quando aplicável |

---

## 14. Invariantes forenses preservadas neste ADR

| INV | Implicação operacional |
|-----|------------------------|
| **INV-3** | Ledger/finance append-only; roles de app sem `UPDATE`/`DELETE` em tabelas de ledger; break-glass não autoriza reescrita silenciosa |
| **INV-6** | Todo timestamp de audit/break-glass/outbox em UTC (`TIMESTAMPTZ`); clock da app via provider UTC |
| **INV-26** | Endpoints sensíveis: Not Found e Wrong Org → mesma resposta (404); testes de oracle obrigatórios |
| **Evidence sealing (INV-9)** | Hash/HMAC de evidência permanece no caminho de ingest/evidence; connection lifecycle não altera bytes selados nem permite leitura cross-tenant do blob |

---

## 15. Replay ordenado de migrations; sem redesign no pivot

- Replay **ordenado** e verificável das migrations existentes (lift-and-shift).
- **Proibido** neste pivot: normalizar schema, dropar colunas, fundir tabelas, “aproveitar para redesenhar”.
- Permitido: adaptação de **policies/harness/roles/grants** conforme este ADR, via migrations **append-only** novas após o replay base — não editar `.sql` já mergeados.
- ALE/KMS: adiada (proposta Phase 11); não misturar com este ciclo de vida.

---

## 16. Máquina de estados da conexão (contrato testável)

| Precondição | Ação | Cleanup | Esperado | Teste | Evidência |
|-------------|------|---------|----------|-------|-----------|
| Principal autenticado; UUID org válido e autorizado | Acquire conn → `BEGIN` → `set_config(app.tenant_id, $1, true)` → queries | `COMMIT` | Dados só da org; GUC local | Integração + pgTAP | Trace txn + assert rows |
| UUID inválido / ausente | Rejeitar **antes** de `BEGIN` | N/A (sem txn) | Sem round-trip tenant set; fail-closed | Unit middleware | Coverage matriz §3 |
| Org não autorizada | Rejeitar pré-DB ou zero-row + 404 | Sem commit de escrita | INV-26 parity | API contract test | Status + body estável |
| Sucesso parcial + erro de domínio | `ROLLBACK` | Devolver conn ao pool | Nenhuma escrita persistida | Integração com falha injetada | Spy Rollback + DB assert |
| Panic no handler | Recover → `ROLLBACK` | Discard/return conforme driver | Sem GUC residual; pool saudável | Chaos/unit | Stack + pool metrics |
| Timeout / cancel do client | Abort txn → `ROLLBACK` | Return ou discard se conn broken | Sem bleed para próximo borrower | Teste cancel + pool size 1 | pid + isolamento B limpo |
| Conn broken (I/O) | Não reutilizar | **Discard** do pool | Próximo request obtém conn nova | Fault injection | Pool “removed” counter |
| Commit OK | Return ao pool | — | Próximo borrower sem `app.tenant_id` | Pool size 1 A→B | `current_setting` vazio no início da txn B |
| Rollback OK | Return ao pool | — | Idem | A rollback → B sucesso | Isolamento B |
| Retry após falha ambígua | Só se fronteira idempotente (§10); nova txn + novo SET LOCAL | — | Sem duplicar ledger; sem reusar GUC antigo | Idempotency test | Contagem de rows append-only |
| Break-glass ativado | Authz + TTL + reason + audit + alert | Expirar credencial; alert fim | Trilha append-only | Runbook test | Audit row + alert mock |
| Worker outbox msg org X | Txn + `SET LOCAL` = X | Commit/Rollback | Só org X | Worker test | Payload org + rows |
| Tentativa `SET` session-level | Bloqueada por lint/wrapper | — | CI fail | Static check | Scanner/lint rule |
| Tentativa nested txn/savepoint | Bloqueada (§11) | — | CI fail | Driver assert | Log proibição |

### Mapeamento commit / rollback / panic / timeout / cancel / broken / return-or-discard

| Evento | Ação na txn | Destino da conexão | Nota |
|--------|-------------|--------------------|------|
| Sucesso limpo | `COMMIT` | **Return** ao pool | Estado tenant descartado com fim da txn (`SET LOCAL`) |
| Erro de aplicação / domínio | `ROLLBACK` | **Return** | |
| Panic recuperado | `ROLLBACK` | **Return** se conn saudável; senão **Discard** | |
| Timeout server-side | `ROLLBACK` | **Return** ou **Discard** se marcada broken | |
| Cancel cliente | `ROLLBACK` | **Return** / **Discard** se incomplete | |
| Conn broken | Abort | **Discard** obrigatório | Nunca return broken |
| Indeterminado pós-commit | Não retry cego | — | Só idempotent boundary |

---

## Alternativas consideradas

| Alternativa | Motivo de rejeição |
|-------------|-------------------|
| Manter `auth.jwt()` no Postgres self-hosted via extensão compat | Acoplamento a claims HTTP no DB; hard de operar com pool Go; foge do modelo SET LOCAL decidido no plano |
| `SET` session-level + reset manual | Frágil sob panic/timeout; alto risco de pool bleed |
| Session-mode pooling para “facilitar prepared statements” | Pior densidade de conexões; incentiva estado de sessão; conflita com objetivo de isolamento por txn |
| BYPASSRLS em `app_user` + filtro só na app | Viola defesa em profundidade INV-2/22 |

## Consequências

- **Positivas:** Isolamento testável sob reuso de conexão **quando** B/C for
  aprovado; contrato de saída explícito sem forçar migração agora.
- **Negativas / custo:** Se B/C avançar — reescrita do harness pgTAP;
  disciplina de drivers/prepared statements; roles extras.
- **Risco residual (só pós-aprovação B/C):** middleware sem `SET LOCAL` —
  mitigado por fail-closed + pool size 1 + scanner.
- **Não-consequência:** sob A portável este ADR **não** agenda Etapa 1
  self-host nem altera o baseline PostgREST.

Status deste documento: **Accepted** (contrato condicional B/C). Budgets
quantitativos: `pending_baseline` até medição pós-gatilho B/C.

---

## Errata documental pós-aceite

**Date:** 2026-07-21
**Authority:** AUTH-E0 (fundador) · Documentation Owner
**Escopo:** Correção editorial de menções internas obsoletas a `Proposed` que
conflitavam com o header `**Status:** Accepted` e o Decision record.
**Não altera:** Decision, Alternatives, Consequences, escopo condicional B/C,
baseline PostgREST sob A portável, nem autoriza implementação.

| Local (pré-errata) | Correção |
|--------------------|----------|
| §Contexto: “este ADR estiver `Proposed` sem promoção” | Texto alinhado a **Accepted** como contrato condicional B/C |
| §Contexto: “Status: **Proposed**” | “Status do documento: **Accepted** (condicional B/C)” |

Referência: [phase11_etapa0_executable_specs.md](../proposals/phase11_etapa0_executable_specs.md) (R-E0-05).
