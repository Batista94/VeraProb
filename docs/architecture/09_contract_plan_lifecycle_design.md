# Phase 5 — Contract & Plan Lifecycle Management
## Design Specification

**Status:** `APROVADO — PRONTO PARA IMPLEMENTAÇÃO`
**Autor:** Engineering Council (Claude Code)
**Data:** 2026-03-09
**Fase:** 5 de 8

---

## 1. Contexto e Motivação

### O que existe hoje

O motor de avaliação (Phases 0–4) funciona de ponta a ponta:
`Telemetria → Engine → Ledger → Snapshots Financeiros`

Mas o motor avalia `contractId` como **string arbitrária** — não existe uma entidade `Contract`
no domínio. Qualquer operador pode passar qualquer string como `contractId` ao declarar um plano.
Não há lifecycle, não há validação de existência, não há status.

Consequência prática: hoje, criar um contrato ou declarar um plano só é possível via
inserção direta no banco ou por código. **Nenhum operador consegue usar o produto sozinho.**

### O que Phase 5 entrega

1. **`Contract` aggregate** — entidade de domínio com lifecycle e state machine
2. **UI completa** — telas para criar contratos e declarar planos com SETs configuráveis
3. **Integridade referencial** — `PlanDeclaration` passa a referenciar um `Contract` real
4. **Base para Phase 6** — sem `Contract` entity, não há o que administrar na fase de self-service

---

## 2. Modelo de Domínio

### 2.1 Entidade `Contract` (nova — Aggregate Root)

```
Contract
├── id: String (UUID v4, gerado internamente)
├── organizationId: String (derivado do JWT — nunca de input)
├── name: String (nome interno do contrato, ex: "Rota SP–Campinas 2026")
├── contractorName: String (nome da empresa contratante)
├── description: String? (opcional)
├── validFromUtc: DateTime (vigência início — informado pelo operador na criação)
├── validUntilUtc: DateTime (vigência fim — informado pelo operador na criação)
├── status: ContractStatus (state machine — ver 2.2)
├── createdAtUtc: DateTime
├── activatedAtUtc: DateTime? (preenchido quando primeiro plano é declarado)
└── closedAtUtc: DateTime?
```

> **Nota CR-2:** `renewedFromContractId` removido do escopo de Phase 5.
> Renovação de contrato adiada para Phase 6 junto com RBAC completo.

**O que Contract NÃO guarda:**
- Valor financeiro total — derivado da soma dos SETs do plano ativo
- Lista de planos — consultada via repositório (evita aggregate gigante)
- Regras SLA — vivem em `ContractualRule` / `RuleSnapshot`, já existentes

### 2.2 State Machine de `ContractStatus`

```
      create()
         │
         ▼
      [draft] ──── declarePlan() ────► [active]
                                          │
                                       close()
                                    (Phase 6: só Admin)
                                          │
                                          ▼
                                       [closed]
```

| Transição | Trigger | Quem pode |
|-----------|---------|-----------|
| `draft → active` | Primeiro `PlanDeclaration` publicado | Automático (handler) |
| `active → closed` | `CloseContractCommand` | **Admin/Gerente — UI exposta na Phase 6 com RBAC** |
| `closed → *` | **Proibido** — estado terminal | N/A |

> **Nota CR-1:** O domínio e o handler de `CloseContractCommand` são implementados em Phase 5,
> mas o botão de encerrar **não aparece na UI** até Phase 6, quando o RBAC estará disponível
> para protegê-lo corretamente. Implementar o botão agora sem proteção de role seria falsa segurança.
>
> **Nota CR-2:** `renewed` removido do estado machine. Renovação adiada para Phase 6.

**`draft` pode receber planos?** Não. Um plano só pode ser declarado para contrato `draft`.
A transição `draft → active` é automática e atômica ao primeiro plano publicado.

**Por que `draft` existe?** Para permitir que o operador crie o contrato e configure
metadados antes de comprometer o primeiro plano. Sem `draft`, o operador teria que criar
contrato e plano num único formulário gigante, ou o contrato só existiria após o plano.

### 2.3 Invariantes do `Contract`

- `name` não pode ser vazio
- `contractorName` não pode ser vazio
- `organizationId` nunca pode ser alterado após criação
- `validFromUtc` deve ser anterior a `validUntilUtc`
- Contrato `closed` **não aceita novos planos** (DomainException)
- Encerrar contrato com SETs `pending` e `windowEndUtc` no futuro:
  **permitido, com confirmação explícita na UI** (CR-3 aprovado)
  — o engine continua avaliando esses SETs normalmente até suas janelas expirarem

### 2.4 Relacionamento com `PlanDeclaration` (existente)

Hoje: `PlanDeclaration.contractId: String` — sem FK real no domínio.

Após Phase 5:
- `PlanDeclaration` continua com `contractId: String` (não muda o aggregate)
- O **handler** (`DeclareContractualPlanHandler`) passa a validar que o `Contract` existe
  e está em estado `draft` ou `active` antes de prosseguir
- A validação de estado é responsabilidade do **domínio do `Contract`**, não do handler

```dart
// No handler — ANTES de criar o PlanDeclaration:
final contract = await _contractRepository.findById(command.contractId, organizationId: command.organizationId);
if (contract == null) throw DomainException('Contract not found');
contract.assertCanReceivePlan(); // lança DomainException se não puder
```

### 2.5 `originalFileHash` em planos criados pela UI

Atualmente, `PlanDeclaration` tem `originalFileHash: String` — pensado para importação de arquivo.

Em planos criados via formulário da UI, não há arquivo. Solução:
**Gerar hash SHA-256 do payload serializado do plano** (mesma lógica do SET determinístico).
Isso mantém a propriedade de auditabilidade sem exigir upload de arquivo.

O campo `originalFileHash` permanece obrigatório, mas seu cálculo muda conforme a origem:

| Origem | Como gerar `originalFileHash` |
|--------|-------------------------------|
| Upload de arquivo | SHA-256 do arquivo bruto |
| Formulário da UI | SHA-256 do JSON serializado do `DeclareContractualPlanCommand` |

---

## 3. Camada de Aplicação

### 3.1 Novos Commands

```dart
// Criar contrato (novo)
CreateContractCommand {
  organizationId: String   // do JWT — nunca do formulário
  name: String
  contractorName: String
  description: String?
  validFromUtc: DateTime
  validUntilUtc: DateTime
}

// Encerrar contrato (novo — domínio implementado em Phase 5, UI exposta em Phase 6)
CloseContractCommand {
  organizationId: String
  contractId: String
  closedByUserId: String
  reason: String
}
```

> `RenewContractCommand` removido do escopo de Phase 5 (CR-2).

`DeclareContractualPlanCommand` **não muda** — já existe e está correto.

### 3.2 Novos Handlers

- `CreateContractHandler` — cria `Contract` em `draft`, persiste, appenda evento ao ledger
- `CloseContractHandler` — valida estado, transiciona para `closed`, persiste, appenda evento

`DeclareContractualPlanHandler` — **modificado** para:
1. Buscar o `Contract` por `contractId + organizationId`
2. Chamar `contract.assertCanReceivePlan()`
3. Se primeira declaração, chamar `contract.activate()` e persistir
4. Continuar o fluxo existente (criar PlanDeclaration, appenda ledger)

### 3.3 Novos Domain Events

```dart
ContractCreatedEvent    { contractId, organizationId, name, contractorName, validFromUtc, validUntilUtc }
ContractActivatedEvent  { contractId, organizationId, activatedAtUtc }
ContractClosedEvent     { contractId, organizationId, closedAtUtc, reason, closedByUserId }
```

Todos appendados ao `sla_audit_ledger` — mesma infraestrutura existente.

### 3.4 Query Service (read model)

Nova interface `ContractQueryService`:

```dart
Future<List<ContractSummaryView>> listContracts({
  required String organizationId,
  ContractStatus? status,         // filtro opcional
});

Future<ContractDetailView?> getContractDetail({
  required String organizationId,
  required String contractId,
});
```

`ContractSummaryView` — campos para listagem:
```
id, name, contractorName, status, createdAtUtc,
activatedAtUtc, planCount, activePlanVersion,
slaHealthPercentage (derived), totalSetsInProgress
```

`ContractDetailView` — campos para tela de detalhe:
```
ContractSummaryView +
recentExecutions: List<SlaExecutionItemView>
financialSummary: SlaExecutionSummary
```

---

## 4. Infraestrutura

### 4.1 Nova tabela: `contracts`

```sql
CREATE TABLE public.contracts (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     UUID NOT NULL REFERENCES organizations(id),
  name                TEXT NOT NULL,
  contractor_name     TEXT NOT NULL,
  description         TEXT,
  valid_from_utc      TIMESTAMPTZ NOT NULL,
  valid_until_utc     TIMESTAMPTZ NOT NULL,
  status              TEXT NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft','active','closed')),
  created_at_utc      TIMESTAMPTZ NOT NULL DEFAULT now(),
  activated_at_utc    TIMESTAMPTZ,
  closed_at_utc       TIMESTAMPTZ,
  closed_by_user_id   TEXT,
  close_reason        TEXT,
  CONSTRAINT valid_period CHECK (valid_until_utc > valid_from_utc)
);

-- Índices para queries frequentes
CREATE INDEX idx_contracts_org_status ON public.contracts (organization_id, status);
CREATE INDEX idx_contracts_org_created ON public.contracts (organization_id, created_at_utc DESC);

-- RLS: operador só vê contratos da própria org
ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Contract tenant isolation"
ON public.contracts FOR ALL TO authenticated
USING (organization_id = (auth.jwt() ->> 'organization_id')::UUID)
WITH CHECK (organization_id = (auth.jwt() ->> 'organization_id')::UUID);
```

### 4.2 FK em `plan_declarations`

Adicionar FK para garantir integridade referencial no banco:

```sql
ALTER TABLE public.plan_declarations
  ADD COLUMN contract_fk UUID REFERENCES public.contracts(id);
```

> **Nota CR-4:** O banco de dev será **resetado** antes de aplicar as migrations de Phase 5.
> Todos os dados existentes são fictícios e serão recriados manualmente ou via seed script.
> A migration não precisa incluir backfill de dados legados.

### 4.3 Novo repositório: `ContractRepository`

Interface no domínio:

```dart
abstract class ContractRepository {
  Future<void> save(Contract contract);
  Future<Contract?> findById(String id, {required String organizationId});
  Future<List<Contract>> findByOrganization(String organizationId, {ContractStatus? status});
}
```

Implementações: `InMemoryContractRepository` + `PostgresContractRepository`

---

## 5. Apresentação (UI)

### 5.1 Tela: Listagem de Contratos

**Rota:** `/contracts`
**Componente:** `ContractsScreen`

Layout: tabela com colunas:
- Nome do contrato
- Contratante
- Vigência (ex: "01/03/2026 – 31/03/2026")
- Status (chip colorido: draft=cinza, active=verde, closed=vermelho)
- Versão do plano atual
- SETs em andamento / total
- SLA Health % (barra de progresso)
- Ações: **Detalhes** (sempre) · ~~Encerrar~~ (Phase 6 — requer RBAC)

Filtros: status, vigência (intervalo de datas), busca por nome/contratante.

Botão primário: **"Novo Contrato"** → abre formulário (5.2).

### 5.2 Formulário: Criar Contrato

Campos:
- Nome do contrato (obrigatório, max 100 chars)
- Nome do contratante (obrigatório)
- Descrição (opcional, textarea)
- Vigência — início (date picker, obrigatório)
- Vigência — fim (date picker, obrigatório, deve ser após início)

Validação inline: se `validUntilUtc ≤ validFromUtc`, bloquear submissão com mensagem.

Submissão → `CreateContractCommand` → `CreateContractHandler`
Após sucesso: redireciona para detalhe do contrato criado.

### 5.3 Formulário: Declarar Plano

**Acesso:** botão "Declarar Plano" na tela de detalhe do contrato (status `draft` ou `active`).

**Estrutura do formulário:**

**Seção 1 — Metadados do plano**
- Versão (auto-calculada: plano anterior + 1, somente leitura)
- Responsável (pré-preenchido com usuário autenticado)

**Seção 2 — SETs (Service Execution Tokens)**
- Lista dinâmica de SETs — botão "Adicionar SET"
- Cada SET tem campos:
  - Início programado (date+time picker, UTC)
  - Fim programado (date+time picker, UTC)
  - Geofence de partida (lat, lng, raio em metros)
  - Geofence de chegada (lat, lng, raio em metros)
  - Veículo planejado (opcional — dropdown de veículos cadastrados)
  - Valor contratual (R$ — double, convertido para Money no handler)
  - Multiplicador de No-Show (default 1.5)

**Seção 3 — Confirmação**
- Resumo: X SETs · valor total R$ Y · período Z
- Aviso em destaque: **"Plano publicado não pode ser editado. Uma nova versão deverá ser declarada."**
- Botão: "Publicar Plano"

Submissão → serializa → calcula `originalFileHash` (SHA-256 do JSON) → `DeclareContractualPlanCommand`

### 5.4 Tela: Detalhe do Contrato

- Header: nome, contratante, vigência, status, datas de criação/ativação
- Aba "Execuções": tabela de SETs com status, veículo, timestamps
- Aba "Histórico de Planos": versões declaradas, imutáveis, com link para ledger entry
- Aba "Financeiro": `SlaExecutionSummary` — protectedRevenue, revenueAtRisk, lostRevenue
- Ação "Encerrar Contrato": **não exposta em Phase 5** — disponível em Phase 6 com RBAC

---

## 6. Integração com Pipeline Existente

O pipeline de avaliação **não muda**. O `ContractualEvaluationEngine` já opera sobre
`ContractualExecutionState` usando `contractId: String`. Essa string agora referencia
um `Contract` real, mas o engine não precisa saber disso.

Fluxo completo após Phase 5:

```
Operador cria Contract (draft)
  └─ Operador declara PlanDeclaration via formulário
       └─ Handler valida Contract.assertCanReceivePlan()
            └─ Handler cria ContractualExecutionStates para cada SET
                 └─ Engine processa telemetria → transiciona estados
                      └─ Snapshots financeiros gerados (Phase 4/7)
```

Nenhum componente das Phases 0–4 precisa ser modificado.

---

## 7. Council Review

> Conduzido pelo Engineering Council em múltiplas personas.
> Perguntas técnicas: respondidas aqui.
> Perguntas de produto: **marcadas como ❓ — aguardando decisão do proprietário.**

---

### Persona: Architect

**A-1. Por que `Contract` é um Aggregate Root separado de `PlanDeclaration`?**

*Resposta:* Porque têm ciclos de vida independentes e razões de mudança diferentes.
`Contract` muda de status (draft/active/closed) independentemente de qualquer plano.
`PlanDeclaration` é imutável após criação. Agrupá-los no mesmo aggregate violaria
o princípio de responsabilidade única e criaria um aggregate excessivamente grande.

**A-2. `PlanDeclaration.contractId` continua como String — isso não quebra a integridade?**

*Resposta:* No domínio Dart, sim — `contractId` continua sendo `String`.
A integridade é garantida em duas camadas:
1. **Application layer:** handler valida existência do `Contract` antes de criar o plano
2. **Infrastructure layer:** FK `plan_declarations.contract_fk → contracts.id` no Postgres

Não mudamos o aggregate `PlanDeclaration` para receber um `Contract` object porque
isso criaria acoplamento de agregados — violação de DDD. Aggregates se referenciam por ID.

**A-3. Faz sentido ter `Contract` sem saber se `PlanDeclaration` tem FK nova ou campo existente?**

*Resposta:* A tabela `plan_declarations` hoje tem `contract_id TEXT`. A migration de Phase 5
adiciona `contract_fk UUID` como nova coluna com FK real. O campo `contract_id TEXT` é mantido
para compatibilidade com o modelo de domínio existente. Futuramente (Phase 8), pode ser
consolidado. Isso é técnica deliberada de migração incremental sem big bang.

**A-4. Por que `Contract` não guarda o `totalContractualValue`?**

*Resposta:* Porque o valor total é derivado dos SETs do plano ativo, que muda a cada
nova versão declarada. Guardar no `Contract` criaria campo derivado que precisaria ser
recalculado — violação de Single Source of Truth. O valor é sempre computado via
`SlaExecutionSummary` dos estados de execução ativos.

---

### Persona: Senior Engineer

**SE-1. O `DeclareContractualPlanHandler` vai buscar `Contract` do repositório — isso não viola o princípio de que handlers são finos?**

*Resposta:* Não. A busca pelo `Contract` para validar estado é lógica de **guarda de pré-condição**,
responsabilidade legítima do handler. O que um handler não deve fazer é lógica de domínio — e aqui
a lógica (`assertCanReceivePlan`) vive no aggregate `Contract`, não no handler.

**SE-2. A transição `draft → active` é automática via handler — e se o plano falhar após a transição?**

*Resposta:* O handler deve ser **transacional**: ou ambas as operações (ativar contrato + salvar plano)
persistem, ou nenhuma. No MVP, sem transação explícita no Supabase, a ordem é:
1. Salvar `PlanDeclaration`
2. Ativar e salvar `Contract`

Se o passo 2 falhar, o plano existe mas o contrato permanece `draft` — o handler pode ser
re-executado (idempotência via `planVersion`). Isso é aceitável para MVP.
Phase 8 endereça com RPC atômica no Postgres.

**SE-3. O hash SHA-256 do JSON do formulário como `originalFileHash` é determinístico?**

*Resposta:* Sim, **desde que a serialização do JSON seja determinística** (chaves em ordem
alfabética fixa). Isso precisa ser garantido na implementação — usar `jsonEncode` com
keys ordenadas ou um serializer customizado. Documentar como decisão técnica.

**SE-4. Como o `planVersion` é calculado para formulário UI — sem arquivo, sem versão manual?**

*Resposta:* O handler consulta `PlanDeclarationRepository.findByContract()`, pega a versão
mais alta, e incrementa +1. Se não há planos anteriores, versão = 1. Isso é determinístico
e não depende de input do usuário.

**SE-5. `ContractSummaryView.slaHealthPercentage` — como é calculado?**

*Resposta:* `(executedCount / totalSets) * 100`, onde `totalSets = executed + noShow + evidenceGap + pending`.
Calculado no `ContractQueryService`, não no domínio. É uma projeção de display, não lógica de negócio.

---

### Persona: QA / Security

**QS-1. `organization_id` vem do JWT — e se a UI enviar um `organizationId` diferente no body?**

*Resposta:* O handler extrai `organizationId` exclusivamente do provider autenticado (`currentOrganizationIdProvider`),
que lê do JWT via Supabase Auth. O campo `organizationId` **não existe** nos commands de input
do formulário — é injetado pela camada de aplicação. Mesmo que o body da requisição fosse adulterado,
o handler usaria o JWT. RLS no Postgres é a segunda linha de defesa.

**QS-2. O formulário de SETs tem campos de latitude/longitude livres — há risco de injeção?**

*Resposta:* Não. Latitudes e longitudes são validadas como `double` no domínio
(`_validateLatitude`: -90 a 90, `_validateLongitude`: -180 a 180). Valores inválidos
lançam `DomainException` antes de qualquer acesso ao banco. Campos de texto (`name`,
`contractorName`) são armazenados como TEXT parametrizado via Supabase SDK — sem SQL dinâmico.

**QS-3. Um operador pode fechar o contrato de outro operador da mesma org?**

*Resposta:* O isolamento é por `organization_id`, não por usuário individual. Dentro da mesma org,
qualquer usuário autenticado pode encerrar qualquer contrato da org. Phase 6 (RBAC) restringirá
isso por role — apenas `Admin` poderá encerrar contratos. Documentado como débito conhecido.

**QS-4. O que acontece com `ContractualExecutionState` (SETs pendentes) quando o contrato é encerrado?**

*Resposta:* Esta é uma decisão de domínio crítica. Proposta técnica: SETs com status `pending`
cujo `windowEndUtc` já passou são marcados como `evidenceGap` ou `noShow` automaticamente pelo engine
durante o próximo ciclo de avaliação — independente do status do contrato. O encerramento do contrato
**não muda retroativamente** estados de execução. O ledger é imutável.

**❓ QS-5 — DECISÃO DE PRODUTO (CR-3):** Deve ser permitido encerrar um contrato que ainda tem SETs
com `windowEndUtc` no futuro (ou seja, execuções ainda ativas)? Ou o domínio deve bloquear isso?

---

### Persona: UX / Ops

**UX-1. O formulário de SETs pode ter muitos itens — como evitar que seja inutilizável?**

*Resposta:* Limitar a 50 SETs por declaração de plano (validado no handler via `DomainException`
ou validação da aplicação). Para volumes maiores, Phase 8 endereça com upload de CSV/Excel.
O formulário deve mostrar contador de SETs e alertar ao se aproximar do limite.

**UX-2. O operador precisa saber o que é um SET? O termo é muito técnico.**

*Resposta:* Na UI, "SET" nunca aparece para o usuário. O label na tela é **"Viagem Programada"**
(ou "Execução Programada"). A sigla SET é interna ao domínio técnico.

**UX-3. Como o operador sabe que o plano foi publicado com sucesso e está alimentando o engine?**

*Resposta:* Após submissão bem-sucedida do plano, a tela de detalhe do contrato exibe:
- Status do contrato muda para `active` (se era `draft`)
- A aba "Execuções" exibe imediatamente os SETs com status `pending`
- Toast de confirmação: "Plano v{N} publicado com sucesso — {X} execuções aguardando telemetria"

---

## 8. Decisões de Produto Registradas

> Council Review concluído. Todas as decisões incorporadas ao spec.
> Documento aprovado para implementação.

| # | Questão | Decisão | Impacto no spec |
|---|---------|---------|-----------------|
| CR-1 | Quem encerra contrato? | Só Admin/Gerente | `CloseContractCommand` implementado em Phase 5; **botão de UI adiado para Phase 6** com RBAC |
| CR-2 | Renovação de contrato? | **Adiado para Phase 6** | Estado `renewed` e `RenewContractCommand` removidos do escopo |
| CR-3 | Encerrar com SETs ativos? | **Permitir com aviso e confirmação** | UI exibe modal: "X execuções em aberto. Deseja continuar?" |
| CR-4 | Dados de dev a preservar? | **Reset total do banco de dev** | Migration não precisa de backfill; banco resetado antes de aplicar |
| CR-5 | Datas de vigência explícitas? | **Sim — campos obrigatórios** | `validFromUtc` + `validUntilUtc` no `Contract`, no formulário e na listagem |

---

## 9. Ordem de Implementação (Phase 5.3)

> Spec aprovado. Sequência obrigatória — cada camada depende da anterior.

```
[1] DOMÍNIO
    ├── Contract aggregate (campos, state machine, invariantes, validFromUtc/validUntilUtc)
    ├── ContractStatus enum (draft, active, closed)
    ├── ContractRepository interface
    └── Domain events: ContractCreatedEvent, ContractActivatedEvent, ContractClosedEvent

[2] APLICAÇÃO
    ├── CreateContractCommand + CreateContractHandler
    ├── CloseContractCommand + CloseContractHandler
    ├── DeclareContractualPlanHandler — modificado (valida Contract antes de criar plano)
    └── ContractQueryService interface + ContractSummaryView + ContractDetailView

[3] INFRAESTRUTURA
    ├── Migration SQL: tabela contracts + FK em plan_declarations + reset de dev
    ├── InMemoryContractRepository
    ├── PostgresContractRepository
    └── ContractQueryServiceInMemory + ContractQueryServicePostgres

[4] APRESENTAÇÃO
    ├── ContractsScreen (listagem com filtros por status e vigência)
    ├── CreateContractForm (com validFromUtc / validUntilUtc)
    ├── DeclareContractPlanForm (SETs configuráveis)
    └── ContractDetailScreen (abas: execuções, planos, financeiro)

[5] TESTES
    ├── Domain unit: Contract state machine + invariantes
    ├── Application: handlers + query service
    ├── Integration: pipeline completo create → declare → engine
    └── Compliance: phase5_compliance_test.dart

[6] VALIDAÇÃO (Phase 5.4)
    ├── Cenários automatizados (5.4)
    ├── Testes manuais com Supabase real (conforme roadmap)
    └── Compliance Report: docs/governance/compliance/phase5_compliance_report.md
```
