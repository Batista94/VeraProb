# Forensic Test Plan — Migration `20260515000001_fix_raw_telemetry_immutability`

> **Classificação:** Engineering Study / Forensic Audit
> **Emitido por:** QA/Security Council Persona
> **Data de emissão:** 2026-05-15
> **Migração alvo:** `supabase/migrations/20260515000001_fix_raw_telemetry_immutability.sql`
> **Tabela afetada:** `public.raw_telemetry_payloads`
> **Mudança estrutural:** Substituição de RULE `DO INSTEAD NOTHING` por TRIGGER GUC-aware via `prevent_immutable_update()`. Adição de RPC `test_tamper_raw_telemetry_payload` (SECURITY DEFINER, `service_role` only).
> **Invariantes cobertos:** INV-3 (Ledger Append-Only), INV-9 (SHA-256 Seal), INV-DB (Zero-Downtime Pattern)

---

## Contexto da Investigação

As RULE `raw_telemetry_payloads_no_update` e `raw_telemetry_payloads_no_delete` eram incompatíveis com o comportamento do PostgREST, que injeta automaticamente `RETURNING *` em todas as mutações. Regras `DO INSTEAD NOTHING` retornam `feature_not_supported (0A000)` nesse contexto, causando crash HTTP 500 em vez do esperado HTTP 409.

Esta migração substitui as RULE por triggers GUC-aware (`trg_raw_telemetry_no_update` e `trg_raw_telemetry_no_delete`) usando a função `prevent_immutable_update()` já existente (definida em `20260423180000_forensic_test_hardening.sql`). A garantia de append-only (INV-3) é preservada; o mecanismo de enforcement migra da camada de rule para a camada de trigger.

Adicionalmente, a RPC `test_tamper_raw_telemetry_payload` é introduzida para permitir que testes de red-team (fase 2 do `hmac_tampering_detection_test.dart`) simulem um DBA malicioso modificando `raw_payload` sem atualizar `payload_hash`, provando que a camada de verificação de hash da aplicação (INV-9 / INV-31) detecta o tamper e lança `IntegrityException`. O bypass é TX-scoped via `SET LOCAL` — sem risco de vazamento de GUC entre conexões.

---

## Pré-condições de Ambiente

| Item | Valor esperado |
|---|---|
| PostgreSQL | ≥ 14 |
| Função `prevent_immutable_update()` | Presente no schema `public` (migração `20260423180000`) |
| Migração aplicada | Triggers `trg_raw_telemetry_no_update` e `trg_raw_telemetry_no_delete` visíveis em `pg_trigger` |
| Ambiente de teste | Supabase local (`supabase start`) ou staging isolado |
| Role `service_role` | Disponível para execução da RPC de red-team |

---

## Grupo 1 — Imutabilidade via Trigger (INV-3)

### Objetivo

Confirmar que os novos triggers bloqueiam `UPDATE` e `DELETE` em `raw_telemetry_payloads` para qualquer role não autorizado, substituindo com garantia equivalente ou superior as RULE removidas.

---

### CT-IM-01: UPDATE Bloqueado pelo Trigger

**Hipótese forense:** O trigger `trg_raw_telemetry_no_update` dispara `BEFORE UPDATE` e chama `prevent_immutable_update()`, que verifica o GUC `vera.authorized_test_cleanup`. Com GUC ausente (valor padrão), a função levanta `restrict_violation`.

**Script de verificação (executar no console Supabase ou `psql`):**

```sql
-- DEVE FALHAR com: restrict_violation (ERRCODE 23001)
-- Mensagem esperada: "raw_telemetry_payloads is immutable (INV-3). Operation: UPDATE"
UPDATE public.raw_telemetry_payloads
SET raw_payload = '{"tampered": true}'::JSONB
WHERE id = (SELECT id FROM public.raw_telemetry_payloads LIMIT 1);
```

**Critério de aceitação:** PostgreSQL retorna `ERROR 23001: restrict_violation`. Nenhuma linha alterada. O PostgREST retorna HTTP 409 ao chamador (não 500 como ocorria com as RULE).

**Critério de falha:** Operação sucede silenciosamente (indica que o trigger não foi instalado) ou retorna `0A000 feature_not_supported` (indica regressão para o comportamento de RULE).

---

### CT-IM-02: DELETE Bloqueado pelo Trigger

**Hipótese forense:** O trigger `trg_raw_telemetry_no_delete` dispara `BEFORE DELETE` com a mesma função, garantindo que registros de telemetria não possam ser apagados por nenhum role não autorizado (INV-3 append-only).

```sql
-- DEVE FALHAR com: restrict_violation (ERRCODE 23001)
DELETE FROM public.raw_telemetry_payloads
WHERE id = (SELECT id FROM public.raw_telemetry_payloads LIMIT 1);
```

**Critério de aceitação:** `ERROR 23001: restrict_violation`. Nenhuma linha removida. O ledger de telemetria permanece intacto.

**Critério de falha:** Linha deletada com sucesso — violação crítica de INV-3. Escalação imediata para Architect + QA/Sec persona.

---

### CT-IM-03: Verificação dos Triggers no Catálogo

**Hipótese forense:** Os dois triggers devem estar instalados e habilitados (`tgenabled = 'O'`) na tabela.

```sql
-- RESULTADO ESPERADO: duas linhas com tgenabled = 'O'
SELECT tgname, tgenabled, tgtype
FROM pg_trigger
WHERE tgrelid = 'public.raw_telemetry_payloads'::regclass
  AND tgname IN ('trg_raw_telemetry_no_update', 'trg_raw_telemetry_no_delete')
ORDER BY tgname;
```

**Critério de aceitação:** Duas linhas retornadas, ambas com `tgenabled = 'O'` (enabled). As RULE antigas (`raw_telemetry_payloads_no_update`, `raw_telemetry_payloads_no_delete`) devem estar ausentes:

```sql
-- RESULTADO ESPERADO: 0 linhas (RULE removidas)
SELECT rulename
FROM pg_rules
WHERE tablename = 'raw_telemetry_payloads'
  AND rulename IN ('raw_telemetry_payloads_no_update', 'raw_telemetry_payloads_no_delete');
```

**Critério de aceitação:** `0 linhas` — confirma que a substituição RULE → TRIGGER foi executada sem resíduos.

---

## Grupo 2 — Red Team: RPC de Tamper Autorizado (INV-9 / INV-31)

### Objetivo

Validar que a RPC `test_tamper_raw_telemetry_payload` funciona corretamente para o role `service_role` (bypass GUC TX-scoped) e que está corretamente vedada para roles não-autorizados. A RPC é usada por `hmac_tampering_detection_test.dart` para provar que a camada de verificação de hash da aplicação detecta adulterações de payload (INV-9).

---

### CT-RT-01: RPC Bypass GUC Funciona com `service_role`

**Hipótese forense:** A RPC executa `SET LOCAL vera.authorized_test_cleanup = 'on'` dentro da transação, permitindo que `prevent_immutable_update()` deixe a operação passar. O `raw_payload` deve ser modificado sem erros. O `payload_hash` permanece o valor original — criando deliberadamente uma inconsistência detectável pela verificação HMAC da aplicação (INV-9).

**Procedimento (executar como `service_role`):**

```sql
-- Passo 1: Inserir registro de referência para o teste
INSERT INTO public.raw_telemetry_payloads (
  id,
  organization_id,
  raw_payload,
  payload_hash,
  received_at
) VALUES (
  '00000000-0000-0000-0000-000000000099'::UUID,
  'org-redteam-test',
  '{"speed_kmh": 80, "lat": -23.5}'::JSONB,
  'sha256_original_hash_placeholder',
  NOW()
);

-- Passo 2: Capturar payload original
SELECT id, raw_payload, payload_hash
FROM public.raw_telemetry_payloads
WHERE id = '00000000-0000-0000-0000-000000000099'::UUID;

-- Passo 3: Executar tamper via RPC (simula DBA malicioso)
SELECT public.test_tamper_raw_telemetry_payload(
  '00000000-0000-0000-0000-000000000099'::UUID,
  '{"speed_kmh": 200, "lat": -23.5, "tampered": true}'::JSONB
);

-- Passo 4: Confirmar que raw_payload foi alterado mas payload_hash permanece original
SELECT
  id,
  raw_payload ->> 'speed_kmh' AS speed_after_tamper,
  payload_hash AS hash_unchanged
FROM public.raw_telemetry_payloads
WHERE id = '00000000-0000-0000-0000-000000000099'::UUID;
```

**Critério de aceitação:**
- Passo 3 executa sem erro (RPC retorna `VOID`).
- Passo 4: `speed_after_tamper = '200'` e `hash_unchanged = 'sha256_original_hash_placeholder'` (hash não atualizado — inconsistência intencional para detecção pelo HMAC da app).
- A aplicação Dart, ao ler este registro, deve lançar `IntegrityException` ao verificar INV-9.

**Cleanup obrigatório após o teste:**

```sql
-- Bypass necessário para cleanup do registro de teste
SELECT public.test_tamper_raw_telemetry_payload(
  '00000000-0000-0000-0000-000000000099'::UUID,
  '{}'::JSONB
);
-- Ou via supabase db reset em ambiente local
```

---

### CT-RT-02: RPC Vedada para Roles Não-Autorizados

**Hipótese forense:** O `REVOKE ALL FROM PUBLIC` garante que roles como `anon` e `authenticated` não conseguem executar a RPC. Apenas `service_role` tem `GRANT EXECUTE`.

```sql
-- Executar como role 'authenticated' ou 'anon'
-- DEVE FALHAR com: permission denied for function test_tamper_raw_telemetry_payload
SET ROLE authenticated;
SELECT public.test_tamper_raw_telemetry_payload(
  gen_random_uuid(),
  '{}'::JSONB
);
RESET ROLE;
```

**Critério de aceitação:** `ERROR 42501: permission denied for function test_tamper_raw_telemetry_payload`. Nenhum bypass possível sem `service_role`.

---

### CT-RT-03: Verificação de Permissões da RPC no Catálogo

```sql
-- RESULTADO ESPERADO: apenas service_role com EXECUTE
SELECT
  grantee,
  routine_name,
  privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name = 'test_tamper_raw_telemetry_payload';
```

**Critério de aceitação:** Apenas `service_role` aparece com `privilege_type = 'EXECUTE'`. `PUBLIC`, `anon`, `authenticated` ausentes.

---

## Grupo 3 — Validação de Zero-Downtime (INV-DB)

### Objetivo

Justificar e confirmar que a migração não adquiriu `AccessExclusiveLock` de longa duração em `raw_telemetry_payloads` durante sua execução. Operações de leitura concorrentes (ingestão de telemetria) não devem ser bloqueadas.

---

### CT-ZD-01: Justificativa Forense de Zero-Downtime

**Hipótese forense:** `CREATE TRIGGER` e `CREATE OR REPLACE FUNCTION` no PostgreSQL adquirem `AccessExclusiveLock` apenas brevemente no catálogo (pg_proc, pg_trigger), não na tabela de dados. O `DROP RULE` também é uma operação de catálogo. A janela de lock é sub-milissegundo em produção — sem impacto em INSERTs concorrentes de telemetria.

**Mapeamento de locks por operação:**

| Operação | Lock Adquirido | Escopo | Bloqueia INSERTs? |
|---|---|---|---|
| `DROP RULE IF EXISTS` | `AccessExclusiveLock` em catálogo | `pg_rewrite` (~ms) | Não |
| `DROP TRIGGER IF EXISTS` | `ShareRowExclusiveLock` em tabela | Breve (~ms) | Não (compartilhado) |
| `CREATE TRIGGER` | `ShareRowExclusiveLock` em tabela | Breve (~ms) | Não (compartilhado) |
| `CREATE OR REPLACE FUNCTION` | `AccessExclusiveLock` em `pg_proc` | Catálogo (~ms) | Não |
| `REVOKE / GRANT` | `AccessShareLock` em pg_proc | Catálogo (~ms) | Não |

**Script de monitoramento (executar em Sessão A antes da migração):**

```sql
-- Monitorar locks enquanto Sessão B aplica a migração
SELECT
  pid,
  query_start,
  state,
  wait_event_type,
  wait_event,
  left(query, 80) AS query_snippet
FROM pg_stat_activity
WHERE state <> 'idle'
  AND query NOT ILIKE '%pg_stat_activity%'
ORDER BY query_start;
```

**Sessão B — Simular workload de INSERT durante migração:**

```sql
-- Rodar em loop concorrente enquanto a migração é aplicada
DO $$
DECLARE i INT := 0;
BEGIN
  WHILE i < 500 LOOP
    INSERT INTO public.raw_telemetry_payloads (
      organization_id, raw_payload, payload_hash, received_at
    ) VALUES (
      'org-load-test',
      ('{"seq": ' || i || '}')::JSONB,
      'hash_' || i,
      NOW()
    );
    i := i + 1;
  END LOOP;
END $$;
```

**Critério de aceitação:** O loop da Sessão B completa sem deadlock ou timeout. `pg_stat_activity` na Sessão A não exibe `wait_event = 'relation'` com `wait_event_type = 'Lock'` para a tabela `raw_telemetry_payloads` durante os `CREATE TRIGGER`. Tempo total do loop não deve exceder 2x o tempo basal.

---

### CT-ZD-02: Idempotência da Migração

**Hipótese forense:** Todos os DDL usam `IF EXISTS` / `IF NOT EXISTS` / `CREATE OR REPLACE`, tornando a migração re-executável sem erro.

**Procedimento:** Re-executar o arquivo de migração manualmente após a aplicação inicial.

```sql
-- Re-executar o conteúdo da migração (sem o SET client_min_messages)
DROP RULE IF EXISTS raw_telemetry_payloads_no_update ON public.raw_telemetry_payloads;
DROP RULE IF EXISTS raw_telemetry_payloads_no_delete ON public.raw_telemetry_payloads;
DROP TRIGGER IF EXISTS trg_raw_telemetry_no_update ON public.raw_telemetry_payloads;
CREATE TRIGGER trg_raw_telemetry_no_update
  BEFORE UPDATE ON public.raw_telemetry_payloads
  FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_update();
DROP TRIGGER IF EXISTS trg_raw_telemetry_no_delete ON public.raw_telemetry_payloads;
CREATE TRIGGER trg_raw_telemetry_no_delete
  BEFORE DELETE ON public.raw_telemetry_payloads
  FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_update();
```

**Critério de aceitação:** Nenhum erro na segunda execução. CT-IM-03 passa identicamente após re-execução.

---

## Matriz de Rastreabilidade

| Caso de Teste | Invariante | Tipo | Automatable? | Prioridade |
|---|---|---|---|---|
| CT-IM-01 | INV-3 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-IM-02 | INV-3 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-IM-03 | INV-3, INV-DB | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-RT-01 | INV-9, INV-31 | Red Team / Integration | Sim (CI/Dart) | P0 - Bloqueante |
| CT-RT-02 | INV-9 | Sec Test | Sim (CI) | P0 - Bloqueante |
| CT-RT-03 | INV-9 | Schema Check | Sim (CI) | P1 |
| CT-ZD-01 | INV-DB | Observabilidade | Manual (Prod-sim) | P0 - Bloqueante |
| CT-ZD-02 | INV-DB | Idempotency | Manual | P1 |

---

## Critério de Go/No-Go para Merge em Main

> Todos os casos **P0 - Bloqueante** devem passar antes do merge. Falha em qualquer P0 é **VETO automático** pelo Reviewer Persona.

| Gate | Condição |
|---|---|
| **PASS** | CT-IM-01: UPDATE retorna `restrict_violation`; CT-IM-02: DELETE retorna `restrict_violation`; CT-IM-03: triggers presentes e habilitados, RULE ausentes; CT-RT-01: RPC modifica `raw_payload` via GUC bypass; CT-RT-02: `authenticated` bloqueado com `permission denied`; CT-ZD-01: INSERTs concorrentes completam sem bloqueio |
| **VETO** | Qualquer P0 com resultado diferente do esperado |
| **WARN** | CT-RT-01 cleanup falha — acionar `supabase db reset` em ambiente local |

---

## Artefatos de Evidência (Forensic Chain of Custody)

Ao concluir a execução, armazenar os seguintes artefatos no storage forense do ambiente:

1. **Output** de CT-IM-03: resultado de `pg_trigger` (triggers habilitados) e `pg_rules` (RULE ausentes)
2. **Screenshot** do erro `restrict_violation` nos casos CT-IM-01 e CT-IM-02
3. **Output** de CT-RT-01: `raw_payload` adulterado + `payload_hash` inalterado (evidência de inconsistência intencional)
4. **Log** de `pg_stat_activity` durante CT-ZD-01 (ausência de lock bloqueante em `raw_telemetry_payloads`)

Estes artefatos constituem a **prova documental** de que a migração foi validada segundo os padrões de governança VeraProb e podem ser referenciados em auditorias contratuais futuras.
