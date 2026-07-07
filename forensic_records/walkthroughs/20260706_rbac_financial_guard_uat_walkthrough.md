# UAT Walkthrough — RBAC & Financial Guard (2026-07-06)

Executed end-to-end against the plan at `forensic_records/plans/20260706_uat_plan_rbac_financial_guard.md`, driving the live Flutter web app (`http://127.0.0.1:50185`) via Playwright and validating state via direct Postgres queries against the local Supabase instance.

Per instruction, this report lists **only bugs, errors, and divergences from expected behavior** that need human review. Passing scenarios (role creation, four-eyes approval, live-check 42501 rejection, cap truncation on the working path, credit-back reversal, tenant isolation) are not narrated here except where needed for context on a bug.

Screenshots referenced below are under `C:\Users\wes_b\Projects\VeraProb\forensic_records\uat_evidence\20260706_rbac_financial_guard\`.

---

## 1. Financial Guard: one sanction bypassed cap truncation despite an active cap (Fase 3.1) — CRITICAL

**Expected (plan):** Any `SANCTION_RECOMMENDED` ledger insert for a contract with `monthly_penalty_cap_cents` set is truncated by `enforce_financial_guard()` (trigger `trg_financial_guard`), stamping `original_fine_cents`, `cap_truncated`, and updating `contract_penalty_monthly_accrual`.

**What actually happened:** With `monthly_penalty_cap_cents = 500` already committed on contract `ab67c52e-0e79-4ea6-9cd5-324e2f8844bb` (confirmed via a prior `SELECT` before the action), clicking **"Gerar Sanção de Teste"** in the UI at `2026-07-06T19:46:38.811Z` produced ledger row `ad9dd0bd-ebd3-49dc-b320-bac5919c6e32` (queue entry `90cf249b-2a66-4bb5-95ea-d2418fd47e11`, vehicle TST-0001) with `fine_cents = 150000`, **no** `original_fine_cents` key, and **no** `contract_penalty_monthly_accrual` row created for that contract at that time — i.e., the guard did not fire/apply for this specific insert. The corresponding UI card shows the full R$ 1.500,00 with **no "TETO ATINGIDO" badge**, even though the same contract's cap was already active.

**Reproduction attempt:** A second app-driven "Gerar Sanção de Teste" click on the same contract (with the same cap already active) at `19:52:18.351Z` (ledger `67ab093d-bb36-422e-a6dc-3f4f46b01927`) correctly truncated (`original_fine_cents: 150000`, `cap_truncated: true`, `fine_cents: 0`), and a direct raw-SQL insert simulating the identical payload also truncated correctly (`fine_cents: 500`, `cap_truncated: true`). So the guard engine itself is not broken in general — this looks like an **intermittent/race failure** on at least one insert (possibly the "no-lock cap probe" in Phase C of `enforce_financial_guard()` racing against a concurrent transaction, or a stale read before the earlier `UPDATE public.contracts SET monthly_penalty_cap_cents` was visible to that specific connection).

**Why this matters:** This is the money-enforcement core of the Financial Guard (INV-3, INV-4). An intermittent failure to cap a fine — silently, with no error surfaced anywhere — is a forensic/financial integrity risk that needs engineering investigation (concurrency/lock-timing review of `enforce_financial_guard()` Phase C/D), not just a UI fix.

**Evidence:** ledger rows `ad9dd0bd-ebd3-49dc-b320-bac5919c6e32` (broken) vs `67ab093d-bb36-422e-a6dc-3f4f46b01927` and `bb5a788d-adcb-45ef-a174-1a471d20df04` (correctly truncated) in `public.sla_audit_ledger_v2`. Screenshot `fase3_2_teto_atingido_badge.png` shows the correctly-truncated case for comparison; the broken sanction (TST-0001, R$1.500,00, no badge) is visible in the accessibility snapshot captured alongside it in the same auditor-queue session.

---

## 2. Settings tab bar becomes completely unresponsive after login + direct navigation — requires manual reload (Fase 1.2, 1.3, 2.2, 4.2, 5.2) — reproduced 5 times

**Expected:** Clicking a tab (`Acessos`, `Equipe`, etc.) in `/admin/hub/settings` switches the tab content immediately.

**What actually happened:** Every single time a fresh login was followed by `goto('/admin/hub/settings')` (a normal `page.goto`, equivalent to a user navigating to Settings right after logging in), the **first click on any tab did nothing** — the tab bar stayed on "Geral" with no visual or state change, and this was not a stale-selector issue (confirmed via `aria-label` locator and `force: true` click, both no-ops). The only fix was a full page reload (`F5` / re-`goto`), after which the exact same tab click worked immediately.

This happened identically after: login as admin-a → Settings (before approving the role), login as admin-a2 (2nd admin) → Settings, re-login as admin-a → Settings (before revoking access), login as admin-b (Org Beta) → Settings. 4-for-4 reproduction rate across independent sessions — this is not a one-off flake.

**Why this matters:** This is exactly the class of bug the task asked to flag explicitly: a page requiring a manual refresh for basic navigation to work after an action (here, right after auth state settles). A real user landing on Settings right after login would see an apparently-frozen tab bar with no error, no loading indicator, and no indication that a refresh is needed.

**Evidence:** Reproduced with matching before/after snapshots in the session log; visually confirmed via `fase5_geral_operator_name_final.png` (post-reload) vs the frozen pre-reload snapshots (not screenshotted individually since the accessibility tree already proves the stuck state — tab remained `[selected]` on "Geral" across two consecutive clicks with no DOM change).

---

## 3. Settings/Acessos panel overflows horizontally at 1024×600 — Salvar button and part of the permission list pushed off-screen with no horizontal scroll (Fase 5.2)

**Expected (plan):** "A lista de módulos e permissões deve possuir rolagem independente... O botão 'Salvar' deve estar visível e fixado no rodapé... sem ser sobreposto por outros elementos ou ficar oculto."

**What actually happened:** At a 1024×600 viewport (a common small-laptop resolution, not an extreme/mobile case), `document.body.scrollWidth` measured **1280px** against a `clientWidth`/`document.documentElement.scrollWidth` of **1024px** — a genuine 256px horizontal overflow with **no horizontal scrollbar exposed**, so the overflowed content (right portion of the permission editor, including — per the accessibility tree — the `Salvar` button) is not reachable at all at this width, only via widening the browser window. No `RenderFlex overflow` exception was thrown to the console (consistent with this being a fixed/unresponsive minimum-width layout rather than a widget-level flex overflow), but the net effect described in the plan's acceptance criterion (Salvar always visible/reachable) is violated.

**Evidence:** `fase5_2_narrow_viewport_matrix.png`, `fase5_3_sticky_salvar_button.png` (both show the panel content cut off at the right edge of the 1024px viewport, Salvar button not visible in either).

---

## 4. Minor: reason-code dropdown mislabeled "(taxonomia)" as maintenance-specific across all sanction actions (Fase 3.1, 3.2)

**Expected:** Contextual label for the reason-code selector shown in the "Confirmar Infração" and "Anular Infração" dialogs.

**What actually happened:** Both dialogs show the same generic dropdown label **"Motivo da manutenção (taxonomia)"** ("Maintenance reason (taxonomy)") regardless of context — confirming a sanction and annulling a sanction both display a label that reads as if it were for equipment/vehicle maintenance, not for the sanction-review action being performed. Functionally harmless (the correct reason-code taxonomy values are offered and selectable), but it's user-facing copy that doesn't match the action, likely a shared/reused widget whose label wasn't parameterized per call site.

**Evidence:** `fase3_1_confirm_dialog.png`, `fase3_4_anular_dialog.png`.

---

## 5. No confirmation dialog when revoking a user's access profile (Fase 2.2)

**Expected (plan):** "Confirmar a remoção" — implies an explicit confirmation step before a role/profile is unassigned from a user.

**What actually happened:** Clicking the "Excluir" (x) icon on the `Auditor Financeiro Restrito` chip in the Equipe tab immediately revoked the role server-side (`user_tenant_roles.revoked_at` stamped) with **no confirmation prompt** of any kind — single click, no undo, no "are you sure". Given this is a security-sensitive action (removing access), the lack of a confirmation step is worth a product decision (intentional fast-path vs. missing safety net).

**Evidence:** `fase2_2_role_revoked_no_confirm.png` (taken immediately post-click, showing the chip already gone).

---

## 6. Minor: `?tab=access` / `?tab=...` query parameter does not select the corresponding Settings tab

**Expected (plan Fase 1.1):** Navigating to `/admin/hub/settings?tab=access` opens directly on the "Acessos" tab.

**What actually happened:** The query parameter was ignored every time (3+ occurrences) — the screen always loaded on "Geral" regardless of the `tab=` value in the URL, requiring a manual tab click afterward. Low severity (no deep-link bookmarking use case broken beyond convenience), but it is a divergence from the plan's documented route contract.

---

## Environment/methodology note (not a product bug)

Fase 2's "two simultaneous browser sessions" (test user vs. admin revoking access) could not be run as two truly concurrent authenticated sessions: Playwright tabs opened in the same browser context share Supabase's `localStorage` session and `BroadcastChannel` auth-state sync, so logging in as a second user in a new tab silently signs out the first tab's session (confirmed: opening a second tab immediately inherited the first tab's session without a login prompt, and logging out in either tab logged out both). Fase 2.3 (live-check O(1) rejection with a stale-but-still-valid JWT) was therefore validated via direct SQL simulation of the JWT claims against the `approve_sanction` RPC rather than two live browser tabs — this is the same technique the plan itself prescribes for Fase 4. Result matched the plan exactly: Postgres error `42501`, message "Permission revoked or insufficient".
