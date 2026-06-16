# UAT — Dispute / Sanction Lifecycle (Full E2E, manual + agent-runnable)

> **Purpose.** End-to-end User Acceptance Test for the dispute reality stack: login → SLA sanction → auditor verdict → carrier dispute portal → counter-evidence / "De Acordo" → auditor resolution → rule lifecycle (Rule Studio) → read-model analytics. Every step lists **action**, **expected**, and **error-path** so a QA agent can drive the UI exactly as a human would and assert pass/fail.
>
> **Standard:** B2B enterprise (not MVP). A scenario fails if ANY error surfaces a raw DB code, stack trace, `[DBG]` prefix, English infra text, or one tenant sees another tenant's data (INV-22 / INV-26 / Lesson 5).

---

## 0. Pre-conditions & environment

| Item | Value |
|------|-------|
| Stack up | `supabase start` + `make run` (web, Wasm/CanvasKit) |
| App URL | `http://localhost:<flutter-web-port>` |
| Org A admin | `admin-a@veraprob.dev` / `123456` |
| Org B admin | `admin-b@veraprob.dev` / `123456` (cross-tenant isolation only) |
| MFA | Tenant admins = no MFA. Super-admin only (out of scope here). |
| Debug build | Required — the **Gerar Sanção de Teste** button (`Icons.science_outlined`) renders only in `kDebugMode`. |
| Reset between runs | `make setup` (db reset + seeds) for a clean ledger. |

**Selector legend** (literal labels verified against source — use exact text):
- Login: `TextField` "E-mail Corporativo", `TextField` "Senha de Acesso", `ElevatedButton` **ACESSAR SISTEMA**.
- Auditor card actions (pending): **SELAR VEREDITO**, **RECUSAR VEREDITO** (→ **CONFIRMAR RECUSA**), **SOLICITAR PROVA FORENSE**.
- Auditor card actions (disputed): **GERAR LINK DE DISPUTA**, **ANULAR MULTA** (→ **CONFIRMAR ANULAÇÃO**, perdoa a multa), **MANTER MULTA** (→ **CONFIRMAR MANUTENÇÃO**, mantém/sela a multa), **CANCELAR SOLICITAÇÃO** (retrata).
- Reason-code taxonomy: dropdown `dispute-reason-code-dropdown` (ex.: "Falha de Sensor", "Outro (ver comentário)"). Mandatory on RECUSAR / ANULAR / MANTER.
- Portal: **Selecionar e enviar**, **Confirmar De Acordo**.
- Rule Studio: **Agendar**, **Aposentar**.

---

## 1. Authentication

### TC-1.1 — Login success (happy path)
1. Open app → redirect lands on `/login` ("Autenticação Corporativa", "Plataforma de Auditoria SLA").
2. Type `admin-a@veraprob.dev` into "E-mail Corporativo".
3. Type `veraprob123!` into "Senha de Acesso".
4. Click **ACESSAR SISTEMA**.

**Expected:** spinner, then route `/admin/dashboard`; admin shell + sidebar render. No error text.

### TC-1.2 — Empty fields
1. At `/login`, leave both fields blank, click **ACESSAR SISTEMA**.

**Expected:** inline error **"Preencha E-mail e Senha"**. No network call, stays on `/login`.

### TC-1.3 — Wrong credentials
1. Email `admin-a@veraprob.dev`, password `wrong`, click **ACESSAR SISTEMA**.

**Expected:** error under password field **"Credenciais Incorretas"**. No raw Supabase/Gotrue text, no stack trace. Stays on `/login`.

### TC-1.4 — Protected route while logged out
1. While unauthenticated, navigate URL directly to `/admin/auditor-queue`.

**Expected:** router redirect bounces to `/login` (no NotFoundPage dead-end — AUTH-TRAP closed).

### TC-1.5 — Session restore (F5)
1. After TC-1.1, press F5 on `/admin/dashboard`.

**Expected:** stays authenticated, same screen restores (go_router + session).

---

## 2. Generate a sanction (engine verdict → queue)

### TC-2.1 — Inject test sanction
1. Sidebar → **Tribunal de Auditoria** (`/admin/auditor-queue`).
2. Ensure filter segment **Pendentes (n)** selected.
3. Click **Gerar Sanção de Teste** (`Icons.science_outlined`).

**Expected:** snackbar **"Sanção VEL-01 injetada — aguarde até 5s para aparecer na fila."** Within ~5s (Realtime) a new `SanctionVerdictCard` appears; Pendentes count +1.

**Error path:** no active contract → snackbar **"Não foi possível simular a sanção. Verifique se há contratos ativos."** (run `make setup` to seed). Missing org → **"Organização não encontrada. Faça login novamente."**

### TC-2.2 — Verdict provenance (≤10s standard)
1. On the pending card, inspect verdict evidence (rule type, telemetry, SHA-256 provenance). On wide screens (≥1200px) the **Mapa Forense** split-pane shows the geolocation; on narrow, toggle via **Mapa Forense** button.

**Expected:** auditor can trace verdict → raw telemetry in 1 interaction. No missing/blank evidence fields.

---

## 3. Auditor verdict paths

### TC-3.1 — Seal verdict (SELAR)
1. On a pending card, click **SELAR VEREDITO**.
2. Confirm any modal (`barrierDismissible: false` → must use explicit confirm/cancel, never tap through barrier).

**Expected:** card leaves Pendentes; appears under **Concluídos** segment. Append-only ledger entry sealed (no UPDATE). Snackbar success in domain language.

### TC-3.2 — Reject verdict (RECUSAR)
1. On a pending card, click **RECUSAR VEREDITO**.
2. The reason zone reveals the `dispute-reason-code-dropdown` + a free-text note field. **CONFIRMAR RECUSA** stays disabled until a structured reason code is selected AND the note is ≥10 chars (BUG-01: a missing code is what caused the PGRST202 — the code is now mandatory client- and server-side).
3. Select a reason (e.g. "Falha de Sensor"), type a note ≥10 chars, click **CONFIRMAR RECUSA**.

**Expected:** removed from Pendentes; not penalized; `VERDICT_REFUSED` ledger fact embeds the `reason_code`. No raw error, no PGRST202.

**Error path:** selecting no reason code, or a note <10 chars, keeps **CONFIRMAR RECUSA** disabled (no submission attempt).

### TC-3.3 — Request forensic proof → moves to dispute
1. On a pending card, click **SOLICITAR PROVA FORENSE**, confirm.

**Expected:** card moves to **Aguardando Evidência (n)** lane (disputed). An SLA resolution timer/due date is set.

### TC-3.3b — Generate the carrier portal link (GERAR LINK DE DISPUTA)
1. On the disputed card (Aguardando Evidência), click **GERAR LINK DE DISPUTA**.

**Expected:** a copyable URL `…/portal/dispute?token=<uuid>` appears (key `dispute-portal-url`) with a copy button + snackbar **"Link de disputa gerado."** A `DISPUTE_PORTAL_TOKEN_GENERATED` ledger fact is appended. This is the token used in §4 (BUG-02: before this wiring `dispute_portal_tokens` was always empty and the carrier never got a link).

**Error path:** entry not contested → opaque domain message (no 42501/SQL leak).

### TC-3.4 — Overdue dispute drill-down
1. Switch to **Aguardando Evidência**. If a `SlaBreachBadge` indicates overdue, click it.

**Expected:** dismissible banner **"Filtrando N disputa(s) com SLA vencido"** + **LIMPAR** clears filter (no silent state — Lesson 5). If none overdue: **"Nenhuma disputa vencida."**

---

## 4. Carrier Dispute Portal (public, tokenized — no session)

> Reached at `/portal/dispute?token=<uuid>` — the token minted by the auditor in TC-3.3b. Open in a **logged-out** browser/incognito to prove no session is required.

### TC-4.1 — Invalid / missing token
1. Open `/portal/dispute` (no `?token=`).

**Expected:** renders login screen (router fallback). 

2. Open `/portal/dispute?token=00000000-0000-0000-0000-000000000000`.

**Expected:** "Validando link..." → card **"Link Inválido"** with domain message ("Link inválido ou expirado."). No raw PostgrestException / 404 oracle distinction between not-found vs wrong-org (INV-26).

### TC-4.2 — Disputed snapshot → submit counter-evidence
1. Open the portal with a valid token for a sanction in `disputed` state (from TC-3.3).

**Expected:** header **"Portal de Disputa"**, verdict summary (rule type + description), **"Evidências (n)"** list with `SHA-256 …` prefixes, and the **"Contestar — enviar contraprova"** branch.

2. Click **Selecionar e enviar**, pick a valid PDF/PNG/JPG ≤10 MB.

**Expected:** button → "Enviando...", then snackbar **"Contraprova enviada. Aguardando análise do auditor."** Snapshot reloads.

### TC-4.3 — File validation error paths
| Input | Expected snackbar |
|-------|-------------------|
| Unsupported ext (e.g. `.exe` / `.docx`) | **"Tipo não permitido. Use JPG, PNG, PDF, HEIC ou WEBP."** |
| Empty/0-byte file | **"Arquivo vazio ou ilegível."** |
| File > 10 MB | **"Arquivo excede 10 MB."** |
| Content ≠ declared type (MIME spoof) | **"O conteúdo do arquivo não corresponde ao tipo informado."** |
| Corruption mid-upload (hash) | **"O arquivo foi alterado durante o envio. Tente novamente."** |

All must be opaque domain messages — never a raw infra/DB error.

### TC-4.4 — Applied snapshot → "De Acordo" (accept penalty)
1. Open the portal with a token for a sanction in `applied` state.

**Expected:** green **"De Acordo — aceitar penalidade"** branch, with **"Hash do registro: <64-hex>"** (selectable, full hash visible).

2. Click **Confirmar De Acordo**.

**Expected:** button → "Registrando...", then card flips to **"Penalidade Aceita"** ("Seu aceite foi registrado de forma definitiva e auditável. Obrigado."). Hash-bound acknowledgement persisted (INV-9). Re-clicking is guarded (no double-submit, `_isSaving`).

### TC-4.5 — Idempotent re-acknowledge
1. Reload the same token after TC-4.4.

**Expected:** no error; acknowledgement is stable (single ledger row). No duplicate penalty.

---

## 5. Auditor resolves the dispute

### TC-5.1 — Counter-evidence appears in queue
1. Log back in as Org A admin → **Tribunal de Auditoria** → **Aguardando Evidência**.

**Expected:** the disputed card now reflects the carrier's submitted evidence (from TC-4.2), pending auditor decision.

### TC-5.2 — Resolve the dispute (ANULAR MULTA / MANTER MULTA / CANCELAR)
1. Open the disputed card. Three resolution arcs are available:
   - **ANULAR MULTA** → **CONFIRMAR ANULAÇÃO**: forgives the fine (`disputed → rejected`). Requires a structured reason code **and** a written comment ≥10 chars.
   - **MANTER MULTA** → **CONFIRMAR MANUTENÇÃO**: upholds + seals the fine (`disputed → applied`, INV-21). Requires a reason code (free-text only for "Outro").
   - **CANCELAR SOLICITAÇÃO**: retracts back to Pendentes (no reason).
2. Pick an arc, fill the reason-code dropdown (+ comment where required), confirm.

**Expected:** terminal state recorded; card moves to **Concluídos** (or back to Pendentes for cancel). The confirm button stays disabled until the mandatory reason code (and comment, for ANULAR) is provided — an empty/invalid reason is blocked client-side and would otherwise be rejected server-side with a domain message (never a 42501/SQL leak).

> **Naming note:** the buttons formerly read "INIBIR VIOLAÇÃO" / "AFIRMAR VIOLAÇÃO" — renamed to **ANULAR MULTA** / **MANTER MULTA** for clarity (action stated in financial outcome terms).

### TC-5.3 — "De Acordo" lane
1. Switch to the **De Acordo** segment.

**Expected:** acknowledged penalties (from TC-4.4) listed. Empty period → **"Nenhuma penalidade em 'De Acordo' neste período."**

---

## 6. Defense Portal (internal justification queue)

### TC-6.1 — List + filter
1. Sidebar → **Portal Defesa** (`/admin/defense-portal`).

**Expected:** header **"Portal Defesa"** + pending badge ("N pendente(s)"). Table columns: CONTRATO / SET ID / CATEGORIA / ENVIADO EM / STATUS. Empty → **"Nenhuma justificativa encontrada."**

2. Click chips **Todos / Pendentes / Aprovadas / Rejeitadas**; type in "Buscar por contrato ou SET ID...".

**Expected:** list narrows accordingly; no crash on no-match.

### TC-6.2 — Submit + approve/reject
1. Click **Nova Justificativa**, fill the form, submit.
2. Tap a row → detail drawer → approve/reject (INV-24).

**Expected:** status badge updates via Realtime. Reject without reason blocked with domain message.

---

## 7. Rule Studio (contract rule lifecycle)

> Navigate: **Contratos** (`/admin/hub/contracts`) → open a contract → Rule Studio (`/admin/hub/contracts/:id/rules`). Sidebar selection stays on Contracts.

### TC-7.1 — View active rules + history
**Expected:** header **"Estúdio de Regras SLA"**; "Regras Ativas" cards (type, `v<n>`, config summary); "Histórico de Versões" panel. Empty contract → **"Nenhuma regra ativa configurada para este contrato."** Load failure → **"Não foi possível carregar as regras ativas."** / **"...o histórico de regras."**

### TC-7.2 — Schedule a future version (Agendar)
1. On a schedulable rule card, click **Agendar**, set a future effective date + new params, confirm.

**Expected:** amber **"Versão agendada (v<n>) — vigência dd/MM/yyyy HH:mm"** badge appears. Append-only (old version preserved). Non-schedulable type → button disabled w/ tooltip **"Tipo de regra não suportado pelo agendador"**.

### TC-7.3 — Retire a rule (Aposentar)
1. Click **Aposentar** → confirm dialog ("Encerrar a versão ativa de ...? O histórico é preservado (append-only).") → **Aposentar**.

**Expected:** snackbar **"Regra aposentada. Histórico preservado."** Active list refreshes; history retains the retired version. Error → red snackbar with domain message (no raw DB code — verified mapped to `IntegrityException`/`SovereigntyViolationException`).

### TC-7.4 — Cancel paths
1. In retire dialog click **Cancelar**; in schedule dialog dismiss.

**Expected:** no mutation, no error.

---

## 8. Read-model analytics

### TC-8.1 — Fleet Risk
1. Navigate `/admin/hub/fleet-risk`.

**Expected:** carrier ranking + risk thermometer render from the MV/RPC. Empty data → empty-state, not error. Values reflect sanctions created above.

---

## 9. Cross-tenant isolation (INV-22 / INV-26) — CRITICAL

### TC-9.1 — Org B cannot see Org A data
1. Log out, log in as `admin-b@veraprob.dev`.
2. Visit Tribunal de Auditoria, Portal Defesa, Fleet Risk.

**Expected:** ONLY Org B data. Zero Org A sanctions/justifications/carriers visible.

### TC-9.2 — Cross-tenant deep link
1. As Org B, paste an Org A contract Rule Studio URL (`/admin/hub/contracts/<orgA-contract-id>/rules`).

**Expected:** not-found / empty — identical to a non-existent id (anti-oracle, INV-26). Never Org A's rules, never a distinct "wrong org" error.

### TC-9.3 — Cross-tenant portal token
1. (If feasible) use an Org A dispute token while reasoning as Org B context.

**Expected:** token resolves only to its bound org; no leakage.

---

## 10. Sign-out

### TC-10.1 — Logout returns to login
1. Sign out from the shell.

**Expected:** lands on `/login` (global signedOut redirect — no NotFoundPage). Re-visiting a protected URL bounces to `/login`.

---

## Pass / Fail summary grid

| # | Scenario | Pass | Notes |
|---|----------|------|-------|
| 1.1–1.5 | Auth (success/empty/wrong/guard/restore) | ☐ | |
| 2.1–2.2 | Sanction injection + provenance | ☐ | |
| 3.1–3.4 | Verdict seal/reject/forensic/overdue | ☐ | |
| 4.1–4.5 | Portal token/submit/validation/De Acordo/idempotent | ☐ | |
| 5.1–5.3 | Auditor dispute resolution + De Acordo lane | ☐ | |
| 6.1–6.2 | Defense Portal list/submit/approve | ☐ | |
| 7.1–7.4 | Rule Studio view/schedule/retire/cancel | ☐ | |
| 8.1 | Fleet Risk analytics | ☐ | |
| 9.1–9.3 | Cross-tenant isolation | ☐ | |
| 10.1 | Sign-out redirect | ☐ | |

**Global gates (any failure = UAT fail):** no raw DB code/stack/`[DBG]`/English infra text in ANY error; no cross-tenant leak; all monetary values BIGINT-cents accurate; all timestamps local-rendered from UTC; double-submit guarded everywhere.
