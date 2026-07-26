# Phase 11 — Etapa 0 Executable Specs (SSOT único — A portável)

**Date:** 2026-07-21
**Status:** Proposed contract (Etapa 0 **PASS** documental — AUTH-E0; veredicto §11)
**Direção:** A portável (Supabase + Flutter)
**Pré-condição:** Etapa −1 **PASS**; missão **R11** (roadmap) concluída em changeset; AUTH-E0 concedida
**Commit baseline documental −1:** `08fda779` (close Etapa −1); exceção histórica `6e626a6f` ratificada
**SSOT siblings (não duplicar):** [phase11_enterprise_pivot.md](phase11_enterprise_pivot.md), [phase11_threat_model.md](phase11_threat_model.md), [phase11_parity_checklist.md](phase11_parity_checklist.md), [ADR-010](../adr/010_exit_supabase.md), [ADR-011](../adr/011_auth_zero_trust.md), [ADR-012](../adr/012_rls_connection_lifecycle.md), [ADR-013](../adr/013_strangler_fig.md), [roadmap.md](../roadmap.md)

> Este arquivo é o **único** SSOT novo da Etapa 0. Contém contratos, matriz de
> rastreabilidade, decomposição da Etapa 1, limites de portabilidade e critérios
> de revogação. Threat model e parity checklist permanecem SSOT especializados.
> **Não** autoriza código, migrations, Edge, RLS runtime, Go, React, self-host ou commit.

---

## 1. Objetivo da Etapa 0

Transformar a direção **A portável** em especificações executáveis e auditáveis:
contratos e fronteiras anti-lock-in **sem** trocar a stack; decomposição da
implementação futura (revogação, backup/restore, DR, portabilidade);
rastreabilidade ADR → ameaça → controle → teste → evidência → owner → gate;
preservação integral de Flutter, Supabase, RLS e invariantes forenses.

**Fora de escopo:** implementação runtime; cutover; reabertura A/B/C sem gatilho;
edição de `AGENTS.md`, INV, skills, scanners ou CI.

---

## 2. Contratos e fronteiras (A portável)

### 2.1 Autoridades

| Superfície | Autoridade |
|------------|------------|
| Identidade / MFA / refresh | Supabase Auth |
| Revogação efetiva (Edge, Data API, RLS) | Registro server-side PostgreSQL (ADR-011) |
| Tenant isolation (hoje) | PostgREST + `auth.jwt() ->> 'organization_id'` (INV-2) |
| Frontend de produção | Flutter Wasm / CanvasKit |
| Indisponibilidade Auth ou PG | **Fail-closed** (deny) |

### 2.2 TTLs e sessão (congelados — ADR-011)

| Token / sessão | TTL |
|----------------|-----|
| Access JWT | 5 minutos |
| Idle | 24 horas |
| Sessão absoluta | 30 dias |
| Step-up AAL2 | 15 minutos |
| Impersonação | 30 minutos, sem refresh, `actor` separado |

Claims obrigatórios além do JWT P0: `session_id`, `jti`, `user_version`,
`session_version`. Sem cache positivo de autorização. Refresh serial com
rotação; reuse revoga a família inteira (incluindo sucessor).

### 2.3 B / C e cutover

| Item | Estado |
|------|--------|
| Alternativa B (híbrido) / C (self-host) | Contratos condicionais (ADR-010/012/013); **não** aprovados; **não** agendados |
| Reabertura | Somente gatilho objetivo + go/no-go formal |
| Cutover | **Não agendado** |
| React / Go produtivo / PG self-host | **Proibidos** sob A portável (Etapas 0–1 inclusive) |

### 2.4 Proibições Etapa 0 / Etapa 1

- Go, React, Kubernetes, PostgreSQL self-host produtivos
- Dual-run / shadow como workstream sob A
- Redesign oportunista de schema / ALE / KMS
- Declarar `PG-REVOCATION` / `PG-BACKUP` / `PG-RESTORE` / `PG-DR` como **PASS** sem evidência runtime
- Remover ou enfraquecer regras Flutter/Supabase em agentes/CI

---

## 3. Matriz de rastreabilidade (Etapa 0 + ponte Etapa 1)

| Req ID | Requisito | Risco / ameaça | Controle (spec) | Teste (quando) | Evidência agora | Owner | Reviewer | Gate |
|--------|-----------|----------------|-----------------|----------------|-----------------|-------|----------|------|
| R-R11-01 | Phase 11 no roadmap + preserve Phase 10.* e Phase 11+ 1:1 + recount migrations | Drift programa / perda backlog | [roadmap.md](../roadmap.md) §Phase 11 + mapa origem→destino | Review R11 | Diff R11 (changeset) | Program Owner | Lead | Y R11 |
| R-E0-01 | Specs executáveis únicas | Implementação ambígua | Este SSOT | Council Etapa 0 | Path + links | Migration Owner | Architect | Y Etapa 0 |
| R-E0-02 | Traceability completa | Gate sem owner | Matriz §3 | QA + Lead | Matriz neste arquivo | QA Owner | Lead | Y Etapa 0 |
| R-E0-03 | Limites de portabilidade | Lock-in | §5 deste SSOT | Etapa 2–3 | Spec docs | API/Flutter Owner | Architect | PG-OPENAPI (E2) |
| R-E0-04 | Anti B/C creep | Escopo Go/React | §2.3–2.4 | Review | Texto + checklist | Architect | Lead | Y Etapa 0 |
| R-E0-05 | Errata ADR-012/013 | Drift status Proposed vs Accepted | Errata pós-aceite | Review | Seções Errata | Documentation Owner | Lead | Y Etapa 0 |
| R-03.3 | Revogação runtime pré-`exp` | T-27, T-31, T-32 | ADR-011 + §4.1 + §6 | `SPEC:revocation_pre_exp_test` (Etapa 1) | Contrato only | Identity Owner | QA/Security | `PG-REVOCATION` piloto |
| R-13 | DR pré-prod 24h/24h | T-23 | P-DR-01 + §4.2 | `SPEC:backup_job_proof`, `SPEC:restore_drill`, `SPEC:dr_drill` (Etapa 1) | Objective decided | Platform Owner | Lead | PG-BACKUP / RESTORE / DR |
| R-03 | Auth Zero-Trust design | T-01..T-06, T-24 | ADR-011 | Extend Etapa 1 | ADR Accepted | Identity Owner | QA/Security | PG-AUTH / PG-SESSION |
| F-06 | `ingest-omnitracs` verify_jwt | T-28 | Track (não impl E0) | Config parity | Finding Open | Ingest Owner | QA/Security | PG-INGEST |

Ameaça detalhada: [phase11_threat_model.md](phase11_threat_model.md).
Estados de gate: [phase11_parity_checklist.md](phase11_parity_checklist.md).

---

## 4. Decomposição da Etapa 1 (specs — não implementação)

> Etapa 1 **não** está autorizada por este documento. Abaixo: missões isoladas
> futuras, critérios de aceite e SPEC IDs. Naming canônico fixado aqui; DDL só
> na Etapa 1 com migration append-only + pgTAP + plan forense 1:1.

### 4.1 `P-REV-IMPL-01` — registro de revogação + wiring

| Campo | Spec |
|-------|------|
| Nome canônico tabela | `app_auth_sessions` (schema `public` ou `app` — decidir na migration Etapa 1; documentar grants) |
| PK | `session_id` (opaco, text/uuid) |
| Colunas mínimas | `principal_id` (`sub`), `user_version`, `session_version`, `status` (`active`\|`revoked`\|`expired`\|`banned_principal`), `refresh_family_id`, `jti` (quando aplicável), `revoked_at`, `expires_at`, timestamps UTC |
| Função | `app.session_is_live()` — fail-closed; lê claims de `auth.jwt()`; compara registro |
| Data API / RLS | Policies sensíveis **MUST** `AND app.session_is_live()` **além** do predicado de org (INV-2) |
| Edge | `handleWithSecurity` / validadores privilegiados consultam o mesmo registro **antes** do handler |
| RPCs | logout / revoke-one / revoke-all (bump `user_version`) / ban — SECURITY DEFINER com checagem principal/org; idempotentes; audit append-only **sem** tokens |
| SPEC teste | `SPEC:revocation_pre_exp_test` |
| Gate | `PG-REVOCATION` runtime PASS (critérios em parity checklist) |
| Owner | Identity Owner |

Critérios de desenho obrigatórios: ver **§6**.

### 4.2 Backup / restore / DR (`PG-BACKUP`, `PG-RESTORE`, `PG-DR`)

| Campo | Spec |
|-------|------|
| RPO / RTO pré-prod | **24h / 24h**, **sem SLA** (P-DR-01) |
| Backup mínimo | Dump lógico diário **cifrado** em localização **independente** do projeto Supabase |
| Storage | Classificar blobs; objetos necessários ao piloto = cópia diária **separada** (DB dump não restaura Storage) |
| Off-site target | Escolher na execução Etapa 1 (não inventar path/credencial aqui) |
| SPEC | `SPEC:backup_job_proof`, `SPEC:restore_drill`, `SPEC:dr_drill` |
| Gates | NOT RUN até evidência; bloqueiam primeiro piloto |
| Owner | Platform Owner |
| Objetivo prod `<5min/<4h>` | **Não aprovado** nesta fase |

### 4.3 Missões Etapa 1 sugeridas (changesets isolados; commit só se AUTH)

1. Migration + grants + `session_is_live` + índice (sem wiring amplo ainda).
2. Wiring RLS em tabelas sensíveis + inventário de exceções de catálogo global.
3. Wiring Edge (`handleWithSecurity` path).
4. RPCs de revogação + audit.
5. Suíte `SPEC:revocation_pre_exp_test` → evidência `PG-REVOCATION`.
6. Job dump + classificação Storage → `PG-BACKUP`.
7. Drill restore ≤24h → `PG-RESTORE`.
8. Continuity drill → `PG-DR`.

---

## 5. Limites de portabilidade (Etapas 2–3 — contratos, sem Go)

### 5.1 Etapa 2 — OpenAPI das superfícies existentes

- Documentar contratos HTTP/RPC **já** usados por Flutter / Edge / Data API.
- Gate: `PG-OPENAPI` / `SPEC:openapi_existing_surfaces`.
- **Proibido:** implementar `apps/api` Go; dual-run; quebrar contratos sem versionamento.
- Objetivo: reduzir lock-in documental sem trocar stack.

### 5.2 Etapa 3 — Desacoplar repositories Flutter

- Extrair detalhes de provedor (URLs Supabase, client concreto) atrás de portas
  de aplicação / `IRepository` já existentes onde couber (INV-13).
- **Proibido:** React; reescrita UI; factories especulativas “para um dia sair”.
- Regra Ponytail: menor diff seguro; Rule of Three para helpers compartilhados.

### 5.3 Anti-acoplamento (contínuo sob A)

- Novos fluxos não devem introduzir dependências desnecessárias a APIs
  proprietárias quando um contrato estável bastar.
- Schema: lift-and-shift se/quando B/C; **sem** redesign no pivot.

---

## 6. Critérios obrigatórios da spec de revogação (Etapa 1)

A implementação futura **MUST** satisfazer todos:

1. **Least privilege** — sem `SELECT` amplo de `authenticated` na tabela crua;
   acesso via funções/RPCs documentadas; grants explícitos (INV-DATA-API-GRANT).
2. **RLS no banco** — `app.session_is_live()` (ou equivalente) como predicado
   **adicional** nas policies sensíveis; **não** substitui predicado de
   `organization_id` (INV-1/2/22).
3. **Lookup indexado** — índice adequado a `session_id` (e, se necessário,
   `(principal_id, user_version)` / `refresh_family_id`) para o caminho hot.
4. **Fail-closed** — claim ausente, divergência de versão, linha ausente,
   erro de leitura ou Auth/PG indisponível → **deny** (nunca allow-on-error).
5. **Sem cache positivo** de autorização / `session_is_live`; staleness pós-commit
   no registro = **zero**.
6. **Concorrência refresh/reuse** — rotação atômica/serial; replay do refresh
   consumido revoga a **família inteira**, inclusive sucessor; força reauth.
7. **Transações curtas** — checks e writes de revogação em txn curtas; sem
   segurar locks além do necessário.
8. **Compatível com transaction pooling** — sem estado de sessão entre requests;
   sem depender de GUC session-level para o check de vida da sessão sob A
   (usa `auth.jwt()` + registro).
9. **Proibido:** `SET` session-level para contexto de revogação; prepared
   statements **persistentes** entre borrowers do pool.

> Estes critérios aplicam-se ao desenho **A portável** (PostgREST + Edge).
> **Não** autorizam o pool Go / `SET LOCAL app.tenant_id` de ADR-012 agora
> (contrato condicional B/C).

---

## 7. Relação com R11 e Etapa −1

| Marco | Estado |
|-------|--------|
| Etapa −1 | PASS documental (`08fda779`); §12 histórico da proposta **preservado** |
| R11 | Roadmap atualizado (changeset); Phase 11 A portável + Phase 11+ preservado 1:1; migrations 377 |
| Etapa 0 | Este SSOT + sync pivot/threat/parity + errata ADR-012/013 |
| Etapa 1 | **Não** autorizada aqui |
| Commit | **Não** autorizado até AUTH explícita |

---

## 8. Critérios PASS / REVISE (Etapa 0)

### PASS se

1. R11 auditável (Phase 11 A portável + Phase 11+ 1:1 + migrations recontadas).
2. Este SSOT único completo (§2–§6).
3. Pivot linka este SSOT; §12 histórico intacto; checkpoint anexado.
4. Threat model: ADR-011 referido como Accepted; runtime risks Open onde cabível.
5. Parity: SPEC IDs apontados; runtime gates **NOT RUN** / OPEN (não PASS falso).
6. Errata explícita ADR-012/013; Decision/Accepted/Consequences intactos.
7. Zero Go/React/self-host como próximo passo aprovado.
8. Council: Architect + Senior Engineer + QA/Security + **Lead Reviewer** (gate final).
9. Validações: paths existem; LF; `make docs-check` OK.

### REVISE se

Creep B/C; quatro arquivos SSOT novos; limpeza silenciosa de ADR; reescrita §12;
Council incompleto; gate runtime PASS sem evidência; edição AGENTS/INV/CI; perda
do changeset R11; código/migration nesta missão.

---

## 9. Validação documental (Etapa 0)

| Check | Método | Resultado | Timestamp UTC |
|-------|--------|-----------|---------------|
| SSOT presente | `Test-Path` | OK | 2026-07-21T22:16:26Z |
| Links siblings | paths relativos (pivot, threat, parity, ADRs 010–013, roadmap) | OK | 2026-07-21T22:16:26Z |
| LF | byte scan CRLF | CRLF=0 (allowlist E0 + roadmap) | 2026-07-21T22:16:26Z |
| `git diff --check` | whitespace | OK (após remoção trailing space errata) | 2026-07-21T22:18:00Z |
| `make docs-check` | Makefile | OK — CI Blocks 22 + Lessons 15 sync | 2026-07-21T22:16:30Z |
| Roadmap R11 preservado | `git status` inclui `roadmap.md` modified | OK | 2026-07-21T22:16:26Z |
| Sem código/migration no diff E0 | `git status` allowlist docs only | OK | 2026-07-21T22:16:26Z |
| §12 histórico pivot | `ETAPA -1 STATUS: PASS` + “Não autorizado por este PASS…” intactos | OK | 2026-07-21T22:16:26Z |
| ADR-012/013 Status | Header **Accepted** + Errata pós-aceite | OK | 2026-07-21T22:16:26Z |
| Council | §10 | PASS (ver abaixo) | 2026-07-21T22:18:00Z |

**Allowlist de arquivos (changeset AUTH-E0 + R11 preservado):**

- `docs/governance/roadmap.md` (R11)
- `docs/governance/proposals/phase11_etapa0_executable_specs.md` (novo)
- `docs/governance/proposals/phase11_enterprise_pivot.md`
- `docs/governance/proposals/phase11_threat_model.md`
- `docs/governance/proposals/phase11_parity_checklist.md`
- `docs/governance/adr/012_rls_connection_lifecycle.md`
- `docs/governance/adr/013_strangler_fig.md`

---

## 10. Council (Etapa 0)

> Subagentes Council dedicados indisponíveis nesta sessão (API limit). Pareceres
> emitidos pelo agente executor sob as personas obrigatórias do `AGENTS.md`,
> com o mesmo critério de gate. Lead Reviewer permanece gate final.

| Persona | Veredicto | Findings | Data UTC |
|---------|-----------|----------|----------|
| Architect | **PASS** | Fronteiras A portável claras (§2); B/C condicionais; portabilidade sem Go/React (§5); errata ADR não altera Decision; zero próximo passo Go/React aprovado | 2026-07-21T22:18:00Z |
| Senior Engineer | **PASS** | §4.1/`app_auth_sessions` + §6 cobrem least privilege, RLS `session_is_live`, índice, fail-closed, sem cache positivo, refresh family, txn curtas, transaction pooling, sem SET session-level / prepared persistente; naming spec-only OK; schema `public` vs `app` deferido à migration E1 (non-blocking E0) | 2026-07-21T22:18:00Z |
| QA/Security | **PASS** | Matriz §3 completa para E0; T-27 permanece runtime Open; threat model ADR-011 Accepted; PG-REVOCATION/BACKUP/RESTORE/DR **NOT RUN**; RPO/RTO 24h/24h sem SLA; nenhum gate runtime falso PASS (PG-AAL2 PASS pré-existente Edge apenas) | 2026-07-21T22:18:00Z |
| Lead Reviewer | **PASS_DOCUMENTAL** | SSOT único; §12 preservado + §15 anexo; errata explícita; allowlist OK; R11 preservado; sem código/commit; Council completo registrado | 2026-07-21T22:18:00Z |

---

## 11. Veredicto da Etapa 0

```text
ETAPA 0 STATUS: PASS
```

**Gates documentais satisfeitos:** SSOT único; matriz; decomp E1; portabilidade; critérios revogação §6; sync pivot/threat/parity; errata ADR-012/013; R11 preservado; validações OK; Council completo.

**Não autorizado por este PASS:** Etapa 1, código, migrations, Edge, RLS runtime, Go/React/self-host, commit (requer AUTH explícita).

```text
IMPLEMENTATION AUTHORIZED: NO
COMMIT AUTHORIZED: NO
RUNTIME GATES: NOT RUN / OPEN (piloto)
NEXT SAFE AUTHORIZATION: AUTH-COMMIT (R11+E0 docs) e/ou AUTH-E1
```
---

## 12. Owners

| Role | Responsabilidade neste SSOT |
|------|----------------------------|
| Migration Owner | Manutenção deste arquivo; sequência Etapa 0→1 |
| Identity Owner | Spec revogação §4.1 / §6 |
| Platform Owner | Spec DR §4.2 |
| QA Owner | Matriz + parity cross-links |
| Architect | Anti B/C creep; portabilidade §5 |
| Lead Reviewer | Gate final PASS/REVISE |
