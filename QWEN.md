# VeraProb — QWEN Context File (SSOT)

> **⚠️ DIRETIVA DE COMPORTAMENTO — LEIA ANTES DE QUALQUER TAREFA:**
>
> A partir de **11 de abril de 2026**, este arquivo é a **Fonte Única de Verdade (SSOT)** para o Qwen Code neste repositório. Toda governança, personas, invariantes e padrões técnicos foram consolidados aqui a partir do diretório `.claude/`.
>
> **Protocolo Obrigatório:**
>
> 1. **SEMPRE** consultar este arquivo antes de iniciar qualquer tarefa.
> 2. **NUNCA** gerar código que viole a "Constituição Arquitetural" (os 27 Invariantes).
> 3. **SEMPRE** declarar no início da resposta: qual **Skill Insight** foi consultado e quais **Invariantes (INV-X)** são relevantes para a tarefa.
> 4. **NUNCA** pular o Passo 0 (The Forensic Pause): identificar skills e invariantes antes de propor código.
>
> **Sem Insight = Sem Código.**

---

## 🏛️ CONSELHO SINTÉTICO — Personas de Auditoria

O projeto utiliza um **Conselho de Personas** distribuído. Cada persona atua como filtro de auditoria independente. Para mudanças estruturais, **TODO O CONSELHO** deve ser invocado.

| Persona | Papel | Filtro de Auditoria |
|---|---|---|
| **Chief Architect** | Integridade de domínio, Bounded Contexts & C4 | Valida que UI (`features/`) NÃO importa Domain/Infrastructure. Verifica isolamento de camadas. |
| **Senior Engineer** | Dart/Wasm, Riverpod, SQL & TDD | Garante Riverpod (Generator), WASM-ready (`dart:js_interop`), TDD rigoroso, constraint-based layouts. |
| **QA & Security** | RLS, Isolamento de Tenant & Prova Forense | Valida RLS com `auth.jwt()`, Error Parity (INV-26), HMAC, tenant isolation, Red Team tests. |
| **UX & Operations** | Material 3, OCC & Carga Cognitiva | Garante Material 3, paleta Industrial Deep, prevenção de eye-strain (24/7), layouts mobile-first. |
| **Business Maverick** | ROI, Estratégia & Proteção de Lucro | Valida free-tier de serviços 3rd-party, impacto financeiro de decisões, product-market fit. |
| **Lead Reviewer** | Gatekeeper — executa `/veraprob-pr-scanner` | **Último filtro antes do merge.** Executa scanner determinístico, reporta BLOCK/WARN/REGRESSION. |

### Skills Disponíveis (`.claude/skills/`)

| Skill | Quando Invocar |
|---|---|
| **veraprob-pr-scanner** | ANTES de qualquer review de PR. Executa `bash scripts/pr_full_scanner.sh` obrigatoriamente. |
| **test-driven-development** | SEMPRE antes de implementar features/bugfixes. Teste falhando PRIMEIRO. |
| **security-best-practices** | Ao criar APIs, lidar com autenticação, CORS, XSS, CSRF, OWASP Top 10. |
| **ingestion-streaming-architect** | Ao tocar ingestão de telemetria, Edge Functions, webhooks, batch inserts, idempotência. |
| **prompt-injection-auditor** | Ao criar workflows com LLM. Executa auditoria de injection/jailbreak (50+ padrões). |
| **systematic-debugging** | SEMPRE ao debugar. 4 fases: Root Cause → Pattern → Hypothesis → Implementation. |
| **database-schema-design** | Ao criar/refatorar tabelas, migrations, indexes, relationships. |
| **wcag-audit-patterns** | Ao auditar/implementar acessibilidade (WCAG 2.2 AA). |
| **frontend-design** | Ao construir interfaces web com design production-grade. |
| **flutter-building-layouts** | Ao criar/refatorar layouts Flutter. |
| **flutter-theming-apps** | Ao customizar temas, cores e tipografia do app. |
| **blue-ocean-strategy** | Sessões de estratégia de produto e mercado. |
| **competitive-analysis** | Análise de competidores e alternativas. |
| **competitor-alternatives** | Comparativos com soluções concorrentes. |
| **firecrawl** | Web scraping e crawling. |
| **hostile-defense-attorney** | Defesa de arbitragem SLA (auditório hostil). |
| **iot-chaos-simulator** | Simulação de caos IoT (GPS jitter, clock skew, duplicatas). |
| **product-strategy-session** | Sessões de estratégia de produto. |
| **supabase-postgres-best-practices** | Boas práticas Supabase/Postgres. |
| **ui-ux-pro-max** | Design UI/UX profissional. |

---

## 📜 CONSTITUIÇÃO ARQUITETURAL — OS 27 INVARIANTES FORENSES

> **VIOLAR QUALQUER INVARIANTE = FALHA CRÍTICA. O PR NÃO PROSSEGUE.**

### 🔴 INVARIANTES CRÍTICOS (Falha Imediata)

| ID | Nome | Regra |
|---|---|---|
| **INV-1** | **Soberania de Identidade** | Toda query MUST filtrar por `organization_id`. A aplicação MUST validar que `organization_id` do payload bate com claim JWT (Fail-Fast). |
| **INV-26** | **Paridade de Erro** | Endpoints sensíveis à segurança MUST retornar status idêntico (404) para 'Not Found' e 'Other Org' — previne Oracle Attacks. ALL Postgres repos MUST usar `PostgresErrorInterceptor` ou estender `BasePostgresRepository`. |
| **INV-30** | **DI Total (Anti-Singleton)** | Proibido usar `Supabase.instance`. O `SupabaseClient` DEVE ser injetado via construtor em todos os repositórios e serviços. |
| **INV-31** | **HMAC Zero-Knowledge** | Assinatura HMAC ocorre APENAS nas Edge Functions. Chave isolada do DB. Verificação obrigatória On-Read para Ledger/SLA. |
| **INV-31.2** | **Graceful Key Rotation** | Todo HMAC gerado deve carregar prefixo de versão (`vN\|hexhash`). Chaves legadas são resolvidas via mapeamento de ambiente (`HMAC_SECRET_KEY_V{N}`). Troca de segredos NÃO invalida histórico do Ledger. |

### 🟡 TODOS OS 27 INVARIANTES

| ID | Categoria | Regra |
|---|---|---|
| INV-1 | Identidade | Toda query/filter por `organization_id`. Validação JWT obrigatória (Fail-Fast). |
| INV-2 | RLS Hardening | Políticas usam `auth.jwt() ->> 'organization_id'`. NUNCA `auth.uid()`. |
| INV-3 | Ledger Integrity | Tabelas financeiras/veredito são APPEND-ONLY. Sem `UPDATE`/`DELETE`. |
| INV-4 | Money Type | `BIGINT` (cents) no DB; `int` nos DTOs; `Money` VO no Domain. |
| INV-5 | BPS Precision | Symmetric Rounding: `(cents * bps + 5000) ~/ 10000`. Proibido truncar. |
| INV-6 | UTC Obrigatório | `DateTime.now().toUtc()` em UMA LINHA. Regex-enforced. |
| INV-7 | Null Safety | Sem `dynamic` no código de aplicação. Tipos estritos apenas. |
| INV-8 | Repo Isolation | Repositories MUST impor `organization_id` em TODAS ops read/write. |
| INV-9 | Evidence Sealing | Hash SHA-256 na ingestão para TODA telemetria/arquivos brutos. |
| INV-10 | Error Visibility | Usar `IntegrityException` para violações de domínio. Sem silent failures. |
| INV-11 | Skill Sealing | "Step 0" Skill Insight obrigatório antes de implementação. |
| INV-12 | Scanner Guard | Anotar doubles não-moeda com `// Physical Metric - Double Required`. |
| INV-13 | Layer Bounds | C4: Features NÃO importam Domain ou Infrastructure. |
| INV-14 | Adaptive Engine | Core transport-agnostic: usa Asset/Operator/Execution. |
| INV-15 | Deterministic | Avaliação gera resultados byte-idênticos em replay. |
| INV-16 | Connection Ops | Supabase Free Tier: máx 60 conexões concorrentes. Design para pooling. |
| INV-17 | Wasm-Ready | Usar `dart:js_interop` para Web. Sem legado `dart:js` ou `dart:html`. |
| INV-18 | Zero-Trust | Telemetria não confiável até normalizada. Spoofing suspeito vai pra quarentena. |
| INV-19 | JIT Workflows | Criação inline de master data (Zones/Assets) em fluxos de contrato. |
| INV-20 | Shift Patterns | Usar `DateTimeRange` + normalização UTC para todos os schedules. |
| INV-21 | Audit Trail | Todo verdict do Engine carrega Snapshot ID rastreável. |
| INV-22 | Multi-Tenancy | Tenant-A NUNCA vê dados de Tenant-B (testar via Red Team tests). |
| INV-23 | Free-Tier First | Todo serviço 3rd-party deve ter free tier para estágio pré-receita. |
| INV-24 | Security Guard | `Security Audit Signature` obrigatório em toda instrução agêntica. |
| INV-25 | Tech Stack | Supabase | MapTiler | Sentry | PostHog | Resend. SOC 2 compliant. |
| **INV-26** | **Error Parity** | Status idêntico (404) para 'Not Found' e 'Other Org'. Oracle Attack prevention. |
| INV-27 | Origin Ownership | Operações source-to-destination MUST verificar ownership da origem. IDs não autorizados = 404. |
| **INV-28** | **Testabilidade Emasculada** | Widgets NÃO devem ter dependências ocultas de Singletons. Todo estado externo MUST ser mockável via `ProviderScope` overrides. |
| **INV-30** | **DI Total (Anti-Singleton)** | Proibido `Supabase.instance`. `SupabaseClient` injetado via construtor em TODOS os repos e serviços. |
| **INV-31** | **HMAC Zero-Knowledge** | HMAC APENAS nas Edge Functions. Chave isolada do DB. Verificação On-Read obrigatória para Ledger/SLA. |
| **INV-31.2** | **Graceful Key Rotation** | HMAC prefixado com versão (`vN\|hexhash`). Chaves legadas resolvidas via env. Rotação sem brick do histórico. |
| **INV-32** | **Optimistic Locking (Lost Update Prevention)** | Todo aggregate root mutável (Contract, Vehicle) possui coluna `version INT NOT NULL DEFAULT 1` com trigger de autoincremento. Repositories MUST usar `updateWithVersion()` que filtra por `.eq('version', entity.version)` e discrimina forense entre `ConflictException.staleVersion` (concorrência) e `ConflictException.deleted` (recurso deletado). Append-only (Ledger) é excluído. |

---

## 🔧 PROTOCOLO DE INFRAESTRUTURA

### BasePostgresRepository — Padrão Obrigatório para Repositórios

**TODOS** os repositórios que acessam Postgres MUST estender `BasePostgresRepository` ou usar o mixin `PostgresErrorInterceptor`. Isto é verificado pelo PR Scanner (regra `INV-26-REPO`).

```dart
// ✅ CORRETO: Estende BasePostgresRepository
class ContractRepository extends BasePostgresRepository implements IContractRepository {
  ContractRepository(SupabaseClient client) : super(client);

  Future<Contract?> findById(String id, String orgId) async {
    return withErrorHandler(
      'contract',
      id,
      () async {
        final data = await client
            .from('contracts')
            .select()
            .eq('id', id)
            .eq('organization_id', orgId)  // ← INV-1
            .maybeSingle();
        if (data == null) return null;
        return _mapToEntity(data);
      },
    );
  }
}
```

### Regras do `withErrorHandler`

| Parâmetro | Obrigatório? | Finalidade |
|---|---|---|
| `resourceType` | ✅ SIM | Nome do domínio (ex: `'contract'`) — usado em logs forenses |
| `resourceId` | ✅ SIM (ou null) | ID da entidade. Se null (ID gerado pelo DB), hash do payload é gerado |
| `operation` | ✅ SIM | A chamada Supabase a ser executada |
| `insertPayload` | ⚠️ Para INSERTs | Payload bruto para hash SHA-256 forense |

### Injeção de Dependência via Construtor

**NUNCA** usar `Supabase.instance.client` diretamente. Todo repositório recebe o `SupabaseClient` via construtor:

```dart
// ❌ CRÍTICO: Acesso direto ao singleton
final client = Supabase.instance.client;

// ✅ CORRETO: Injeção via construtor
class MyRepository extends BasePostgresRepository {
  MyRepository(SupabaseClient client) : super(client);
}
```

### PostgresErrorInterceptor — Mapeamento de Erros

| Código PostgREST | Significado | Exceção de Domínio | Resposta HTTP |
|---|---|---|---|
| `22P02` | invalid_text_representation | `ResourceNotFoundException` | 404 |
| `23503` | foreign_key_violation | `ResourceNotFoundException` | 404 |
| `PGRST116` | not_found | `ResourceNotFoundException` | 404 |
| `PGRST204` | column_not_found | `ResourceNotFoundException` | 404 |
| `P0001` | RAISE EXCEPTION | `IntegrityException(msg)` | Preservado |
| `23505` | unique_violation | `IntegrityException` | Preservado |
| Outros | Não mapeado | Re-lançado (fail-fast) | — |

**Nenhum** erro PostgREST pode vazar para a camada de Application. A tradução é automática e obrigatória.

---

## 🔒 PADRÃO DE INTEGRIDADE — HMAC & JSON CANÔNICO

### INV-9: Ordenação Recursiva de Chaves JSON

Para garantir que hashes SHA-256 sejam **idênticos** entre Dart (insert) e Deno (verificação), as chaves JSON DEVEM ser ordenadas alfabeticamente de forma recursiva:

```dart
// BasePostgresRepository._sortKeys() — ordenação recursiva
static dynamic _sortKeys(dynamic obj) {
  if (obj == null || obj is! Map<String, dynamic>) return obj;
  final sorted = <String, dynamic>{};
  final keys = obj.keys.toList()..sort();
  for (final key in keys) {
    sorted[key] = _sortKeys(obj[key]);
  }
  return sorted;
}
```

**Por que:** `jsonEncode` do Dart preserva a ordem de inserção do Map. Sem ordenação, o mesmo payload geraria hashes diferentes em Dart vs Deno — quebrando a verificação HMAC.

### Isolamento da Chave HMAC nas Edge Functions (Blind DB)

- A chave HMAC **NUNCA** reside no banco de dados ou no cliente Flutter.
- A assinatura HMAC-SHA256 é computada **exclusivamente** nas Edge Functions (Deno).
- O banco de dados é "cego" (Blind DB) — armazena apenas o hash resultante, nunca a chave.
- Na ingestão, o payload é selado com hash SHA-256 (`_hashPayloadIfPresent`) para rastreabilidade forense.
- A verificação é feita pelo HMAC Verification Worker (Edge Function) que compara o hash assinado com o hash do payload armazenado.

### Checklist de Segurança para Edge Functions de Ingestão

- [ ] Autenticação: API key ou HMAC-SHA256
- [ ] Tenant resolution: `organization_id` do JWT, NUNCA do body
- [ ] Validação de schema: campos obrigatórios, tipos, `occurred_at` válido
- [ ] Idempotência: chave UNIQUE constraint, duplicata retorna 200
- [ ] Rate limiting: por `device_id`, retorna 429 com `Retry-After`
- [ ] Sem Ledger writes síncronas: retorna 202 antes de normalizar/avaliar
- [ ] Erros: payloads malformados retornam 400 estruturado, nunca 200 com erro no JSON
- [ ] Audit log: todo payload aceito/rejeitado logado com `device_id`, `received_at`, `status_code`, `idempotency_key`

---

## 🏗️ Visão Geral do Projeto

**VeraProb** é uma plataforma **B2B de Conformidade SLA & Proteção Financeira** construída com **Flutter/Dart**. Atua como um "Juiz Digital" que transforma telemetria bruta (GPS, IoT, Check-ins) em **Verdade Contratual Verificável** através de um pipeline event-sourced com auditabilidade forense.

### Core Pipeline

1. **Ingestão** — Telemetria bruta via Edge Functions seguras
2. **Normalização** — Dados unificados em Fatos Canônicos (snapshots determinísticos)
3. **Avaliação** — Fatos replayados contra Regras SLA pelo Motor de Avaliação Forense
4. **Veredito** — Impactos financeiros selados em Ledger Imutável (INV-7)

### Arquitetura: Clean Architecture (C4 Model)

| Camada | Path | Responsabilidade |
|---|---|---|
| **Domain** | `lib/domain/` | Entidades, value objects, interfaces de repositório. Zero dependências de infra (INV-18) |
| **Application** | `lib/application/` | Casos de uso, commands, handlers, projeções, adapters, ports |
| **Infrastructure** | `lib/infrastructure/` | Implementações Supabase/Postgres, adapters externos, data mappers |
| **State** | `lib/state/` | Riverpod providers e gerenciamento global de estado |
| **Presentation** | `lib/presentation/` / `lib/features/` | Flutter UI com widgets atômicos, telas por feature |
| **Core** | `lib/core/` | Utilitários compartilhados, invariantes forenses, constantes, theme, config, time |

### Bounded Contexts (`lib/domain/`)

- `admin/` — Administração
- `auth/` — Autenticação & autorização
- `authority/` — Controle de acesso
- `entities/` — Entidades core do negócio
- `sla_audit/` — Lógica de avaliação SLA e vereditos
- `stops/` — Gerenciamento de paradas/rotas
- `super_admin/` — Super-admin
- `assets/`, `enums/`, `services/`, `shared/`

---

## 🛠️ Tecnologias

- **Flutter SDK** >= 3.41.5 / **Dart** ^3.10.8
- **State Management:** Flutter Riverpod
- **Backend:** Supabase (PostgreSQL, Auth, Storage, Edge Functions)
- **Local DB:** Drift (SQLite) para LocalFactQueue offline
- **Maps:** flutter_map + latlong2
- **Charts:** fl_chart
- **Observability:** Sentry, PostHog
- **Localization:** intl, flutter_localizations (PT-BR)
- **Testing:** flutter_test, integration_test, mocktail, fake_async

---

## 🚀 Building and Running

### Setup & Run

```bash
# 1. Start local Supabase (Docker)
supabase start

# 2. Apply migrations + seed
supabase db reset

# 3. Configure env
cp .env.example .env
# (preencha com chaves do `supabase status`)

# 4. Run
flutter run -d chrome --web-renderer wasm
```

### Comandos Úteis

| Comando | Descrição |
|---|---|
| `flutter run -d chrome --web-renderer wasm` | Roda app no browser com WASM |
| `flutter analyze` | Static analysis (lints + type checking) |
| `flutter test` | Roda testes unitários/widget |
| `flutter test --coverage` | Testes com coverage |
| `flutter test integration_test/` | Testes de integração |
| `dart run build_runner build` | Gera código (Drift, etc.) |
| `bash scripts/pr_full_scanner.sh` | Scanner forense completo (run before merge) |
| `supabase start` | Start containers Supabase local |
| `supabase db reset` | Reset DB com migrations + seed |

### Code Generation

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## 📋 Protocolo de Execução (MUST)

### Passo 0 — The Forensic Pause (INV-11)

Antes de propor código, declarar:

1. **Skill Insight:** Qual skill de `.claude/skills/` foi consultada.
2. **Invariant Check:** Quais invariantes (INV-1 a INV-27) são relevantes.

**Sem Insight = Sem Código.**

### TDD Obrigatório

- Escrever teste falhando PRIMEIRO.
- Implementar código mínimo para passar.
- Refatorar com sign-off do Conselho.
- **Código sem teste falhando primeiro = DELETAR e refazer do zero.** (Ver skill `test-driven-development`)

### PR Scanner Pre-Flight

1. Self-audit por `DateTime.now()` (sem `.toUtc()`) e `double` não-anotado.
2. Executar `bash scripts/pr_full_scanner.sh`.
3. Scanner exit 1 = **NO-GO**. Terminar review. Listar BLOCKs.
4. Scanner exit 0 = Prosseguir com análise neural.

### Consenso do Conselho

Para mudanças estruturais: Architect, Senior, QA devem concordar.

### Passo Final — Self-Audit Loop (Obrigatório)

**Antes de entregar qualquer código**, o Qwen deve verificar:

- [ ] Meu código usa `Supabase.instance`? → Se sim, refatorar para DI via construtor (INV-30).
- [ ] Este JSON será hasheado? → Se sim, aplicar `_sortKeys` para canonicidade (INV-9).
- [ ] Este erro vaza códigos do banco? → Se sim, envolver com `withErrorHandler` (INV-26).
- [ ] Este widget tem dependência oculta de Singleton? → Se sim, tornar mockável via `ProviderScope` (INV-28).
- [ ] Estou usando `DateTime.now()` sem `.toUtc()`? → Se sim, corrigir (INV-6).
- [ ] Este widget importa `domain/` ou `infrastructure/`? → Se sim, violação C4 (INV-13).

**Qualquer checkbox marcado = refatorar ANTES de entregar.**

---

## 🎯 Padrões de Código

### Dart & Flutter Web

- **State Management:** Riverpod (Generator). Evitar `ChangeNotifier`.
- **Projections:** `AsyncValue` patterns para UI.
- **Layouts:** Constraint-based. Mobile-first. Paleta Industrial Deep (eye-strain 24/7).
- **Web:** Target WASM/CanvasKit.

### Supabase & Postgres

- **Migrations:** SQL idempotente puro. Sem `DROP` ou `ALTER` destrutivo.
- **RLS:** Habilitado em TODA tabela. Tenant-isolation inegociável.
- **Idempotência:** Ingestão duplicada retorna `200 OK` (Ignored), não erro de duplicata.

### Precisão Financeira

- **Application Layer (DTOs):** `int` (cents/bps)
- **Domain Layer:** `Money` value object
- **BPS Rates:** `(value * BPS) ~/ 10000`. Proibido truncar.

### Linting (`analysis_options.yaml`)

- `avoid_print: true` | `unawaited_futures: true` | `prefer_const_constructors: true`
- `use_super_parameters: true` | `always_declare_return_types: true`
- `exhaustive_cases: true` | `no_logic_in_create_state: true`
- `use_build_context_synchronously: true` | `avoid_unnecessary_containers: true`

### Isolamento de Camadas (C4 — INV-13)

- UI (`features/`) **NUNCA** importa `domain/` ou `infrastructure/`
- Domain layer tem **zero** dependências de infra

---

## 📂 Diretórios Chave

| Diretório | Propósito |
|---|---|
| `lib/` | Todo source code (Clean Architecture layers) |
| `supabase/` | Migrations, seed data, config |
| `sql/` | Scripts SQL raw |
| `scripts/` | Automação (PR scanner, coverage, bootstrap) |
| `test/` | Testes unitários e widget |
| `integration_test/` | Testes end-to-end |
| `docs/` | Documentação, governança, manifesto forense |
| `.claude/` | Skills, regras e personas de agentes AI |
| `assets/` | Assets estáticos (fontes, etc.) |

---

## 📍 Status Atual

**Phase:** 10.5 — The Forensic Truth (Hardening Architecture & Layer Isolation)
**Recent Milestone:** Phase 10.4 WS-5 (Telemetry Map-Sync) COMPLETED
**Next:** Lote 5 (C4 Correction) & Infrastructure DB Sync

---

## 📎 Arquivos Importantes

| Arquivo | Propósito |
|---|---|
| **`QWEN.md`** | **SSOT do Qwen Code** — governança, invariantes, protocolos e padrões consolidados |
| `CLAUDE.md` | Master orchestrator (fonte original das regras) |
| `.claude/rules/forensic-standards.md` | 27 invariantes forenses (fonte canônica) |
| `.claude/skills/` | 20 skills especializados de auditoria e desenvolvimento |
| `analysis_options.yaml` | Configuração do Dart analyzer |
| `pubspec.yaml` | Dependências e configuração do projeto |
| `.cursorrules` | Regras de editor e auto-inicialização |
| `scripts/pr_full_scanner.sh` | Scanner forense de PR (executar antes do merge) |
