# Architecture Plan: Financial Guard (Penalty Stop-Loss Cap)

**Status:** DESIGN-ONLY — nenhum código de produção (Dart/TS/SQL) faz parte desta entrega.
**Milestone:** READY FOR FIRST TENANT — Bloqueador #2 (`docs/governance/roadmap.md`).
**Data:** 2026-07-04. **Revisão:** v2 (v1 recebeu NO-GO duplo do Council; remediações em §8).
**Invariantes governantes:** INV-3 (append-only), INV-4 (BIGINT cents), INV-5 (arredondamento bps), INV-6 (UTC), INV-10 (exceções tipadas), INV-15 (replay determinístico), INV-16 (budget de conexões), INV-18 (Zero-Trust telemetria), INV-22 (isolamento de tenant), INV-26 (anti-oracle).

---

## 0. Problema de negócio e ameaça

Falha de hardware em sensor de telemetria pode emitir milhares de alertas falsos por minuto. O motor de SLA (`contractual_evaluation_engine.dart`) converte cada alerta em evento penal no ledger com `fine_cents` calculado. Sem circuit breaker financeiro:

| Ameaça | Consequência |
| --- | --- |
| Multas infinitas em minutos | Violação de teto contratual → passivo jurídico massivo |
| Race condition em rajada (N inserts no mesmo ms) | Cap burlado por leitura assíncrona (TOCTOU) |
| Relógio de sensor corrompido espalha eventos em meses fabricados | Cada bucket mensal nasce com headroom cheio → cap burlado pela própria falha que ele deveria conter |
| Truncamento sem trilha | Verdicts não auditáveis → quebra da promessa forense (<10s) |

**Princípio central:** o Guard corta a **multa**, nunca o **fato forense**. A infração é sempre registrada (Zero-Trust, INV-18); apenas o valor financeiro é limitado. Rejeitar o INSERT destruiria evidência.

## 0.1 Desvio de premissa: `sla_infractions` não existe

O pedido original referencia uma tabela `sla_infractions`. Ela **não existe** no schema. Penalidades são eventos no ledger append-only `sla_audit_ledger_v2` (hash-particionado por `organization_id`, 4 partições `p0..p3`), com valor em **`payload -> 'verdict_evidence' ->> 'fine_cents'`** (BIGINT cents, INV-4 — caminho aninhado; NÃO existe chave `fine_cents` top-level em nenhuma linha real), fluindo para `sanction_review_queue.verdict_evidence` via trigger de fila (`20260406000002`). A "expansão da tabela de infrações" é portanto projetada sobre o schema real:

1. **Enriquecimento do `payload` do ledger** no BEFORE INSERT (trilha dupla selada — ledger é imutável pós-insert via `trg_ledger_v2_no_update/no_delete`).
2. **Tabela de acúmulo mensal tipada** (nova) para a soma O(1) sob lock.

Escritores/leitores verificados do caminho aninhado: `sla_ledger_mapper.dart:359-374` (escritor), `20260907000001` linha 168 e `20260819000001` linha 290 (leitores SQL), `20260406000002` linha 34 (propagação p/ fila).

Tipo penal vivo hoje: **apenas `SANCTION_RECOMMENDED`** (o engine sempre emite esse tipo — `contractual_evaluation_engine.dart:683-692`; `NO_SHOW_PENALTY` existe só como label/enum in-memory, nunca como `type` de ledger). O `WHEN` do trigger mantém ambos por defesa-em-profundidade futura, com essa realidade documentada.

---

## 1. Database Schema & Ledger

### 1.1 Teto financeiro no contrato

| Objeto | Mudança | Padrão reutilizado |
| --- | --- | --- |
| `contracts` | `ADD COLUMN monthly_penalty_cap_cents BIGINT NULL` | Espelha `financial_ceiling_cents` (`20260310240000`) |
| `contracts` | `CHECK (monthly_penalty_cap_cents IS NULL OR monthly_penalty_cap_cents > 0)` via 3-step `NOT VALID → VALIDATE` | INV-DB zero-downtime (ci-blocks #1) |
| `contract_financial_amendments` | `ADD COLUMN monthly_penalty_cap_cents BIGINT NULL` | SSOT versionado, append-only (`20260816000002`) |
| RPC `amend_contract_financial_terms` | Novo parâmetro opcional + denormalização p/ `contracts` | Mesmo fluxo de `penalty_multiplier_bps` (`20260816000003`) — CUIDADO: basear no ÚLTIMO CREATE OR REPLACE da função, não no original; manter nomes de parâmetros existentes (PGRST202) |

Semântica: `NULL` = sem teto (kill-switch por contrato; rollout gradual por tenant sem flag global). `financial_ceiling_cents` (teto absoluto do contrato) permanece intocado e ortogonal — o Guard é **mensal**.

### 1.2 Acumulador mensal — `contract_penalty_monthly_accrual` (nova tabela)

| Coluna | Tipo | Nota |
| --- | --- | --- |
| `organization_id` | `UUID NOT NULL REFERENCES organizations(id)` | INV-1 |
| `contract_id` | `UUID NOT NULL` | FK → `contracts(id)`. Ledger armazena `contract_id` como TEXT → cast `::uuid` obrigatório |
| `month_utc` | `DATE NOT NULL` | Bucket clamped (ver §2.3.1) — INV-6 |
| `accrued_cents` | `BIGINT NOT NULL DEFAULT 0 CHECK (accrued_cents >= 0)` | Soma dos `fine_cents` APLICADOS |
| `cap_cents_snapshot` | `BIGINT NOT NULL` | Cap vigente no primeiro accrual do mês (auditoria de mudança mid-month) |
| `cap_reached_at_utc` | `TIMESTAMPTZ NULL` | Idempotência do evento de breach |
| `warned_at_utc` | `TIMESTAMPTZ NULL` | Idempotência do early-warning (80%) |
| `updated_at_utc` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | |
| **PK** | `(organization_id, contract_id, month_utc)` | Uma linha por contrato-mês |

Obrigatório na migration: `COMMENT ON TABLE contract_penalty_monthly_accrual IS 'LOCK ORDER INVARIANT: sempre contracts (FOR UPDATE) ANTES desta tabela. Escrita exclusiva via financial guard functions.'` — o invariante anti-deadlock fica descobrível via `\d+`, não só em prosa de plano.

### 1.2.1 Marcador de crédito — `financial_guard_credits` (nova tabela, exactly-once)

| Coluna | Tipo | Nota |
| --- | --- | --- |
| `organization_id` | `UUID NOT NULL` | |
| `sanction_ledger_entry_id` | `UUID NOT NULL` | ID da linha `SANCTION_RECOMMENDED` original cujo fine foi anulado |
| `credited_cents` | `BIGINT NOT NULL CHECK (credited_cents >= 0)` | |
| `credited_at_utc` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | |
| **PK** | `(organization_id, sanction_ledger_entry_id)` | `INSERT ... ON CONFLICT DO NOTHING` = gate exactly-once |

Idempotência do crédito **auto-contida no Financial Guard** — independente da máquina de estados de `sanction_review_queue` (que pode ser afrouxada no futuro, ex.: `dispute_round` recycling já existe). Append-only por construção (sem policies/paths de UPDATE/DELETE).

Governança de ambas as tabelas:

- **Classificação:** projeção/estado operacional do guard. NÃO é ledger — INV-3 não exige append-only no acumulador; a fonte de verdade auditável é o ledger enriquecido. Precedente ativo de projeção financeira mutável: `sanction_review_queue.status/reviewed_at`, mutada por todos os RPCs de approve/reject/dispute hoje. (`contractual_financial_snapshot_v2` NÃO é citado como precedente — é vestigial, zero referências em `lib/` e zero write-path.)
- **Escrita:** exclusivamente via funções SECURITY DEFINER do Guard. RLS: `SELECT` org-scoped via `auth.jwt() -> 'app_metadata' ->> 'org_id'` (padrão unificado `20260317000001`; NUNCA o claim legado top-level — trap de zero-rows silencioso); nenhuma policy de INSERT/UPDATE/DELETE para roles cliente.
- **Grants explícitos (INV-DATA-API-GRANT):** `SELECT` para `authenticated`; `ALL` para `service_role`; nada para `anon`.
- **Motivação O(1):** somar o valor aninhado no ledger hash-particionado a cada INSERT seria O(n) no hot path exato da tempestade. O acumulador reduz o custo por infração a 1 leitura + 1 upsert sob lock.

### 1.3 Trilha de auditoria dupla (enriquecimento do payload do ledger)

O trigger BEFORE INSERT reescreve `NEW.payload` (permitido — não é UPDATE; imutabilidade só sela pós-insert). **Caminhos JSONB exatos:**

| Chave (caminho) | Escrita | Semântica |
| --- | --- | --- |
| `payload -> 'verdict_evidence' ->> 'fine_cents'` | `jsonb_set(NEW.payload, '{verdict_evidence,fine_cents}', to_jsonb(v_applied))` | Valor efetivamente aplicado pós-corte. **Corrigir NO LOCAL ANINHADO é obrigatório**: `sanction_review_queue.verdict_evidence`, `carrier_notification_outbox.fine_cents` (`20260907000001:168`) e `persist_evidence_snapshot` (`20260819000001:290`) leem esse caminho — só assim os leitores existentes enxergam o valor capado sem nenhuma mudança |
| `payload ->> 'original_fine_cents'` (top-level) | trigger | Valor que a regra calculou (Dart, `Money.multiplyByBps`) — copiado do aninhado ANTES do corte |
| `payload ->> 'cap_truncated'` (top-level) | trigger | `true` somente quando `applied < original` |
| `payload ->> 'cap_remaining_before_cents'` (top-level) | trigger | Headroom no instante do insert — sela a ordem de chegada para replay determinístico (INV-15) |
| `payload ->> 'cap_check_deferred'` (top-level) | trigger | `true` só no caminho de lock_timeout (§2.2) — marca linha para true-up assíncrono |

**Anti-forgery:** o trigger escreve as 4 chaves de auditoria **incondicionalmente**, sobrescrevendo qualquer valor pré-populado pelo cliente (cenário pgTAP #15 obrigatório). Nenhuma chave de guard é jamais lida do input.

Ledger e `sanction_review_queue` já possuem triggers de imutabilidade → trilha dupla selada pelo pipeline existente sem código novo de selagem.

---

## 2. Concorrência e Isolamento Transacional (Core)

### 2.1 Ponto de interceptação

`trg_financial_guard` — `BEFORE INSERT ON sla_audit_ledger_v2 FOR EACH ROW WHEN (NEW.type IN ('SANCTION_RECOMMENDED','NO_SHOW_PENALTY'))`. Trigger no PAI particionado propaga automaticamente às 4 partições (PG17; precedente: `trg_ledger_v2_no_update/no_delete` também só no pai) — coberto por pgTAP positivo nas 4 partições (cenário #16). Função `enforce_financial_guard()` `SECURITY DEFINER SET search_path = ''`.

**Ordem de disparo:** hoje `enforce_tenant_envelope_ledger` < `trg_financial_guard` por ordem alfabética (regra do Postgres p/ mesmo timing) — correto, mas frágil a renames. pgTAP asserta a ordem lida de `pg_trigger` (cenário #19); qualquer trigger BEFORE INSERT futuro no ledger DEVE respeitar a convenção de nome documentada na migration.

Sequência dentro da função (fail-fast, INV-10):

1. **Validação de claim (INV-22 defesa-em-profundidade):** SECURITY DEFINER bypassa RLS em `contracts`/acumulador; a policy `WITH CHECK` do ledger só avalia DEPOIS dos BEFORE triggers. Portanto, primeira linha: se o role da sessão não for `service_role`, `NEW.organization_id` DEVE igualar `(auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid`, senão `RAISE ... USING ERRCODE = 'insufficient_privilege'` — fecha o side-channel de lock cross-tenant (org forjada adquirindo `FOR UPDATE` em contrato alheio antes do rollback da RLS). Mesmo padrão de `approve_sanction`/`dispute_sanction`.
2. `payload -> 'verdict_evidence' ->> 'fine_cents'` ausente ou `<= 0` → passthrough (evento penal sem multa é válido).
3. `NEW.contract_id` NULL ou não-UUID em tipo penal com multa → `RAISE ... USING ERRCODE = 'integrity_constraint_violation'` (condition name real — nomes inventados explodem em runtime).

### 2.2 Estratégia de lock: `SELECT ... FOR UPDATE` na linha do contrato

```text
Fase 0 (fast path, sem lock):
    SELECT monthly_penalty_cap_cents FROM public.contracts
     WHERE id = NEW.contract_id::uuid AND organization_id = NEW.organization_id;
    → NULL? RETURN NEW (zero custo para contratos sem cap).

Fase 1 (serialização, com teto de espera):
    SET LOCAL lock_timeout = '2s';   -- valor final calibrado na implementação
    SELECT monthly_penalty_cap_cents INTO v_cap FROM public.contracts
     WHERE id = ... AND organization_id = ...
     FOR UPDATE;                     -- lock-then-check: re-lê o cap JÁ sob lock
                                     -- (template: super_admin_archive_organization, 20260905000004)
    → lock_timeout estourou? Caminho de degradação (abaixo).
    → cap virou NULL entre fase 0 e 1? RETURN NEW.

Fase 2 (acúmulo, já serializado por contrato):
    INSERT INTO contract_penalty_monthly_accrual (org, contract, month, accrued_cents, cap_cents_snapshot)
    VALUES (..., 0, v_cap)
    ON CONFLICT (organization_id, contract_id, month_utc) DO NOTHING;
    SELECT accrued_cents, cap_reached_at_utc, warned_at_utc INTO v_row ... ;  -- leitura simples: já serializada pela Fase 1
```

**Caminho de degradação (lock_timeout):** o insert forense passa **sem truncamento** com `cap_check_deferred = true` no payload; o job de reconciliação (§5) faz o true-up assíncrono do acumulador. Racional: escolher entre (a) segurar conexão indefinidamente na fila do lock — com writes single-row via PostgREST (`postgres_sla_audit_ledger_repository.dart:73-77`), uma tempestade num único contrato enfileiraria dezenas de conexões e exauriria o pool de 60 (INV-16): o mecanismo de segurança viraria o vetor de DoS — ou (b) perder o evento forense (inaceitável, INV-18). O deferred preserva evento E conexões; o overshoot residual é limitado à janela do timeout e detectado/corrigido pela reconciliação. Cenário pgTAP/integração #18.

Por que isso fecha a race: **toda** transação que insere penalidade para o contrato X precisa do row lock em `contracts(X)` antes de ler o acumulador. Dezenas de inserts no mesmo milissegundo enfileiram no lock (até o teto do timeout); cada um vê o `accrued_cents` commitado pelo anterior. TOCTOU eliminado no nível do banco — nenhuma leitura assíncrona de aplicação participa da decisão.

Decisões de concorrência:

| Decisão | Justificativa |
| --- | --- |
| `FOR UPDATE` bloqueante + `SET LOCAL lock_timeout` | Fila curta = throttle desejado; fila patológica = degradação graciosa via deferred, nunca perda de evento nem exaustão de pool. `NOWAIT` (padrão dos RPCs de disputa) falharia inserts legítimos exatamente no pico |
| Ordem de lock fixa: `contracts` → `accrual` | Anti-deadlock. Selada via `COMMENT ON TABLE` (§1.2). Qualquer função futura que toque ambos DEVE seguir a mesma ordem |
| Alternativa rejeitada: `pg_advisory_xact_lock(hashtextextended(org‖contract‖month))` | Funciona (padrão dos 22 RPCs de portal), mas: (a) risco teórico de colisão de hash entre contratos, serializando tenants alheios (viola espírito INV-22); (b) invisível em `pg_locks` por objeto; (c) a linha do contrato existe sempre — lock natural, auditável, sem chave sintética |
| Interação com `amend_contract_financial_terms` | O amend faz UPDATE em `contracts` → conflita com o `FOR UPDATE` do Guard → mudanças de cap serializam-se naturalmente com a tempestade. Correto por construção |
| INV-16 (60 conexões) | Zero conexões novas; hold-time limitado pelo lock_timeout |

### 2.3 Matemática de truncamento

Domínio: centavos puros (BIGINT). Nenhum arredondamento novo — o arredondamento bps (INV-5, `(cents*bps+5000) ~/ 10000`) permanece exclusivamente no Dart, upstream.

```text
v_remaining := GREATEST(v_cap - v_accrued, 0);
v_applied   := LEAST(v_original, v_remaining);
```

| Cenário | `original` | `remaining` | `applied` | `cap_truncated` | Evento |
| --- | --- | --- | --- | --- | --- |
| Abaixo do cap | 10.000 | 50.000 | 10.000 | `false` | — |
| **Cruzamento parcial (corte parcial)** | 10.000 | 4.000 | 4.000 | `true` | `FINANCIAL_CAP_REACHED` (1ª vez) |
| Borda exata (`original == remaining`) | 4.000 | 4.000 | 4.000 | `false` | `FINANCIAL_CAP_REACHED` (1ª vez) |
| **Pós-limite (zerar multa)** | 10.000 | 0 | 0 | `true` | — (já emitido) |

Corte parcial vs. zerar: o corte parcial aplica-se **apenas na infração que cruza a linha** — o tenant fatura exatamente até o teto contratual (`accrued_cents == cap`, nunca ultrapassa nem desperdiça headroom). Todas as infrações subsequentes do mês têm multa zerada, mas o registro forense integral (com `original_fine_cents` preservado) continua entrando no ledger — o CFO enxerga o passivo evitado.

Acúmulo: `UPDATE ... SET accrued_cents = accrued_cents + v_applied` (só quando `v_applied > 0`).

### 2.3.1 Bucket mensal: clamp anti clock-spoof (Zero-Trust, INV-18)

`occurred_at_utc` é fornecido pelo caller e **não tem bound no ledger** para tipos penais — um relógio de sensor corrompido (o exato threat model do §0) espalharia a tempestade por meses fabricados, cada um com headroom cheio. Defesa: **clampar apenas a chave do bucket, nunca o fato forense**:

```text
v_bucket_ts := LEAST(GREATEST(NEW.occurred_at_utc,
                              now() - make_interval(secs => v_tolerance)),
                     now() + make_interval(secs => v_tolerance));
v_month := date_trunc('month', v_bucket_ts AT TIME ZONE 'UTC')::date;
```

`v_tolerance` reutiliza a coluna existente `organizations.clock_drift_tolerance_s` (CT10, `20260520180000`) — nenhuma tolerância nova inventada. O payload preserva o `occurred_at_utc` verdadeiro intacto; só a contabilidade do cap é ancorada no tempo do servidor. Eventos legítimos na virada de mês (drift ≤ tolerância) caem no bucket correto. Cenário pgTAP #17.

**Acoplamento consciente:** `clock_drift_tolerance_s` é primariamente um knob de drift GPS/device — um tenant que o alargar por razões legítimas de telemetria alarga TAMBÉM a janela de spoof do Guard. Aceito (Ponytail: sem coluna nova); suporte/UI de configuração de tenant DEVE estar ciente ao ajustar drift GPS de que mexe na rede de segurança financeira. Se um dia divergirem, aí sim coluna dedicada.

### 2.4 Reversão de disputa (crédito de headroom)

Semântica REAL dos terminais de disputa (verificada em `20260809000001`/`20260901000002`):

| Evento | Efeito na sanção | Crédito? |
| --- | --- | --- |
| `DISPUTE_ACCEPTED` | `status='rejected'` — multa ANULADA, nunca faturada | **SIM** — credita `applied` de volta |
| `DISPUTE_OVERTURNED` | `status='applied'` — multa MANTIDA, devida | **NÃO** — creditar reabriria overshoot de multa legítima |
| `DISPUTE_RETRACTED` | `status` volta a `'pending'` — sanção segue viva | **NÃO** — débito original permanece correto |
| `VERDICT_REFUSED` (rejeição admin sem disputa) | multa anulada em revisão | **Decisão aberta p/ implementação (recomendado: SIM)** — mesma lógica jurídica do `DISPUTE_ACCEPTED`; confirmar semântica do `reject_sanction` no código antes de incluir |

Racional do crédito: sem ele, uma tempestade de falsos positivos disputados com sucesso "roubaria" o cap das infrações reais do mês — o teto limita multas *devidas*, não *alegadas*.

Mecanismo (função SEPARADA, não a mesma do débito — timings e sinais opostos são mais auditáveis isolados):

- `credit_financial_guard()` — trigger **AFTER INSERT** no ledger, `WHEN type = 'DISPUTE_ACCEPTED'`.
- Lookup do `applied` original: linha de ledger da sanção via `sanction_review_queue.ledger_entry_id` → `payload -> 'verdict_evidence' ->> 'fine_cents'` (valor já pós-corte). **Lookup-miss = fail-fast (INV-10):** se a linha original não for encontrada, `RAISE ... USING ERRCODE = 'integrity_constraint_violation'` — nunca no-op silencioso (crédito legítimo perdido sem trilha). Cenário pgTAP #21.
- **Exactly-once auto-contido:** `INSERT INTO financial_guard_credits ... ON CONFLICT DO NOTHING` (§1.2.1); só credita se a linha foi inserida — imune a replay/duplicação e a afrouxamentos futuros da máquina de estados da fila.
- Crédito aplicado ao bucket do **mês da infração original** (mesmo clamp §2.3.1), sob a mesma ordem de lock `contracts → accrual`.
- Floor 0 no acumulador: se o decremento clampar em 0 (só possível com drift), registrar `FINANCIAL_GUARD_DRIFT` no `system_audit_log` — o clamp nunca engole sinal de reconciliação silenciosamente.
- `cap_reached_at_utc` **não** é limpo (fato histórico imutável); novo esgotamento do headroom creditado NÃO re-emite `FINANCIAL_CAP_REACHED` (idempotência por contrato-mês mantida; o audit log do crédito documenta a reabertura).

---

## 3. Trilha de Auditoria (Breach Notification)

### 3.1 Registro do momento exato do breach

Na transação que faz `accrued_cents` atingir `v_cap` pela primeira vez no mês (`cap_reached_at_utc IS NULL` → `SET cap_reached_at_utc = now()` — idempotente por construção, sob o mesmo lock):

| Destino | Conteúdo |
| --- | --- |
| `system_audit_log` | `event_type='FINANCIAL_CAP_REACHED'`, `severity='critical'`, `actor_type='SYSTEM'`, `source='financial_guard'`, `reason` descritivo, `payload` = `{contract_id, month_utc, cap_cents, breaching_ledger_entry_id, original_fine_cents, applied_fine_cents}`. Sem conflito com `system_audit_log_governance_check` (whitelist de reason-obrigatório não inclui esses tipos — verificado `20260427010004`) |
| `sla_audit_ledger_v2` | Linha companheira `type='FINANCIAL_CAP_REACHED'` (mesmo org/contract), payload espelho. Sem recursão: tipo fora do set penal do `WHEN` do trigger |

Mudança de constraint: adicionar `FINANCIAL_CAP_REACHED` (e `FINANCIAL_CAP_WARNING`, §3.3) ao CHECK do ledger via swap versionado `chk_ledger_type_v7 NOT VALID → VALIDATE → DROP antigo → RENAME` de volta ao nome canônico `chk_ledger_type` (v6 é o vigente, `20260818000005`; testes commitados asserem o nome canônico).

### 3.2 Gancho webhook (documentado, NÃO implementado agora)

A linha companheira no ledger torna a notificação externa trivial no futuro: adicionar `'FINANCIAL_CAP_REACHED'` ao IF-list de `enqueue_resolution_events()` (`20260907000001`) → fan-out automático para `webhook_delivery_logs` (ERP) + `carrier_notification_outbox` (Resend), com drain/retry/DLQ já existentes. Zero infraestrutura nova de entrega.

### 3.3 Early-warning (soft threshold)

Ao cruzar 80% do cap (`accrued >= (cap * 80 + 50) / 100` — aritmética inteira): evento `FINANCIAL_CAP_WARNING` (`severity='warning'`) em `system_audit_log` + ledger, idempotente via `warned_at_utc`. Dá ao tenant janela de reação (investigar sensor) antes do corte duro.

---

## 4. Cobertura de Testes (pgTAP + Integração Dart)

Arquivos 1:1 por migration (`supabase/tests/{ts}_test.sql` + `forensic_records/plans/{ts}_test_plan.md` — consolidação não satisfaz o scanner). Cenários obrigatórios:

| # | Cenário | Assert central |
| --- | --- | --- |
| 1 | Cap `NULL` | Passthrough: payload **intocado** (sem chaves do guard), acumulador sem linha |
| 2 | Abaixo do cap (2 inserts) | `accrued_cents` = soma exata; `verdict_evidence.fine_cents == original_fine_cents`; `cap_truncated=false` |
| 3 | **Cruzamento parcial** | `verdict_evidence.fine_cents = remaining` (caminho ANINHADO — fixture de teste DEVE usar a shape real do payload), `cap_truncated=true`, `accrued_cents == cap` EXATO, `cap_reached_at_utc` setado, 1 linha `FINANCIAL_CAP_REACHED` no audit log E no ledger |
| 4 | **Pós-limite** | `fine_cents = 0`, `cap_truncated=true`, evento NÃO duplicado (count == 1) |
| 5 | Borda exata (`fine == remaining`) | `cap_truncated=false` porém `cap_reached_at_utc` setado + evento emitido |
| 6 | Virada de mês UTC | Insert com `occurred_at_utc` no mês seguinte (dentro da tolerância) → nova linha de acumulador, headroom cheio |
| 7 | INV-22 isolamento | (a) Tenant B com JWT próprio: acumulador de A invisível (0 rows); (b) INSERT com `organization_id` divergente do claim → `insufficient_privilege` ANTES de qualquer lock; (c) tempestades de A e B nunca serializam no lock uma da outra. Claim via `app_metadata->>'org_id'` |
| 8 | Tipo penal sem `contract_id` | `throws_matching` erro tipado (errcode real, anti-oracle: assert do errcode/domínio, nunca `isNot(PostgrestException)`) |
| 9 | Imutabilidade das projeções | UPDATE/DELETE direto em acumulador/credits como `authenticated` → bloqueado (RLS sem policy de escrita) |
| 10 | Grants | `table_privs_are` para `authenticated`/`anon`/`service_role` nas 2 tabelas novas (INV-DATA-API-GRANT) |
| 11 | Crédito de reversão | `DISPUTE_ACCEPTED` → `accrued_cents` decrementado pelo `applied` original; `cap_reached_at_utc` preservado; `DISPUTE_OVERTURNED` e `DISPUTE_RETRACTED` NÃO creditam |
| 12 | Warning 80% | 1 evento `FINANCIAL_CAP_WARNING`, idempotente |
| 13 | Regressão de tipos antigos | CHECK v7 aceita TODOS os valores pré-existentes (widening carrega tudo — 23514 em rows antigas se omitir) |
| 14 | Snapshot de cap mid-month | Amendment do cap no meio do mês → `cap_cents_snapshot` preservado; comportamento prospectivo documentado |
| 15 | **Anti-forgery de payload** | INSERT cliente com `original_fine_cents`/`cap_truncated`/`cap_remaining_before_cents`/`cap_check_deferred` pré-populados com valores de atacante → trigger sobrescreve TODAS incondicionalmente, byte-exato ao truncamento computado |
| 16 | Propagação nas 4 partições | Inserts com orgs que hasheiam p/ `p0..p3` → guard dispara em todas |
| 17 | **Clock-spoof do bucket** | Tempestade com `occurred_at_utc` fabricado (futuro/passado distante) → TODOS os eventos caem no bucket do mês corrente (clamp CT10); payload preserva timestamp original |
| 18 | Degradação por lock_timeout | Lock segurado artificialmente → insert passa sem truncar, `cap_check_deferred=true`; reconciliação corrige acumulador |
| 19 | Ordem de triggers | Assert em `pg_trigger`: `enforce_tenant_envelope_ledger` dispara antes de `trg_financial_guard` |
| 20 | Exactly-once do crédito | Ciclo re-disputa/re-aceite no mesmo `ledger_entry_id` (se máquina de estados permitir) → crédito aplicado exatamente 1× (`financial_guard_credits` PK) |
| 21 | Lookup-miss do crédito | `DISPUTE_ACCEPTED` sem linha de sanção original localizável → `integrity_constraint_violation` (fail-fast, INV-10), nunca no-op silencioso |

**Concorrência paralela real (fora do pgTAP):** `dblink` self-connect é BLOQUEADO no Supabase local (postgres não é superuser) — paralelismo verdadeiro exige teste de integração Dart: 2+ `SupabaseClient` + `Future.wait` disparando N inserts simultâneos que cruzam o cap (harness já provado em `resolve_dispute`/`dual_control_confirm`). Assert: `SUM(fine_cents aplicados) == cap` exato, **zero overshoot**, N linhas forenses no ledger. Load-test adicional: tempestade concorrente num único contrato validando o caminho de lock_timeout sem exaustão de pool. pgTAP cobre a variante serial (duas transações sequenciais na mesma sessão).

---

## 5. Tier-1 Enterprise — pontos adicionais (Palantir-grade)

| Tema | Design |
| --- | --- |
| **Reconciliação forense (drift detection + true-up)** | Job periódico (pg_cron ou RPC service_role): `accrued_cents` vs `SUM((payload->'verdict_evidence'->>'fine_cents')::bigint)` do ledger por contrato-mês, + varredura de linhas `cap_check_deferred=true` para true-up do caminho de degradação (§2.2). Divergência → `system_audit_log` `severity='critical'` `FINANCIAL_GUARD_DRIFT`. O acumulador é projeção; o ledger é verdade — self-check garante que o circuit breaker nunca minta silenciosamente |
| **Semântica de amendment mid-month** | Prospectiva sempre: cap novo vale para o headroom restante (`remaining = GREATEST(new_cap - accrued, 0)`), nunca recalcula multas já aplicadas (INV-3). `cap_cents_snapshot` documenta o cap de abertura do mês. Redução abaixo do já-acumulado → `remaining = 0` imediato, sem clawback |
| **Bootstrap / go-live backfill** | Migration inicializa o acumulador do mês corrente com `SUM` das penalidades já existentes no ledger — sem isso o cap "esquece" multas pré-guard e concede headroom fantasma |
| **Replay determinístico (INV-15)** | O resultado do truncamento depende da ordem de chegada — `cap_remaining_before_cents` sela essa ordem no payload imutável de cada evento. Replay lê o selo, não re-executa a corrida |
| **Kill-switch granular** | `monthly_penalty_cap_cents = NULL` desliga por contrato (rollout gradual por tenant, rollback instantâneo por UPDATE de 1 coluna — nenhuma flag global, nenhum deploy) |
| **Observabilidade** | Breach/warning já caem em `system_audit_log` (fonte para PostHog/Sentry via pipeline existente). Read-model futuro p/ CFO: "% do cap consumido" por contrato (SELECT direto no acumulador, RLS-scoped) — UI fora deste escopo |
| **Degradação graciosa sob tempestade** | Serialização por contrato com teto de espera (`lock_timeout`): fila curta = rate-limit natural; fila patológica = deferred + true-up, sem perda de evento e sem exaustão do pool (INV-16) |
| **Risco residual documentado (aceito nesta fase)** | O INSERT no ledger NÃO é RPC-gated: `GRANT INSERT ... TO authenticated` (`20260527164000:62`) + RLS `WITH CHECK` só de org — qualquer usuário autenticado do tenant pode forjar `verdict_evidence.fine_cents` do próprio tenant (nunca cross-tenant). O Guard limita o dano ao teto mensal (mitigação parcial). Hardening futuro: rotear escrita de sanções por RPC SECURITY DEFINER com claim de engine/service, alinhando ao padrão RPC-gated do resto do codebase |
| **Anti-oracle (INV-26)** | Qualquer RPC futuro de leitura do acumulador: 404 para not-found E wrong-org, indistinguíveis |
| **Zero-downtime total** | 100% DDL aditivo: colunas novas NULL, tabelas novas, triggers novos, CHECK via NOT VALID→VALIDATE. Nenhum ALTER bloqueante, nenhum backfill síncrono em tabela quente |
| **Fairness de disputa** | Crédito de reversão (§2.4) impede que falsos positivos disputados consumam o cap de infrações legítimas — o teto limita multas *devidas*, não *alegadas* |
| **Limites de escopo (Ponytail)** | Fora: cap por evento individual (o `financial_ceiling_cents` + engine Dart já cobrem), cap progressivo/time-scaled (roadmap Phase 10.9 — Progressive Penalty Engine), moeda múltipla, timezone de billing por contrato (mês UTC por decreto INV-6; knob futuro se contrato exigir) |

---

## 6. Sequenciamento de implementação (referência futura, fora deste escopo)

1. Migration A: colunas de cap (`contracts` + `contract_financial_amendments`) + RPC amend estendido + pgTAP.
2. Migration B: tabelas `contract_penalty_monthly_accrual` (+ COMMENT de lock order) e `financial_guard_credits` + RLS + grants + pgTAP.
3. Migration C: `chk_ledger_type_v7` (novos tipos) + `enforce_financial_guard()` (débito, BEFORE) + clamp CT10 + backfill bootstrap + pgTAP (cenários 1–10, 12–19).
4. Migration D: `credit_financial_guard()` (crédito, AFTER, função separada) + pgTAP (cenários 11, 20, 21). **PRÉ-CONDIÇÃO DURA (gate de merge):** a decisão `VERDICT_REFUSED` credita ou não (§2.4) DEVE estar resolvida — via leitura do `reject_sanction` real + sign-off QA/Security — antes desta migration existir. Sem resolução, Migration D não entra.
5. Migration E: RPC de reconciliação/true-up (`reconcile_financial_guard`, service_role) — varre `cap_check_deferred=true` + drift acumulador vs ledger; **DEVE adquirir a MESMA ordem de lock `contracts (FOR UPDATE) → accrual`** antes de mutar `accrued_cents` (nunca corre contra insert vivo do mesmo contrato) + agendamento pg_cron + pgTAP. O caminho de degradação (§2.2) só está completo com esta migration entregue no MESMO pacote — sem ela, linhas deferred nunca são corrigidas.
6. Teste de integração Dart de concorrência paralela + load-test do lock_timeout.
7. (Futuro, roadmap) IF-list webhook + UI CFO + hardening RPC-gated do ledger.

Cada migration com test plan 1:1, `supabase db reset` antes de `make test-db`, types regenerados (`sync_db_types.sh` manual em feature branch).

---

## 7. Council Sign-off

| Persona | v1 | v2 |
| --- | --- | --- |
| Architect | NO-GO (2 BLOCKER, 1 MAJOR, 3 MINOR) | **GO-WITH-CHANGES** — blockers/major verificados como remediados contra o código-fonte; 2 MINOR restantes (reconciliação sem step próprio; acoplamento do knob CT10) — ambos incorporados nesta mesma revisão (§6 passo 5; §2.3.1 nota de acoplamento) |
| QA/Security | NO-GO (2 BLOCKER, 4 MAJOR, 4 MINOR) | **GO-WITH-CHANGES** — todos os B/M verificados como remediados; 2 MINOR restantes (gate duro p/ decisão `VERDICT_REFUSED`; lookup-miss do crédito fail-fast) — ambos incorporados nesta mesma revisão (§6 passo 4; §2.4 + cenário #21) |

Nenhum achado pendente. Documento apto a servir de base para o pacote de implementação (migrations A–E, §6).

## 8. Council Remediation Notes (v1 → v2)

| Achado (persona, severidade) | Remediação em v2 |
| --- | --- |
| QA B1 BLOCKER: caminho JSON errado (`payload->>'fine_cents'` não existe) | §0.1/§1.3/§2.1: caminho aninhado `verdict_evidence.fine_cents` como fonte e destino (`jsonb_set` aninhado); chaves de auditoria top-level; leitores verificados |
| Arch #1 BLOCKER: bucket mensal confiava em `occurred_at_utc` spoofável | §2.3.1: clamp do bucket com `organizations.clock_drift_tolerance_s` (CT10); fato forense preservado; cenário #17 |
| Arch #2 BLOCKER: crédito em `DISPUTE_OVERTURNED` estava semanticamente invertido | §2.4: tabela de semântica real; crédito só em `DISPUTE_ACCEPTED`; `VERDICT_REFUSED` como decisão aberta |
| QA B2 BLOCKER: cenário de forgery ausente | Cenário #15 (sobrescrita incondicional) + nota de fixture com shape real (anti LAZY-TEST-BYPASS) |
| Arch #3 MAJOR: `FOR UPDATE` sem teto = exaustão de pool | §2.2: `SET LOCAL lock_timeout` + caminho deferred + true-up na reconciliação; cenário #18 + load-test |
| QA M1 MAJOR: sem re-validação de claim JWT no trigger | §2.1 passo 1: claim check primeiro, `insufficient_privilege`; cenário #7b |
| QA M2 MAJOR: ledger INSERT não RPC-gated (forgery intra-tenant) | §5: risco residual documentado + hardening futuro |
| QA M3 MAJOR: idempotência do crédito dependia de subsistema alheio | §1.2.1: `financial_guard_credits` PK + ON CONFLICT DO NOTHING; cenário #20 |
| QA M4 MAJOR: ordem de triggers por acidente alfabético | §2.1: pgTAP assert de `pg_trigger` (cenário #19) + convenção documentada |
| Arch #4 MINOR: função única p/ débito+crédito | §2.4: funções separadas (BEFORE débito / AFTER crédito) |
| Arch #5 MINOR: precedente vestigial citado | §1.2: precedente trocado p/ `sanction_review_queue.status` |
| Arch #6 MINOR: lock order só em prosa | §1.2: `COMMENT ON TABLE` obrigatório na migration |
| QA m1 MINOR: `NO_SHOW_PENALTY` não é tipo vivo | §0.1: documentado; mantido no WHEN por defesa futura |
| QA m2/m3/m4 MINOR: gaps de cobertura | Cenários #16, #7b/c, #20 |
