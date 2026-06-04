# Plano de Testes E2E/UAT — Tribunal de Auditoria (AuditorQueueScreen)

**Tela:** `lib/features/admin/presentation/screens/auditor_queue_screen.dart`
**Card de Veredito:** `lib/features/admin/presentation/widgets/sanction_verdict_card.dart`
**Invariantes:** INV-1 (org_id Fail-Fast), INV-2/INV-3 (ledger append-only), INV-6 (UTC), INV-22 (isolamento de tenant), INV-23 (provenance/explainability do veredito), INV-24 (idempotência).
**Risco:** Alto — selamento de veredito gera entrada **imutável** no ledger (`VERDICT_SEALED`). Ações irreversíveis.

> [!NOTE]
> Plano cobre o ciclo **completo** desde o login: simular sanção → revisar provenance → SELAR / RECUSAR / SOLICITAR PROVA → conferir filtros (Pendentes / Aguardando Evidência / Selados) → dossiê → mapa forense. Cada passo de UI tem uma **verificação de banco** correspondente para confirmar persistência correta.

---

## 🛠️ Pré-requisitos & Ambiente

| Item | Comando / Ação | Estado Esperado |
|------|----------------|-----------------|
| Supabase local | `make setup` / `supabase start` | Containers ativos, migrações aplicadas |
| Massa base | `supabase db reset` | Seeds aplicados (`supabase/seed.sql`), contratos ativos |
| App Flutter | `make run` | Frontend no navegador |
| Cliente SQL | Supabase Studio `http://localhost:54323` ou `psql` | Para verificações de banco |

### 🔐 Credenciais (Inquilinos Isolados)

* **Inquilino A (Org Alpha):** `admin-a@veraprob.dev` / `veraprob123!` — Org ID `00000000-0000-0000-0000-000000000001`
* **Inquilino B (Org Beta):** `admin-b@veraprob.dev` / `veraprob123!` — Org ID `00000000-0000-0000-0000-000000000002`

### 📌 Pré-condição obrigatória

A tela depende de **contratos ativos** para o botão **Gerar Sanção de Teste** funcionar (`runSanctionSimulation`). Confirme antes:

```sql
SELECT id, organization_id, status
FROM public.contracts
WHERE organization_id = '00000000-0000-0000-0000-000000000001'
  AND status = 'active'
LIMIT 5;
-- Esperado: ≥ 1 linha. Se 0, rode `supabase db reset` para repor seeds.
```

---

## 🚀 Fluxo E2E Completo

### Passo 1 — Login (do zero)

1. Abra `http://localhost:<porta>`. Tela **Autenticação Corporativa** (`AdminLockScreen`).
2. Campo **"E-mail Corporativo"** → `admin-a@veraprob.dev`.
3. Campo **"Senha de Acesso"** → `veraprob123!`.
4. Clique no botão **"ACESSAR SISTEMA"**.
5. **Checkpoint:** redirecionamento ao painel da Org Alpha. Sem erro `Credenciais Incorretas`. Sem stack trace no console (Lesson #5).

**Verificação de banco — sessão e claim JWT:**

```sql
SELECT u.email,
       u.raw_app_meta_data ->> 'org_id'      AS org_claim,
       u.raw_app_meta_data ->> 'role'        AS role,
       u.raw_app_meta_data ->> 'super_admin' AS super_admin
FROM auth.users u
WHERE u.email = 'admin-a@veraprob.dev';
-- Esperado: org_claim = 00000000-0000-0000-0000-000000000001 (UUID, NÃO o nome).
--           role = TENANT_ADMIN. super_admin = NULL (admin de org, não superadmin).
```

> ⚠️ **Chave correta é `org_id`, não `organization_id`.** O metadado armazenado em
> `raw_app_meta_data` usa a chave `org_id` (ver `bootstrap_dev.mjs` / hook
> `custom_access_token_hook`). Consultar `->> 'organization_id'` retorna NULL — não é bug.
> O claim top-level `organization_id` só existe no **token** em runtime (injetado pelo hook
> `20260410000001`), não na coluna armazenada. E o valor é o **UUID** da org, nunca o nome.
>
> INV-1: a claim `org_id` precisa existir; sem ela todas as queries falham Fail-Fast.
> O lado Dart lê `app_metadata.org_id` via `currentOrganizationIdProvider`.

---

### Passo 2 — Navegar à Fila Auditora

1. No painel lateral, abra **"Fila Auditora"** → `AuditorQueueScreen`.
2. **Checkpoint:** cabeçalho **"Tribunal de Auditoria"** (ícone `gavel`). Filtro segmentado visível: **Pendentes (N)**, **Aguardando Evidência (N)**, **Selados**.
3. Se a fila estiver vazia: estado **"Nenhum veredito pendente"** com botão **Gerar Sanção de Teste**.

---

### Passo 3 — Gerar Sanção de Teste (semear o caso)

1. Clique em **"Gerar Sanção de Teste"** (header ou empty-state). Injeta uma sanção sintética **VEL-01** (placa `TST-0001`, operador `Motorista Teste`) via `SanctionSimulationService`.
2. **Checkpoint:** SnackBar *"Sanção VEL-01 injetada — aguarde até 5s para aparecer na fila."*
3. Aguarde até 5s (Supabase Realtime). Um **SanctionVerdictCard** aparece sob **Pendentes**, com borda esquerda **vermelha** (não selado) — **vermelha mesmo se o card estiver focado** (acento dirigido por status; foco indicado pelo tint + badge "NO MAPA").
4. **Checkpoint identidade (INV-14):** a faixa de identidade mostra `[VEL-01] · 🚚 TST-0001 · 👤 Motorista Teste`. A placa tem destaque igual à cláusula.
5. **Checkpoint VEL (Q5):** o card exibe os três rótulos obrigatórios: **VELOCIDADE REGISTRADA**, **LIMITE CONTRATUAL** e **EXCESSO** (com `88.5 km/h` / `80.0 km/h` / `+8.5 km/h`).

**Verificação de banco — sanção enfileirada (Org Alpha):**

```sql
SELECT id, organization_id, contract_id, set_id, status,
       verdict_evidence ->> 'clauseRef' AS clause,
       vehicle_plate, operator_name,
       created_at
FROM public.sanction_review_queue
WHERE organization_id = '00000000-0000-0000-0000-000000000001'
ORDER BY created_at DESC
LIMIT 1;
-- Esperado: 1 linha. status = 'pending'. clause começa com 'VEL'.
--           vehicle_plate = 'TST-0001'. operator_name = 'Motorista Teste'
--           (resolvidos via fallback Zero-Trust do payload — INV-18, pois a
--            sanção simulada não tem execution_state vinculado).
--           organization_id = ...001 (NUNCA ...002).
```

Anote o `id` retornado — referenciado como **`<QUEUE_ID>`** nos passos seguintes.

---

### Passo 4 — Provenance em 1 clique (INV-23)

Valida a regra "silenciar contestação em 10s": evidência rastreável em ≤1 clique.

1. No card, clique na faixa **"Cadeia de Custódia · Prova Forense"** (mostra `SHA-256: …`).
2. **Checkpoint:** abre o **InvestigationModal** com a cadeia de custódia (setId + contractId). Hash visível.
3. Feche o modal (X / barreira).

**Verificação de banco — hash de evidência selado no ingest (INV-9):**

```sql
SELECT id,
       verdict_evidence ->> 'evidenceHash'    AS evidence_hash,
       verdict_evidence ->> 'confidenceScore' AS confidence
FROM public.sanction_review_queue
WHERE id = '<QUEUE_ID>'
  AND organization_id = '00000000-0000-0000-0000-000000000001';
-- Esperado: evidence_hash com 64 chars hex (SHA-256). confidence numérico 0–100.
```

> O `SHA-256` exibido no card deve **bater** com `evidence_hash`. Divergência = violação de selo (INV-9).

---

### Passo 5 — SELAR VEREDITO (caminho crítico, append-only)

1. No card, clique em **"SELAR VEREDITO"** (botão verde, ícone `gavel`).
2. **Se** `confidenceScore` for baixo (`requiresDoubleConfirmation`): aparece diálogo **"⚠ Integridade Baixa"** → clique **"Confirmar Selamento"**. (Para testar este ramo, force um caso de baixa integridade; o VEL-01 padrão pode ter score alto e pular o diálogo.)
3. **Checkpoint:** o card sai da aba **Pendentes** (stream re-consultado). Em **Selados**, reaparece com badge **"SELADO"** (cadeado) e borda cinza, opacidade reduzida — imutável (INV-7).

**Verificação de banco — fila transicionou para `applied`:**

```sql
SELECT status, reviewed_at, reviewed_by
FROM public.sanction_review_queue
WHERE id = '<QUEUE_ID>'
  AND organization_id = '00000000-0000-0000-0000-000000000001';
-- Esperado: status = 'applied'. reviewed_at NOT NULL (UTC). reviewed_by = id do operador.
```

**Verificação de banco — entrada imutável no ledger (INV-3, Pillar C):**

```sql
SELECT type, organization_id, set_id, contract_id, occurred_at_utc
FROM public.sla_audit_ledger_v2
WHERE organization_id = '00000000-0000-0000-0000-000000000001'
  AND type = 'VERDICT_SEALED'
ORDER BY occurred_at_utc DESC
LIMIT 1;
-- Esperado: 1 linha type = 'VERDICT_SEALED', org = ...001, set_id/contract_id batem com o card.
```

**Verificação de imutabilidade (INV-3) — UPDATE/DELETE devem ser bloqueados:**

```sql
BEGIN;
UPDATE public.sla_audit_ledger_v2
SET type = 'TAMPERED'
WHERE organization_id = '00000000-0000-0000-0000-000000000001'
  AND type = 'VERDICT_SEALED';
ROLLBACK;
-- Esperado: ERROR (trigger/policy append-only bloqueia UPDATE no ledger).
```

> Idempotência (INV-24): clicar SELAR uma segunda vez no mesmo `<QUEUE_ID>` (se ainda visível) deve falhar com *"is already applied"* — nenhuma 2ª entrada `VERDICT_SEALED` é criada. Confirme contando: `SELECT count(*) FROM public.sla_audit_ledger_v2 WHERE set_id = '<SET_ID>' AND type='VERDICT_SEALED';` → deve ser **1**.

---

### Passo 6 — RECUSAR VEREDITO (rejeição com motivo)

Gere uma **nova** sanção (Passo 3) para este teste. Anote o novo `<QUEUE_ID>`.

1. No card, clique em **"RECUSAR VEREDITO"** (botão outline vermelho). Abre o campo **"Motivo da rejeição (mínimo 10 caracteres)"**.
2. Digite < 10 chars → botão **"CONFIRMAR RECUSA"** permanece **desabilitado** (guard de UI).
3. Digite ≥ 10 chars (ex.: `Telemetria inconsistente`) → **"CONFIRMAR RECUSA"** habilita. Clique.
4. **Checkpoint:** card sai de **Pendentes**.

**Verificação de banco — rejeição persistida:**

```sql
SELECT status, rejection_reason, reviewed_at, reviewed_by
FROM public.sanction_review_queue
WHERE id = '<QUEUE_ID>'
  AND organization_id = '00000000-0000-0000-0000-000000000001';
-- Esperado: status = 'rejected'. rejection_reason = texto digitado (≥10 chars). reviewed_at NOT NULL.
```

> Rejeição **não** gera `VERDICT_SEALED` no ledger. Confirme: nenhuma nova linha em `sla_audit_ledger_v2` com este `set_id` e `type='VERDICT_SEALED'`.

---

### Passo 7 — SOLICITAR PROVA FORENSE (disputa)

Gere uma **nova** sanção (Passo 3). Anote `<QUEUE_ID>`.

1. Clique em **"SOLICITAR PROVA FORENSE"** (botão âmbar).
2. **Checkpoint:** SnackBar *"Solicitação enviada. Motorista será notificado…"*. Card migra para a aba **"Aguardando Evidência"** com badge âmbar **"AGUARDANDO EVIDÊNCIA"** e borda âmbar.
3. **Checkpoint trava de UI (Q7 — obrigatório):** com o badge âmbar presente, os botões **SELAR VEREDITO** e **RECUSAR VEREDITO** **deixam de existir** na árvore daquele card (imposto por `if (!isLocked)` — `disputed` é `locked`). Garante que não há concorrência acidental contra falha humana. Asserção automatizada:
   ```dart
   expect(find.widgetWithText(FilledButton, 'SELAR VEREDITO'), findsNothing);
   expect(find.widgetWithText(OutlinedButton, 'RECUSAR VEREDITO'), findsNothing);
   expect(find.text('AGUARDANDO EVIDÊNCIA'), findsOneWidget);
   ```

**Verificação de banco — disputa registrada:**

```sql
SELECT status FROM public.sanction_review_queue
WHERE id = '<QUEUE_ID>' AND organization_id = '00000000-0000-0000-0000-000000000001';
-- Esperado: status = 'disputed'.

SELECT type, occurred_at_utc
FROM public.sla_audit_ledger_v2
WHERE organization_id = '00000000-0000-0000-0000-000000000001'
  AND type = 'SANCTION_DISPUTED'
ORDER BY occurred_at_utc DESC LIMIT 1;
-- Esperado: 1 linha type = 'SANCTION_DISPUTED'.
```

---

### Passo 8 — Filtro "Selados" + intervalo de datas

1. Clique no segmento **"Selados"**. Aparece a **barra de período** (`_DateFilterBar`) com "Período: dd/mm/aaaa até dd/mm/aaaa".
2. O veredito do Passo 5 deve constar na lista (badge SELADO).
3. Clique em **"ALTERAR"** → escolha um intervalo que **exclua** hoje → confirme.
4. **Checkpoint:** lista vazia → *"Nenhum veredito selado encontrado neste período."* Reverta o intervalo para incluir hoje → veredito reaparece.
5. Se houver > página: botão **"CARREGAR MAIS"** (paginação `fetchNextPage`).

**Verificação de banco — selados no período (UTC, INV-6):**

```sql
SELECT count(*)
FROM public.sla_audit_ledger_v2
WHERE organization_id = '00000000-0000-0000-0000-000000000001'
  AND type = 'VERDICT_SEALED'
  AND occurred_at_utc >= date_trunc('day', now() AT TIME ZONE 'UTC');
-- Esperado: contagem coerente com o que a UI lista para "hoje".
```

> Atenção ao fuso: a UI converte UTC→local para exibir (`toLocal()`); a query usa UTC. Confirme que um veredito perto da meia-noite local não "some" por erro de conversão.

---

### Passo 9 — BAIXAR DOSSIÊ (PDF forense)

1. Em qualquer card, clique em **"BAIXAR DOSSIÊ"**.
2. **Checkpoint:** spinner → SnackBar *"Dossiê forense baixado com sucesso."*. Arquivo `dossie_forense_<hash8>_<ts>.pdf` salvo. Em falha: *"Falha ao gerar o dossiê. Tente novamente."* (mensagem domínio-limpa, Lesson #5).
3. Abra o PDF: confere `formattedFine`, coordenadas, hash de evidência.

---

### Passo 10 — Visualizar Evidência Forense (veredito aplicado)

1. Na aba **Selados**, num card com status `applied`, clique em **"Visualizar Evidência Forense"**.
2. **Checkpoint (caminho feliz):** abre `ForensicEvidenceModal` carregado por `ledgerEntryId`. Mostra a regra congelada + selo **verde** "Cópia Autenticada" (hash recomputado bate). Feche o modal.

---

### Passo 10.1 — Adulteração de Snapshot (Anti-Fraude — INV-9, INV-21)

Auditoria crítica: o sistema precisa **provar** que reage a uma adulteração da regra congelada. A detecção já é nativa (`verify_forensic_evidence` recomputa o SHA-256 sobre o snapshot canônico a cada leitura).

1. **Pré:** use um veredito **selado** (Passo 5). Obtenha o `ledger_entry_id`:
   ```sql
   SELECT ledger_entry_id FROM public.sanction_review_queue
   WHERE id = '<QUEUE_ID>' AND organization_id = '00000000-0000-0000-0000-000000000001';
   ```
2. **Ação (via SQL):** altere **um único caractere** do JSON da regra congelada, **sem** tocar o `integrity_hash` (deixe-o obsoleto):
   ```sql
   UPDATE public.forensic_evidence_snapshots
   SET snapshot = jsonb_set(snapshot, '{rules,0,rule_config,threshold_minutes}', '999')
   WHERE ledger_entry_id = '<LEDGER_ENTRY_ID>'
     AND organization_id = '00000000-0000-0000-0000-000000000001';
   -- NÃO atualizar integrity_hash. (A tabela é imutável por trigger; rode como
   --  superuser/migração para simular fraude de DBA — INV-3.)
   ```
3. **Checkpoint UI (obrigatório):** clique novamente em **"Visualizar Evidência Forense"**. O modal **NÃO** pode exibir os parâmetros da regra. Ele DEVE:
   - travar a leitura ("…bloqueada de forma preventiva por motivos de segurança.");
   - exibir o banner vermelho **"Divergência Crítica de Integridade"** ("Suspeita de Fraude no Banco de Dados…");
   - exibir o botão **"ESCALAR INCIDENTE"**.
4. **Checkpoint escalonamento:** clique em **"ESCALAR INCIDENTE"** → SnackBar *"Incidente de segurança escalado com sucesso."*; registro `SECURITY_INCIDENT_ESCALATION_REQUESTED` via `log-security-incident`.

**Verificação de banco — divergência confirmada:**

```sql
SELECT (public.verify_forensic_evidence(
          '00000000-0000-0000-0000-000000000001', '<LEDGER_ENTRY_ID>'
        ) ->> 'status') AS status;
-- Esperado: 'tampered' (stored_hash ≠ computed_hash).
```

---

### Passo 11 — Mapa Forense (Map-Sync WS-5)

**Tela larga (≥1200px):** split-pane — lista (esq) + `TelemetrySyncMap` (dir).
**Tela estreita (<1200px):** botão **"Mapa Forense"** no header abre um **end-drawer** com o mapa.

1. Clique num card → ele ganha borda azul + badge **"NO MAPA"**; o mapa centraliza no ponto da infração (geofence visível se houver).
2. Em tela estreita: ao focar uma sanção, o drawer abre automaticamente.
3. Clique no endereço (`ReverseGeocodedAddress`) → mapa re-centraliza (`recenter`) mesmo se já selecionado.
4. Clique no card de novo → desfoca (toggle), badge some.

**Verificação de banco — coordenadas da evidência:**

```sql
SELECT verdict_evidence ->> 'primaryEvidenceLat' AS lat,
       verdict_evidence ->> 'primaryEvidenceLng' AS lng,
       verdict_evidence ->> 'geofenceCenterLat'  AS geo_lat,
       verdict_evidence ->> 'geofenceRadiusMeters' AS geo_radius
FROM public.sanction_review_queue
WHERE id = '<QUEUE_ID>' AND organization_id = '00000000-0000-0000-0000-000000000001';
-- Esperado: lat/lng batem com o badge de coordenadas exibido no card.
```

---

### Passo 12 — Isolamento de Tenant (INV-22) — Red Team

1. Faça **logout** e login como **Inquilino B** (`admin-b@veraprob.dev`).
2. Abra **Fila Auditora** → **Selados** e **Pendentes**.
3. **Checkpoint:** **NENHUMA** sanção da Org Alpha (`TST-0001`, `<QUEUE_ID>`, set/contract da Org A) aparece para a Org B.

**Verificação de banco — RLS bloqueia leitura cross-tenant:**

```sql
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111","organization_id":"00000000-0000-0000-0000-000000000002"}';

SELECT count(*) FROM public.sanction_review_queue
WHERE organization_id = '00000000-0000-0000-0000-000000000001';
-- Esperado: 0 (RLS filtra; Org B não enxerga linhas da Org A).
ROLLBACK;
```

> INV-26 (Anti-Oracle): tentar `findById` do `<QUEUE_ID>` da Org A enquanto autenticado como Org B deve retornar **vazio/Not Found** — idêntico a um id inexistente. Nunca "acesso negado" distinguível.

---

## 📊 Matriz de Aceitação

| Cód | Validação | Esperado | Status |
|:----|:----------|:---------|:------:|
| AQ-01 | Login Inquilino A → Fila Auditora | Sessão + redirect, sem erro | `[ ]` |
| AQ-02 | Gerar Sanção de Teste | Card VEL-01 em Pendentes; row `status='pending'` | `[ ]` |
| AQ-03 | Provenance 1-clique (InvestigationModal) | Hash do card = `evidenceHash` no banco | `[ ]` |
| AQ-04 | SELAR VEREDITO | `status='applied'` + `VERDICT_SEALED` no ledger | `[ ]` |
| AQ-05 | Ledger append-only | UPDATE/DELETE bloqueado (INV-3) | `[ ]` |
| AQ-06 | Idempotência selar 2x | Erro "already applied"; 1 só entrada | `[ ]` |
| AQ-07 | RECUSAR (<10 chars desabilita) | `status='rejected'`, motivo salvo | `[ ]` |
| AQ-08 | SOLICITAR PROVA FORENSE | `status='disputed'` + `SANCTION_DISPUTED` | `[ ]` |
| AQ-09 | Filtro Selados + intervalo de datas | Lista filtra por período (UTC↔local) | `[ ]` |
| AQ-10 | CARREGAR MAIS | Paginação carrega próxima página | `[ ]` |
| AQ-11 | Baixar Dossiê | PDF gerado, dados conferem | `[ ]` |
| AQ-12 | Visualizar Evidência Forense | Modal abre por `ledgerEntryId` | `[ ]` |
| AQ-13 | Mapa Forense (foco/drawer/split) | Centraliza no ponto; coords batem | `[ ]` |
| AQ-14 | Isolamento de Tenant (Org B) | 0 sanções da Org A; RLS=0 linhas | `[ ]` |
| AQ-15 | Identidade Ativo/Operador (INV-14) | Card mostra placa + operador; `vehicle_plate`/`operator_name` na row | `[ ]` |
| AQ-16 | Rótulos VEL (Q5) | "VELOCIDADE REGISTRADA" + "LIMITE CONTRATUAL" + "EXCESSO" presentes | `[ ]` |
| AQ-17 | SELAR travado sem placa | SELAR desabilitado quando `vehicle_plate` ausente | `[ ]` |
| AQ-18 | Acento de severidade (Q3) | Borda vermelha em pendente mesmo focado | `[ ]` |
| AQ-19 | Trava em disputa (Q7) | SELAR/RECUSAR ausentes após badge âmbar | `[ ]` |
| AQ-20 | Adulteração de snapshot (10.1) | Modal trava + banner Divergência + Escalar; `verify_*`='tampered' | `[ ]` |

---

## 🤖 Automação E2E (Flutter integration_test)

> **Protocolo obrigatório (CLAUDE.md / CI Block #8, #10):**
> - Rodar **sempre** via `make test-e2e` ou `make test-e2e-file FILE=...` (injeta `--dart-define=SKIP_MFA_DEV=true`; sem isso `pumpAndSettle` trava).
> - Antes de navegação externa, fechar modais com `cancelModal(tester)` (barreira não-dismissível — Lesson #4).
> - Sem imports/locais não usados (gate de lint estrito).

**Seletores literais (conferidos contra os arquivos da tela):**

| Elemento | Seletor |
|----------|---------|
| Campo e-mail | `find.byType(TextField)` (label `'E-mail Corporativo'`) |
| Campo senha | `find.byType(TextField)` (label `'Senha de Acesso'`) |
| Botão login | `find.widgetWithText(ElevatedButton, 'ACESSAR SISTEMA')` |
| Gerar sanção | `find.widgetWithText(OutlinedButton, 'Gerar Sanção de Teste')` |
| Selar | `find.widgetWithText(FilledButton, 'SELAR VEREDITO')` |
| Recusar | `find.widgetWithText(OutlinedButton, 'RECUSAR VEREDITO')` |
| Confirmar recusa | `find.widgetWithText(FilledButton, 'CONFIRMAR RECUSA')` |
| Motivo rejeição | `find.byType(TextField)` (label `'Motivo da rejeição (mínimo 10 caracteres)'`) |
| Solicitar prova | `find.widgetWithText(TextButton, 'SOLICITAR PROVA FORENSE')` |
| Baixar dossiê | `find.widgetWithText(OutlinedButton, 'BAIXAR DOSSIÊ')` |
| Confirmar selamento (low integrity) | `find.widgetWithText(FilledButton, 'Confirmar Selamento')` |
| Filtro Selados | `find.text('Selados')` (segmento) |
| Placa (ativo) | `find.text('TST-0001')` |
| Operador | `find.text('Motorista Teste')` (ou `find.text('Não Identificado')` no fallback) |
| Rótulos VEL (Q5) | `find.text('VELOCIDADE REGISTRADA')`, `find.text('LIMITE CONTRATUAL')`, `find.text('EXCESSO')` |
| Acento severidade (Q3) | `find.byKey(const ValueKey('verdict-severity-accent'))` → cor `VeraProbColors.error` em pendente |
| Banner divergência (10.1) | `find.text('Divergência Crítica de Integridade')` + `find.widgetWithText(*, 'ESCALAR INCIDENTE')` |

> **Asserções VEL obrigatórias (Q5):** o teste do cenário VEL DEVE encontrar os três
> rótulos na árvore — KPI primário "VELOCIDADE REGISTRADA", mais "LIMITE CONTRATUAL" e
> "EXCESSO" — antes de prosseguir. Vide grupo "VEL layout" em
> `test/features/admin/presentation/widgets/sanction_verdict_card_test.dart`.

> **Realtime em E2E:** a sanção simulada chega via stream Supabase (até ~5s). Em teste automatizado, prefira semear a `sanction_review_queue` direto via helper de banco (padrão de `test/integration/e2e/helpers/`) em vez de depender do timing do Realtime — determinismo (INV-15). Use `pumpAndSettle` com timeout só após o seed estar visível.

**Cobertura pgTAP/integração existente relacionada:**
- `test/application/sla_audit/approve_sanction_handler_test.dart` — RBAC + idempotência + append ledger.
- `test/application/sla_audit/reject_sanction_handler_test.dart` / `dispute_sanction_handler_test.dart`.
- `test/integration/sanction_review_queue_test.dart` — RLS + transições de status.

---

## 🔄 Rollback / Diagnóstico

1. Erro de RLS em ação legítima → verifique a claim do JWT:
   * `sanction_review_queue`: `(auth.jwt() ->> 'organization_id')::uuid`.
2. Card não some após selar → confirme `ref.invalidate(pendingSanctionsStreamProvider)` e que o status no banco virou `applied`.
3. Sanção não aparece após "Gerar" → confirme contratos ativos (pré-condição) e aguarde a janela de Realtime (5s).
