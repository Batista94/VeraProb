# =============================================================================
# VeraProb — Orchestration Makefile
# =============================================================================

# ── Environment ───────────────────────────────────────────────────────────────
IMAGE_NAME = veraprob-test-env
# Em Windows/PowerShell, CURDIR precisa ser tratado para o Docker
# Usamos um volume nomeado (veraprob_dart_tool) para isolar o cache do Linux do Windows
DOCKER_RUN = docker run --rm -v "$(CURDIR)":/app -v veraprob_dart_tool:/app/.dart_tool -v veraprob_pub_cache:/root/.pub-cache -v /app/build -w /app

# Uso:
#   make <comando>
#
# Exemplo:
#   make help
# =============================================================================

.PHONY: help setup env run run-staging scan-secrets test-security pr-scan load-tokens index-advisor coverage goldens chaos-test format format-check test test-db test-e2e test-e2e-file test-all test-full full-check build-test-env check check-integrity docs-check

help: ## Mostra este menu de ajuda
	@echo "VeraProb — Comandos Disponíveis:"
	@echo "-----------------------------------------------------------------------------"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo "-----------------------------------------------------------------------------"

# ── Desenvolvimento ───────────────────────────────────────────────────────────

setup: ## [A La Carte] Prepara o ambiente do zero (DB, Migrações, Seeds)
	node scripts/dev/bootstrap_dev.mjs

env: ## Cria o arquivo .env inicial a partir do template .env.example
	@if [ ! -f .env ]; then cp .env.example .env && echo ".env criado."; else echo ".env já existe."; fi

run: ## Inicia o ambiente de desenvolvimento local
	powershell scripts/dev/run_dev.ps1

run-staging: ## Inicia o ambiente simulando staging
	powershell scripts/dev/run_staging.ps1

# ── Segurança & Governança (INV-28) ──────────────────────────────────────────

check-integrity: ## [Tier 1] Valida encoding UTF-8 e finais de linha LF em todo o projeto
	$(DOCKER_RUN) $(IMAGE_NAME) python3 scripts/security/check_integrity.py

scan-secrets: ## Executa o scanner de segredos nos arquivos staged
	$(DOCKER_RUN) $(IMAGE_NAME) python3 scripts/security/scan_secrets.py

test-security: ## Valida se os 3 níveis do motor do scanner estão operacionais
	$(DOCKER_RUN) $(IMAGE_NAME) python3 scripts/internal/test_scan_secrets.py

# ── QA & Performance ──────────────────────────────────────────────────────────

index-advisor: ## [INV-12] Analisa queries staged para Seq Scans e índices faltantes
	$(DOCKER_RUN) --network host -e PGHOST=host.docker.internal $(IMAGE_NAME) python3 scripts/index_advisor.py

load-tokens: ## Gera tokens JWT para testes de estresse (K6)
	node scripts/qa/generate_load_test_tokens.mjs

coverage: ## Gera relatório de cobertura de testes Dart/Flutter
	dart scripts/qa/coverage_report.dart

goldens: ## [Tier 1] Gera/Atualiza Goldens herméticos via Docker Linux (paridade CI — NUNCA atualize goldens fora deste target)
	bash scripts/generate_goldens.sh

chaos-test: ## Executa a suite de testes de caos (resiliência)
	bash scripts/qa/chaos/run_chaos_suite.sh

format: ## [Tier 1] Formata o código usando o padrão do ambiente hermético (Linux/Docker)
	$(DOCKER_RUN) $(IMAGE_NAME) dart format .

format-check: ## [Tier 1] Valida se o código segue o padrão de formatação (idêntico ao CI)
	$(DOCKER_RUN) $(IMAGE_NAME) dart format --output=none --set-exit-if-changed .

# Selo de sincronia para o Windows local
.local_deps_synced: pubspec.yaml
	@echo [Local-Sync] Detectada mudanca em pubspec.yaml. Atualizando Windows...
	flutter pub get
	@echo synced > .local_deps_synced

test: .local_deps_synced ## Executa a suite completa de testes (Sequencial -j 1 para evitar race conditions no DB)
	flutter test -j 1

test-db: ## [INV-28] Executa testes forenses de integridade no PostgreSQL (pgTap)
	supabase test db

test-e2e: .local_deps_synced ## [E2E] Executa testes E2E SuperAdmin (auto-aplica dart-defines; ver .claude/rules/ci-blocks.md #8)
	flutter test test/integration/e2e/ -j 1 \
		--dart-define=SKIP_MFA_DEV=true \
		--dart-define=ENV=dev

test-e2e-file: .local_deps_synced ## [E2E] Executa um arquivo E2E específico: make test-e2e-file FILE=path/to/test.dart
	@if [ -z "$(FILE)" ]; then echo "FILE=path/to/test.dart required"; exit 1; fi
	flutter test $(FILE) \
		--dart-define=SKIP_MFA_DEV=true \
		--dart-define=ENV=dev

# Nota: test-all NÃO inclui test-e2e (E2E exige Supabase rodando + service-role + tem ciclo lento).
# Pipeline E2E é separado — rode `make test-e2e` quando o ambiente local estiver up.
test-all: test test-db ## Roda testes não-E2E (Flutter unit/widget + DB pgTap)

test-full: test-all test-e2e ## Roda TUDO incluindo E2E (exige Supabase local up)

# ── Sincronização de Ambiente (Automação) ───────────────────────────────────

# O selo de sincronia garante que o container tem as dependências corretas.
# Ele depende do pubspec.yaml; se você mudar o arquivo, o selo fica "velho".
.docker_deps_synced: pubspec.yaml
	@echo [Auto-Sync] Detectada mudanca em pubspec.yaml ou ambiente novo.
	@echo Sincronizando dependencias dentro do ambiente hermetico (Docker)...
	$(DOCKER_RUN) $(IMAGE_NAME) flutter pub get
	@echo synced > .docker_deps_synced

build-test-env: ## Constrói a imagem Docker de ambiente de testes e sincroniza dependências
	docker build -t $(IMAGE_NAME) -f scripts/docker/Dockerfile.test .
	@$(MAKE) .docker_deps_synced

# ── Atalhos ───────────────────────────────────────────────────────────────────

# pr-scan agora depende do selo de sincronia para evitar erros de análise
pr-scan: .docker_deps_synced ## [Lead Reviewer] Executa o scanner determinístico completo de PR
	$(DOCKER_RUN) -e FULL_SCAN=$(FULL_SCAN) $(IMAGE_NAME) bash scripts/security/pr_full_scanner.sh

docs-check: ## [Governance] Valida sync entre AGENTS.md index e SSOT (.claude/rules/ci-blocks.md + .kiro/steering/lessons.md)
	bash scripts/governance/check_docs_sync.sh

check: check-integrity scan-secrets pr-scan index-advisor format-check docs-check ## Roda todas as verificações de segurança e lint locais

full-check: ## O "Veredito Supremo": Scanner forense (Full Scan) + Testes (incl. E2E) + Caos + Coverage
	@$(MAKE) check FULL_SCAN=1
	@$(MAKE) test-full chaos-test coverage
