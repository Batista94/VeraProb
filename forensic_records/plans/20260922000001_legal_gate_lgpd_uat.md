# UAT — Legal Gate LGPD (20260922000001)

Manual User Acceptance Testing checklist for the Legal Gate feature (Flutter operators + Telegram drivers).

**Companion automated coverage:** `forensic_records/plans/20260922000001_legal_gate_lgpd_test_plan.md`

---

## 1. Scope

| Surface | What you validate |
|---------|-------------------|
| **Flutter Web** | Full-screen gate at `/legal-consent` blocks admin shell until terms are accepted |
| **Telegram Bot** | Drivers must read + accept terms before binding; `/revoke` withdraws consent |
| **Admin UI** | Telegram binding dialog discloses LGPD prerequisite |
| **Ledger (DB)** | Append-only consent rows with document hash (Art. 8 audit trail) |

**Out of scope for this UAT:** Privacy Policy standalone screen (catalog exists; gate uses `terms_of_use` only in v1).

---

## 2. Prerequisites

### Environment

- [ ] Local stack up: `make setup` (or `supabase start` + migrations applied)
- [ ] Flutter app running: `make run` (Wasm web)
- [ ] Telegram webhook reachable (local tunnel or staging) with bot token configured
- [ ] **Do not** use `SKIP_LGPD_CONSENT_DEV=true` for UAT — that flag bypasses the gate (dev/E2E only)

### Test personas

The following identities are automatically provisioned by [bootstrap_dev.mjs](file:///c:/Users/wes_b/Projects/VeraProb/scripts/dev/bootstrap_dev.mjs):

| ID | Persona | Credentials / Token | Purpose |
|----|---------|---------------------|---------|
| **U1** | Tenant Admin (Org Beta) who has **never** accepted terms | `admin-b-no-terms@veraprob.dev` / `123456` | First-time gate |
| **U2** | Tenant Admin (Org Beta) who **already accepted** v1.0 terms | `admin-b-accepted@veraprob.dev` / `123456` | Regression / no re-prompt |
| **U3** | SuperAdmin (VeraProb staff) | `master@veraprob.dev` / `veraprob123!` | Bypass gate |
| **T1** | Fresh Telegram driver (unbound/unconsented) | Code: `VERAPRB2` | Driver consent + binding |
| **T2** | Pre-bound Telegram driver (consented/bound) | Code: `VERAPRB3`, Chat ID: `908453791` | Regression / bound flow |

**Reset U1 for first-time tests** (pick one):

```sql
-- Run as service_role in SQL editor — removes Flutter consent history for U1 only
DELETE FROM public.user_legal_consents
WHERE user_id = '<U1-auth-users-uuid>';
```

Or use a brand-new invited user with no prior login.

### Reference data (seed)

After migration, confirm published documents exist:

```sql
SELECT doc_type, version, status, active_to_utc IS NULL AS is_active
FROM public.legal_documents
WHERE status = 'published'
ORDER BY doc_type, published_at_utc DESC;
```

Expected: `terms_of_use` v1.0 and `telegram_bot_terms` v1.0 both active (`is_active = true`).

---

## 3. Sign-off sheet

| # | Scenario | Tester | Date | Pass / Fail | Notes |
|---|----------|--------|------|-------------|-------|
| F-01 | First login → Legal Gate | | | ☐ | |
| F-02 | Accept terms → dashboard | | | ☐ | |
| F-03 | Decline → sign-out | | | ☐ | |
| F-04 | Deep link blocked while pending | | | ☐ | |
| F-05 | Return visit no re-prompt | | | ☐ | |
| F-06 | SuperAdmin bypass | | | ☐ | |
| F-07 | Version bump re-gate | | | ☐ | |
| F-08 | Copy / hash / changelog UI | | | ☐ | |
| T-01 | /start without consent | | | ☐ | |
| T-02 | Read terms → accept (no shortcut) | | | ☐ | |
| T-03 | Bind without consent blocked | | | ☐ | |
| T-04 | Bind after consent | | | ☐ | |
| T-05 | /revoke withdraws + unbinds | | | ☐ | |
| T-06 | Evidence blocked after revoke | | | ☐ | |
| A-01 | Admin binding dialog copy | | | ☐ | |
| S-01 | Ledger hash matches document | | | ☐ | |
| S-02 | User cannot see another user's ledger | | | ☐ | |

---

## 4. Flutter — Legal Gate (tenant operators)

### F-01 — First login shows Legal Gate

**Pre:** U1 has no rows in `user_legal_consents`.

| Step | Action | Expected |
|------|--------|----------|
| 1 | Open app → `/login` | Login screen loads |
| 2 | Sign in as **U1** | Redirect to `/legal-consent` (not dashboard) |
| 3 | Observe screen | Full-screen gate; **no** admin nav / sidebar visible |
| 4 | Check header | Document title, chip `Versão 1.0 — publicada em …`, chip `SHA …` |
| 5 | Scroll reader | Markdown body readable in scroll area (max width ~720px) |
| 6 | Check footer | Checkbox unchecked; **Aceitar** disabled; **Recusar** enabled |

**Pass criteria:** User cannot reach `/admin/dashboard` or any admin route without accepting.

---

### F-02 — Accept terms unlocks dashboard

**Pre:** On Legal Gate (F-01).

| Step | Action | Expected |
|------|--------|----------|
| 1 | Read checkbox label | Mentions Termos de Uso, custódia de dados, LGPD Lei 13.709/2018 |
| 2 | Check the checkbox | **Aceitar** becomes enabled |
| 3 | Click **Aceitar** | Brief loading; no raw error text / stack trace |
| 4 | Wait for navigation | Lands on `/admin/dashboard` (or hub per role) |
| 5 | Refresh browser (F5) | Goes straight to dashboard — **no** gate |
| 6 | Verify DB (optional) | One `accepted` row for U1 with `document_content_sha256` populated |

```sql
SELECT action, document_version, document_content_sha256, consented_at_utc
FROM public.user_legal_consents
WHERE user_id = '<U1-uuid>'
ORDER BY consented_at_utc DESC
LIMIT 1;
```

**Pass criteria:** Gate cleared; ledger append-only accept row exists.

---

### F-03 — Decline signs user out

**Pre:** Fresh U1 session on Legal Gate (reset consent if needed).

| Step | Action | Expected |
|------|--------|----------|
| 1 | Click **Recusar** | Dialog: title **Recusar termos**; warns disconnect |
| 2 | Click **Cancelar** | Dialog closes; still on gate |
| 3 | Click **Recusar** again → **Recusar e sair** | User signed out |
| 4 | Observe URL | Redirect to `/login` |
| 5 | Sign in again as U1 | Gate shown again (still pending) |

**Pass criteria:** Decline never grants shell access; no consent row with `accepted` unless user explicitly accepted.

---

### F-04 — Deep link blocked while pending

**Pre:** U1 pending (not accepted).

| Step | Action | Expected |
|------|--------|----------|
| 1 | While logged in, manually navigate to `/admin/dashboard` | Redirect back to `/legal-consent` |
| 2 | Try `/admin/hub` or another admin path | Same redirect to gate |
| 3 | Try `/legal-consent` directly | Gate loads (no redirect loop) |

**Pass criteria:** GoRouter guard enforces gate on all non-exempt routes.

---

### F-05 — Return visit (already consented)

**Pre:** U2 accepted current terms (complete F-02 once for U2).

| Step | Action | Expected |
|------|--------|----------|
| 1 | Sign in as **U2** | Direct to dashboard — **no** gate |
| 2 | Manually open `/legal-consent` | Redirect to dashboard (current consent) |

**Pass criteria:** No unnecessary re-prompt on unchanged version.

---

### F-06 — SuperAdmin bypass

**Pre:** **U3** SuperAdmin account.

| Step | Action | Expected |
|------|--------|----------|
| 1 | Sign in as **U3** | SuperAdmin path (MFA flow if configured) — **no** Legal Gate |
| 2 | Manually open `/legal-consent` | Bounce to SuperAdmin tenants route |
| 3 | Confirm U3 may have **zero** `user_legal_consents` rows | Still has full staff access |

**Pass criteria:** Staff bypass; tenant users still gated.

---

### F-07 — Version bump forces re-consent

**Pre:** U2 has accepted v1.0. SuperAdmin or `service_role` publishes v2.0.

**Publish v2.0** (SQL editor as `service_role`):

```sql
SELECT public.publish_legal_document(
  'terms_of_use',
  '2.0',
  'Termos de Uso VeraProb v2.0',
  '# Termos v2.0\n\nConteúdo atualizado para UAT.',
  'UAT: nova cláusula de retenção de evidências.'
);
```

| Step | Action | Expected |
|------|--------|----------|
| 1 | Sign in as **U2** | Redirect to `/legal-consent` |
| 2 | Observe UI | Version chip shows **2.0**; amber callout **O que mudou nesta versão** with changelog text |
| 3 | Accept v2.0 | Dashboard access restored |
| 4 | Verify ledger | New `accepted` row for v2.0; prior v1.0 rows still present (append-only) |

**Pass criteria:** Version bump re-opens gate; changelog visible; old ledger rows not deleted.

---

### F-08 — Copy terms & hash tooltip

**Pre:** On Legal Gate with document loaded.

| Step | Action | Expected |
|------|--------|----------|
| 1 | Hover SHA chip | Tooltip shows full 64-char hash |
| 2 | Click **Baixar / copiar** | SnackBar: **Texto dos termos copiado…** |
| 3 | Paste clipboard | Full markdown body matches reader content |

**Pass criteria:** Art. 8 evidence copy path works; no UI errors exposed to user.

---

### F-09 — Load failure recovery (adverse)

**Pre:** Simulate outage — stop Supabase briefly **or** block network in DevTools.

| Step | Action | Expected |
|------|--------|----------|
| 1 | Open gate while API down | Message: **Não foi possível carregar os Termos de Uso.** |
| 2 | Click **Tentar novamente** | Retries fetch (no raw exception in UI) |
| 3 | Click **Sair** | Signs out to login |

**Pass criteria:** Fail-closed UX; no `$e` / PostgREST codes shown.

---

## 5. Telegram — Driver consent & binding

### T-01 — /start without consent

**Pre:** **T1** = new Telegram chat (never messaged bot, or consent cleared).

| Step | Action | Expected |
|------|--------|----------|
| 1 | Send `/start` | Welcome message; steps 1️⃣ LGPD + 2️⃣ Vincular |
| 2 | Check keyboard | Button **📋 Ler Termos de Uso (LGPD)** |
| 3 | Send 8-char binding code **without** accepting terms | Binding refused; prompted to accept terms first |

**Pass criteria:** No binding before consent.

---

### T-02 — Informed consent (read before accept)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Tap **📋 Ler Termos de Uso (LGPD)** | Full terms message (title, version, body) |
| 2 | Check buttons | **✅ Aceitar e Continuar** appears **only after** terms displayed |
| 3 | Tap **✅ Aceitar e Continuar** | Toast **✅ Termos aceitos!**; prompt to send binding code |
| 4 | Send `/start` again | Message says terms already accepted; asks for binding code |

**Pass criteria:** No one-tap accept on `/start` alone — must open `view_terms` first.

---

### T-03 — Binding without consent (adverse)

**Pre:** Fresh T1, **do not** accept terms.

| Step | Action | Expected |
|------|--------|----------|
| 1 | In admin app, generate Telegram binding token for a driver | Dialog mentions LGPD prerequisite |
| 2 | Send token to bot | Error / guidance to accept terms first (not silent bind) |

**Pass criteria:** `consume_telegram_binding_token` enforces current telegram consent.

---

### T-04 — Happy path: consent → bind → evidence

**Pre:** T1 accepted terms (T-02).

| Step | Action | Expected |
|------|--------|----------|
| 1 | Generate binding code in VeraProb admin (Telegram binding dialog) | Copy mentions: *aceita os Termos LGPD no bot (/start) antes de vincular* |
| 2 | Send 8-char code to bot | Binding success message |
| 3 | Send a photo or document | Evidence accepted (normal bot flow) |
| 4 | Send `/help` | Help text mentions `/revoke` for LGPD withdrawal |

**Pass criteria:** End-to-end driver onboarding with consent-before-binding.

---

### T-05 — /revoke withdraws consent and unbinds

**Pre:** T1 bound and operational (T-04).

| Step | Action | Expected |
|------|--------|----------|
| 1 | Send `/revoke` | **✅ Consentimento revogado**; chat unbound |
| 2 | Send `/start` | Prompted to read/accept terms again |
| 3 | Verify DB (optional) | Latest telegram row `action = withdrawn`; binding inactive |

**Pass criteria:** Art. 8 §5 withdrawal path works; user can re-consent via `/start`.

---

### T-06 — Evidence blocked after revoke

**Pre:** T-05 completed (revoked, not re-accepted).

| Step | Action | Expected |
|------|--------|----------|
| 1 | Send photo/document without re-accepting | Blocked; directed to accept terms |
| 2 | Re-accept via T-02 flow | Evidence flow available again after re-bind if needed |

**Pass criteria:** Fail-closed on missing current consent.

---

## 6. Admin UI — Operator disclosure

### A-01 — Telegram binding dialog LGPD copy

| Step | Action | Expected |
|------|--------|----------|
| 1 | Admin → open Telegram binding for a driver | Dialog visible |
| 2 | Read helper text | States driver must accept LGPD in bot via `/start` before bind |
| 3 | Read expiry note | Code expires in 15 minutes; bind refused without LGPD accept |

**Pass criteria:** OCC operator sees compliance prerequisite before sharing code.

---

## 7. Security & audit (optional but recommended)

### S-01 — Hash integrity (Flutter)

```sql
SELECT
  c.document_content_sha256 AS ledger_hash,
  d.content_sha256 AS doc_hash,
  c.document_content_sha256 = d.content_sha256 AS match
FROM public.user_legal_consents c
JOIN public.legal_documents d ON d.id = c.document_id
WHERE c.user_id = '<U1-uuid>' AND c.action = 'accepted'
ORDER BY c.consented_at_utc DESC
LIMIT 1;
```

**Pass:** `match = true` for every accepted row.

---

### S-02 — Tenant isolation (ledger SELECT)

**Pre:** U1 and U2 in same org, both with consent rows.

| Step | Action | Expected |
|------|--------|----------|
| 1 | As U1 (authenticated JWT), query own consents via app | Only U1 rows visible |
| 2 | Direct API attempt to read U2's rows (if testing with REST client) | Empty or RLS denied — never U2's data |

**Pass criteria:** `user_legal_consents` RLS is user-scoped (`JWT sub`).

---

### S-03 — Immutability spot-check

```sql
-- Must FAIL (append-only)
UPDATE public.user_legal_consents SET action = 'withdrawn' WHERE id = (
  SELECT id FROM public.user_legal_consents LIMIT 1
);
```

**Pass:** Error raised; no UPDATE allowed on ledger.

---

## 8. Regression smoke (post-UAT)

After all scenarios, run automated suite once:

```bash
make test-db   # includes 20260922000001_legal_gate_lgpd_test.sql (48 assertions)
flutter test test/app/routing/legal_gate_redirect_test.dart \
  test/features/shared/legal_consent_screen_test.dart \
  test/state/legal_consent_providers_test.dart -j 1
```

---

## 9. Known limitations (v1)

- Flutter **withdraw** exists only via RPC (`withdraw_legal_consent`) — no in-app settings UI yet; UAT decline path covers “refuse to proceed”.
- `SKIP_LGPD_CONSENT_DEV` bypasses gate in dev builds only — never enable in staging/prod UAT.
- SuperAdmin publishes new legal versions via `publish_legal_document` (service_role / staff) — no self-service publisher UI in v1.

---

## 10. UAT exit criteria

- [ ] All **Pass** scenarios in §3 marked Pass (or documented waivers with ticket ID)
- [ ] No P1 defects open (gate bypass, wrong tenant data, bind without consent)
- [ ] Ledger hashes verified for at least one Flutter accept and one Telegram accept
- [ ] Automated companion tests green (§8)

**Approved by:** ___________________ **Date:** ___________
