# 12 — Systemic User Journeys & Hard Gate Architecture

**Status:** Ratified by Council (2026-03-17)
**Council:** @architect · @qa_security · @business_maverick
**Implementation Ref:** Phase 8.8 — Systemic UX, Hard Gates & Dual-Key RLS
**Invariants Introduced:** INV-18 · INV-19 · INV-20

---

## 1. Filosofia Sistêmica

> **O sistema impõe o fluxo — não a UI.**

Esconder um botão no Flutter é cosmético. Bloquear na camada de domínio é arquitetural. PactaFlow adota uma política de **defesa em profundidade** com três camadas de enforcement obrigatórias para qualquer hard gate:

| Camada | Mecanismo | Responsável |
|--------|-----------|-------------|
| **Domain** | `DomainException` lançada em factory/guard method | `lib/domain/` |
| **Application** | RBAC check + pre-condition guard no handler | `lib/application/` |
| **Infrastructure** | RLS policy no PostgreSQL via JWT claim | `supabase/migrations/` |

**Regra de Ouro:** Se um pré-requisito existe no domínio, ele DEVE ser enforcado no handler correspondente via `DomainException`. A UI reflete a realidade do domínio — nunca a precede.

---

## 2. Máquina de Estados de Onboarding (Engine Activation Prerequisites)

Antes que o `EvaluationEngine` possa ser ativado para um contrato, o seguinte **grafo de pré-requisitos** deve estar satisfeito. Cada nó representa um bloqueador sistêmico:

```
Organização Configurada (name, timezone, currency)
      │
      ▼
Zonas Operacionais ≥ 1
(OperationalZone para a org)          ← GATE: DeclareContractualPlanHandler
      │
      ├──────────────────────────────┐
      ▼                              ▼
Contractor ≥ 1                    Assets ≥ 1 (Veículos Ativos)
(para atribuição ao contrato)      (para planos shift-based)
      │                              │
      └──────────────┬───────────────┘
                     ▼
            SLA Template Ativo
            (Rule Snapshot capturado)   ← GATE: DeclareContractualPlanHandler (já implementado)
                     │
                     ▼
             CONTRATO PODE RECEBER PLANO
                     │
                     ▼
             ENGINE ATIVADO ✅
```

### Tabela de Pré-Requisitos por Operação

| Operação | Pré-Requisito | Onde Enforcar | Status |
|----------|---------------|---------------|--------|
| `CreateContractHandler` | org existe | ✅ `organizationId not empty` | Implementado |
| `DeclareContractualPlanHandler` (qualquer) | ≥ 1 OperationalZone | `lib/application/sla_audit/declare_contractual_plan_handler.dart` | **GAP — Phase 8.8** |
| `DeclareContractualPlanHandler` (shift-based) | ≥ 1 Vehicle ativo | `lib/application/sla_audit/declare_contractual_plan_handler.dart` | **GAP — Phase 8.8** |
| `DeclareContractualPlanHandler` (qualquer) | Rule Snapshot ativo | ✅ linha 92-95 do handler | Implementado |
| `SubmitContractForApprovalHandler` | RBAC `canApproveContractAcceptance` | ✅ linhas 52-59 | Implementado |
| `CloseContractHandler` | RBAC `canCloseContracts` | ✅ linha 43 | Implementado |

---

## 3. Persona A — Tenant Admin (First Run)

**Objetivo:** Do login até a primeira avaliação de SLA ativa.

### Jornada Ideal

```
[1] LOGIN
    URL: / (AdminLockScreen)
    Ação: email + senha → Supabase Auth
    Resultado: JWT injetado com org_id + role via custom_access_token_hook
    Gate: JWT sem org_id → tela de erro "Organização não encontrada. Contate o suporte."
         │
         ▼
[2] ORG SETUP (OrgSettingsScreen)
    Campos: Nome da Organização · Fuso Horário · Moeda
    Gate: org.name não pode ser vazio (UpdateOrgSettingsHandler)
    UX: Banner de onboarding aparece no AdminShell enquanto pré-requisitos faltam
         │
         ▼
[3] ZONAS OPERACIONAIS (OperationalZonesScreen)
    Ação: Criar ≥ 1 zona (garagem, cliente, apoio) com geofence válida
    Gate Domain: OperationalZone.create() valida lat/lng/radius
    UX: Banner de onboarding marca "Zonas ✓" ao detectar primeira zona criada
         │
         ▼
[4] CONTRACTORS (ContractorManagementScreen)
    Ação: Cadastrar ≥ 1 contractor com name + taxId + primaryEmail + contactName
    UX: Banner marca "Contractors ✓"
         │
         ▼
[5] ASSETS / VEÍCULOS (ResourceManagementScreen → VehiclesTab)
    Ação: Registrar ≥ 1 veículo com plate + model + status=active
    UX: Banner marca "Veículos ✓"
         │
         ▼
[6] TEMPLATE SLA (RuleStudio — somente admin)
    Ação: Criar regras SLA (penalidades, tolerâncias) para o contrato
    RBAC Gate: somente users com canEditSlaRules (admin role)
    UX: Banner marca "SLA Template ✓"
         │
         ▼
[7] CRIAR CONTRATO (ContractsScreen)
    Ação: "Novo Contrato" → CreateContractForm
    UX: Todos os pré-requisitos satisfeitos → banner desaparece
    Gate Domain: Contract.create() valida name, contractorName, datas
         │
         ▼
[8] DECLARAR PLANO (ContractDetailScreen → "Declarar Plano")
    Gate Handler (INV-18): operationalZones.count > 0 para a org
    Gate Handler (INV-18): se shift-based → vehicles.countActive > 0
    Gate Domain: contract.assertCanReceivePlan()
    Gate Handler: ruleSnapshot existe para o contrato
    Resultado: Plano declarado → contrato transita draft → active
         │
         ▼
[9] ENGINE ATIVO ✅
    TelemetryIngestionPipeline processa facts
    EvaluationEngine avalia SETs
    Ledger recebe vereditos imutáveis
```

### OnboardingProgressBanner — Especificação UX

**Localização:** `lib/presentation/shell/admin_shell.dart` (above main content area)
**Visibilidade:** Somente quando ≥ 1 pré-requisito não satisfeito
**Itens clicáveis:** Navegam para a tela correspondente sem perder contexto

```
┌─────────────────────────────────────────────────────────────────┐
│  ⚙ Configure sua organização para ativar o motor de avaliação   │
│                                                                  │
│  [✓] Zonas Operacionais  [✗] Contractors  [✗] Veículos  [✓] SLA │
└─────────────────────────────────────────────────────────────────┘
```

### Mensagens de Erro por Hard Gate

| Gate | DomainException | Mensagem na UI |
|------|----------------|----------------|
| Org sem nome | `'Organization name must not be empty'` | "Nome da organização é obrigatório" |
| Geofence inválida | `'latitude must be between -90 and 90'` | "Coordenadas da zona são inválidas" |
| Sem zonas ao declarar plano | `'No operational zones configured for this organization'` | "Cadastre pelo menos uma Zona Operacional antes de declarar um plano [→ Zonas]" |
| Sem veículos (shift-based) | `'No active vehicles found for this organization'` | "Registre pelo menos um veículo ativo para planos baseados em turno [→ Veículos]" |
| Rule Snapshot ausente | Repositório retorna null | "Nenhuma regra SLA ativa encontrada. Configure o Rule Studio primeiro." |

---

## 4. Persona B — Contract Manager (Operador / Admin)

**Objetivo:** Do contrato em rascunho até o motor avaliando execuções reais.

### Jornada Ideal

```
[1] CRIAR CONTRATO
    Rota: ContractsScreen → "Novo Contrato"
    Componente: CreateContractForm (dialog/sheet modal)
    ┌───────────────────────────────────────────────────────┐
    │ Nome do Contrato       [campo obrigatório]            │
    │ Contratante            [typeahead de Contractors]     │
    │   └─ Vazio?            [+ Criar Contractor] → Modal   │ ← INV-19
    │ Vigência De / Até      [DatePicker]                   │
    │ Teto Financeiro (R$)   [opcional]                     │
    └───────────────────────────────────────────────────────┘
    Gate Domain: Contract.create() — 4 invariantes
    Resultado: Contrato criado em status draft
         │
         ▼
[2] CONFIGURAR REGRAS SLA (ContractDetailScreen → RuleStudio)
    RBAC: somente admin (canEditSlaRules)
    Ação: Definir tolerâncias, penalidades, multiplicadores
    Resultado: Rule Version criada e linkada ao contrato
         │
         ▼
[3] DECLARAR PLANO (ContractDetailScreen → "Declarar Plano")
    Modo Manual:  serviços explícitos (lista de SETs)
    Modo Shift:   padrões de turno (ShiftPattern → ShiftProjectionService gera SETs)

    GATES em ordem de execução:
    ① Handler: services XOR shiftPatterns (não ambos)
    ② Handler: se shift-based → contractualValueCents > 0
    ③ Handler (INV-18): operationalZones.count > 0 para org
    ④ Handler (INV-18): se shift-based → vehicles.countActive > 0
    ⑤ Domain: contract.assertCanReceivePlan()
    ⑥ Handler: ruleSnapshot existe para o contrato

    Resultado: PlanDeclaration criado → contrato auto-ativa (draft → active)
         │
         ▼
[4] WORKFLOW DE APROVAÇÃO (opcional, somente admin)
    Ação: "Submeter para Aprovação do Contratante"
    RBAC Gate: canApproveContractAcceptance (somente admin)
    Domain Gate: contract.submitForApproval() — status deve ser draft
    Resultado: Token gerado → email enviado ao contractor → status: awaitingContractorAcceptance
         │
         ▼
[5] ACEITE DO CONTRACTOR (ReviewContractScreen — público)
    Token: posse do token = autorização
    Gate: token válido, não expirado, uso único (RPC server-side)
    Gate Domain: contract.acceptByContractor() — status deve ser awaitingContractorAcceptance
    Resultado: contrato → active · ledger entry imutável carimbado
```

### Criação On-The-Fly (INV-19 — Zero Dead Ends)

Quando o usuário está preenchendo um formulário e bate num pré-requisito faltante:

**Padrão de implementação:**
```
ContractorSelectorField (typeahead dentro de CreateContractForm)
  ├─ Lista vazia ou usuário digita um nome não encontrado
  ├─ Exibe: "+ Criar 'Nome Digitado' como Contractor"
  └─ Abre: SaveContractorModal (Dialog/BottomSheet overlay)
       ├─ Campos: name, taxId, primaryEmail, contactName
       ├─ Salva via SaveContractorHandler
       └─ Fecha o modal → injeta o novo contractor no campo do formulário pai
          SEM navegar para fora · SEM perder campos preenchidos

ZoneTypeAheadField (já existe — mesmo padrão para zonas em ShiftPattern)
```

**Regra (INV-19):** Qualquer criação de dependência a partir de um formulário pai DEVE ser implementada como overlay modal. Navegação que destrói o estado do formulário é falha de UX inaceitável.

### Tabela Completa de Domain Exceptions → Mensagens de UI

| DomainException | Handler | Mensagem para o Usuário |
|----------------|---------|-------------------------|
| `'name must not be empty'` | CreateContractHandler | "Nome do contrato é obrigatório" |
| `'contractorName must not be empty'` | CreateContractHandler | "Selecione ou crie um contratante" |
| `'validUntilUtc must be after validFromUtc'` | CreateContractHandler | "Data de término deve ser posterior à data de início" |
| `'organizationId must not be empty'` | CreateContractHandler | "Erro de sessão. Faça login novamente." |
| `'No operational zones configured for this organization'` | DeclareContractualPlanHandler | "Cadastre pelo menos uma Zona Operacional [→ ir para Zonas]" |
| `'No active vehicles found for this organization'` | DeclareContractualPlanHandler | "Registre pelo menos um veículo ativo [→ ir para Veículos]" |
| `'services and shiftPatterns are mutually exclusive'` | DeclareContractualPlanHandler | "Escolha entre plano manual ou por turno — não ambos" |
| `'contractualValueCents must be greater than 0 for shift-based plans'` | DeclareContractualPlanHandler | "Valor contratual deve ser maior que zero para planos por turno" |
| `'is closed and cannot receive new plans'` | DeclareContractualPlanHandler | "Contrato encerrado. Nenhum novo plano pode ser adicionado." |
| `'Cannot submit contract in status X'` | SubmitForApprovalHandler | "Contrato não está em rascunho — status atual: [X]" |
| `'Cannot accept contract in status X'` | AcceptByContractorHandler | "Token inválido ou contrato já processado." |
| `'closedByUserId must not be empty'` | CloseContractHandler | "Erro interno: identidade do usuário não encontrada." |
| RBAC denial | Qualquer handler | "Permissão insuficiente para esta ação." |

---

## 5. Persona C — Contractor / Cliente Final

**Objetivo:** Receber link → assinar contrato → acessar evidências auditadas.

### Modelo de Isolamento (INV-20 — CRÍTICO)

> ⚠️ **VULNERABILIDADE ARQUITETURAL IDENTIFICADA E MITIGADA**
>
> O modelo de RLS atual isola por `organization_id` (a org do Tenant). Se um contractor recebesse uma `user_roles` entry com role `admin` ou `operator`, ele teria acesso aos dados de **todos os outros contractors** da mesma viação. Isso é uma breach de dado crítica em ambiente multi-contractor.

**Solução — Role `CONTRACTOR_VIEWER` com JWT Dual-Key:**

O contractor NÃO pode ter role `admin`, `operator` ou `auditor`. Ele recebe exclusivamente a role `CONTRACTOR_VIEWER`, que carrega **dois claims obrigatórios no JWT**:

```
app_metadata.org_id        → UUID da organização do Tenant (para RLS base)
app_metadata.contractor_id → UUID do registro do contractor específico (para isolamento cross-contractor)
app_metadata.role          → 'CONTRACTOR_VIEWER'
```

**Implementação no `custom_access_token_hook`:**

```sql
-- Pseudocódigo do hook (implementação em Phase 8.8)
IF user_role = 'CONTRACTOR_VIEWER' THEN
  claims.app_metadata.org_id        := user_roles.organization_id;
  claims.app_metadata.contractor_id := user_roles.contractor_id;  -- coluna a ser adicionada
  claims.app_metadata.role          := 'CONTRACTOR_VIEWER';
ELSE
  -- Roles internas (admin, operator, auditor)
  claims.app_metadata.org_id        := user_roles.organization_id;
  claims.app_metadata.contractor_id := NULL;  -- explicitamente NULL — sem escopo de contractor
  claims.app_metadata.role          := user_roles.role;
END IF;
```

**RLS Dual-Keyed para tabelas do portal do contractor:**

```sql
-- audit_packages — política para CONTRACTOR_VIEWER
CREATE POLICY "audit_packages_contractor_viewer_isolation"
  ON public.audit_packages
  FOR SELECT
  TO authenticated
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND contractor_id = (auth.jwt() -> 'app_metadata' ->> 'contractor_id')::uuid
  );

-- Obs: a política para roles internas (admin/operator/auditor) usa apenas org_id:
CREATE POLICY "audit_packages_tenant_isolation"
  ON public.audit_packages
  FOR ALL
  TO authenticated
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'contractor_id') IS NULL
  );
```

**Migração SQL necessária (Phase 8.8):**
- Adicionar coluna `contractor_id UUID REFERENCES contractors(id)` na tabela `user_roles`
- Atualizar `custom_access_token_hook` para injetar o claim
- Adicionar políticas RLS dual-keyed para tabelas do portal do contractor

### Jornada Fase 1 — Assinatura de Contrato (Token Público)

```
[Email com link /review-contract?token=<uuid>]
      │
      ▼
ReviewContractScreen (público — sem autenticação necessária)
  Gate RPC: token válido + não expirado + não utilizado
  Gate Domain: status do contrato == awaitingContractorAcceptance APENAS
               → se draft ou active: "Token inválido ou contrato já processado."
               → se closed: "Contrato encerrado."

  Exibe:
  ┌──────────────────────────────────────────────────────┐
  │  Contrato: [Nome]                                    │
  │  Contratante: [Nome] · CNPJ: [XX.XXX.XXX/XXXX-XX]   │
  │  Vigência: [DD/MM/YYYY] → [DD/MM/YYYY]               │
  │  Valor Contratual: R$ XX.XXX,XX / mês               │
  │                                                      │
  │  Regras SLA (snapshot imutável):                     │
  │  • No-show: multa XX% após XX min                    │
  │  • Atraso: R$ X,XX/min após tolerância XX min        │
  │                                                      │
  │  [ACEITAR CONTRATO]  [RECUSAR]                       │
  └──────────────────────────────────────────────────────┘

  Ação "Aceitar":
    → AcceptByContractorHandler
    → contract.acceptByContractor() → status: active
    → ledger entry imutável carimbado
    → token marcado como utilizado (uso único garantido pelo RPC)
    → tela: "Contrato aceito com sucesso. Você receberá acesso ao portal de evidências."
```

### Jornada Fase 2 — Portal de Transparência (Auth com CONTRACTOR_VIEWER)

```
[Email de convite /accept-invite?token=<uuid>]
  (enviado pelo Tenant Admin via InviteUserHandler com role=CONTRACTOR_VIEWER + contractor_id)
      │
      ▼
AcceptInviteScreen
  → Criação de senha → sessão autenticada
  JWT contém: org_id + contractor_id + role=CONTRACTOR_VIEWER
      │
      ▼
ContractorPortalScreen (autenticado)
  Query: sealedAuditPackagesProvider
    WHERE organization_id = jwt.org_id
    AND   contractor_id   = jwt.contractor_id   ← isolamento cross-contractor
    AND   status          = 'sealed'             ← NUNCA exposição de draft

  Exibe:
  ┌──────────────────────────────────────────────────────┐
  │ Portal de Evidências — [Nome do Contractor]          │
  │                                                      │
  │ Período: Jan/2026                                    │
  │ Receita Protegida: R$ 150.000,00                     │
  │ Receita em Risco: R$ 12.340,00                       │
  │ Compliance: 91,8%                                    │
  │                                                      │
  │ Hash SHA-256: a3f8b2c9d1e4... (verificação ind.)     │
  │                                                      │
  │ [Exportar PDF]  [Exportar CSV]                       │
  └──────────────────────────────────────────────────────┘

  Garantias de Segurança:
  ✅ Nunca vê contratos de outros contractors da mesma viação (INV-20)
  ✅ Nunca vê status draft ou awaitingContractorAcceptance (sealed-only)
  ✅ Nunca acessa ledger bruto — apenas AuditPackage agregado
  ✅ Todo export inclui AttestationHeader + packageHash (INV-16, INV-17)
  ✅ Acesso de escrita: ZERO — leitura pura
```

---

## 6. Technical Debt Ativo

### JWT Path Inconsistency em `audit_packages` (BLOQUEIA Phase 8.8)

| Padrão Canônico (INV-10) | Padrão em `audit_packages` | Status |
|--------------------------|---------------------------|--------|
| `(auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid` | `(auth.jwt() ->> 'organization_id')::uuid` | ⚠️ INCONSISTENTE |

**Migração necessária:** A política RLS da tabela `audit_packages` usa o caminho simplificado. O `custom_access_token_hook` injeta sob `app_metadata.org_id`. Se o caminho simplificado não for populado pelo hook, a política falha silenciosamente (0 rows). Corrigir como primeiro passo da migração de Phase 8.8.

**Arquivo:** `supabase/migrations/20260401000001_audit_packages.sql`

---

## 7. Inventário de Invariantes Ratificados Neste Documento

### INV-18 — ENGINE ACTIVATION GATE
> `DeclareContractualPlanHandler` DEVE verificar que a organização possui ao menos uma `OperationalZone` antes de aceitar qualquer plano (manual ou shift-based). Para planos shift-based, ao menos um `Vehicle` com status `active` também deve existir. O engine não pode produzir avaliações espaciais sem contexto geográfico. Um contrato sem contexto espacial é input inválido para o engine.

**Onde implementar:** `lib/application/sla_audit/declare_contractual_plan_handler.dart`

### INV-19 — ON-THE-FLY CREATION MUST NOT LOSE DRAFT
> Qualquer fluxo de "criar dependência" disparado a partir de um formulário pai (criação de contractor a partir do formulário de contrato, criação de zona a partir do formulário de plano) DEVE ser implementado como overlay modal que preserva o estado do formulário pai. Navegação que destrói o estado do formulário em progresso é falha de UX inaceitável.

**Onde implementar:** `lib/features/admin/presentation/screens/create_contract_form.dart` (ContractorSelectorField)

### INV-20 — CONTRACTOR VIEWER DUAL-KEY ISOLATION
> Um usuário com role `CONTRACTOR_VIEWER` DEVE ter seu JWT enriquecido com AMBOS `org_id` E `contractor_id` pelo `custom_access_token_hook`. As políticas RLS em todas as tabelas visíveis pelo portal do contractor DEVEM enforcar predicado duplo: `organization_id = jwt.org_id AND contractor_id = jwt.contractor_id`. Um contractor com acesso ao org_id do Tenant mas sem escopo de `contractor_id` pode ver os pacotes selados de todos os outros contractors — isso constitui uma breach de dado crítica. O hook DEVE injetar `contractor_id = NULL` para todas as roles internas do Tenant (admin, operator, auditor) para tornar elevação acidental impossível.

**Onde implementar:** `supabase/migrations/[timestamp]_contractor_viewer_role.sql` + hook update

---

## 8. Arquivos Críticos de Referência

| Componente | Arquivo | Linhas Relevantes |
|------------|---------|-------------------|
| Contract aggregate + guards | [lib/domain/sla_audit/contract.dart](../../lib/domain/sla_audit/contract.dart) | 108-161 (create), 275-488 (guards) |
| DomainException | [lib/domain/sla_audit/domain_exception.dart](../../lib/domain/sla_audit/domain_exception.dart) | 1-12 |
| DeclareContractualPlanHandler | [lib/application/sla_audit/declare_contractual_plan_handler.dart](../../lib/application/sla_audit/declare_contractual_plan_handler.dart) | 62-89 (gates existentes) |
| CreateContractHandler | [lib/application/sla_audit/create_contract_handler.dart](../../lib/application/sla_audit/create_contract_handler.dart) | — |
| ContractStatus enum | [lib/domain/sla_audit/contract_status.dart](../../lib/domain/sla_audit/contract_status.dart) | 13-25 |
| UserRole + Permissions | [lib/domain/enums/user_role.dart](../../lib/domain/enums/user_role.dart) | 1-36 |
| RBAC Guard widget | [lib/presentation/shared/widgets/rbac_guard.dart](../../lib/presentation/shared/widgets/rbac_guard.dart) | 1-32 |
| Auth providers (JWT) | [lib/state/providers/auth_providers.dart](../../lib/state/providers/auth_providers.dart) | 40-52 (org_id), 53-65 (role) |
| AdminShell navigation | [lib/presentation/shell/admin_shell.dart](../../lib/presentation/shell/admin_shell.dart) | 192-204 (role filter) |
| CreateContractForm | [lib/features/admin/presentation/screens/create_contract_form.dart](../../lib/features/admin/presentation/screens/create_contract_form.dart) | 103-162 (validation) |
| ContractorPortalScreen | [lib/presentation/shell/contractor_portal_screen.dart](../../lib/presentation/shell/contractor_portal_screen.dart) | — |
| RLS JWT Unification | [supabase/migrations/20260317000001_rls_jwt_path_unification.sql](../../supabase/migrations/20260317000001_rls_jwt_path_unification.sql) | 12-36 (hook), 54-133 (RLS) |
| Audit Packages migration | [supabase/migrations/20260401000001_audit_packages.sql](../../supabase/migrations/20260401000001_audit_packages.sql) | 108-115 (⚠️ inconsistent RLS path) |
