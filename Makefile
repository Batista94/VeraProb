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

.PHONY: help setup run scan-secrets test-security pr-scan load-tokens index-advisor test test-db test-all full-check goldens build-test-env check-integrity

help: ## Mostra este menu de ajuda
	@echo "VeraProb — Comandos Disponíveis:"
	@echo "-----------------------------------------------------------------------------"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo "-----------------------------------------------------------------------------"

# ── Desenvolvimento ───────────────────────────────────────────────────────────

setup: ## [A La Carte] Prepara o ambiente do zero (DB, Migrações, Seeds)
	node scripts/dev/bootstrap_dev.mjs

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

goldens: ## [Tier 1] Gera/Atualiza Goldens herméticos via Docker (Linux)
	bash scripts/generate_goldens.sh

chaos-test: ## Executa a suite de testes de caos (resiliência)
	bash scripts/qa/chaos/run_chaos_suite.sh

format: ## [Tier 1] Formata o código usando o padrão do ambiente hermético (Linux/Docker)
	$(DOCKER_RUN) $(IMAGE_NAME) dart format .

# Selo de sincronia para o Windows local
.local_deps_synced: pubspec.yaml
	@echo [Local-Sync] Detectada mudanca em pubspec.yaml. Atualizando Windows...
	flutter pub get
	@echo synced > .local_deps_synced

test: .local_deps_synced ## Executa a suite completa de testes unitários (Dart/Flutter)
	flutter test

test-db: ## [INV-28] Executa testes forenses de integridade no PostgreSQL (pgTap)
	supabase test db

test-all: test test-db ## Roda todos os testes (Flutter + DB)

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
	$(DOCKER_RUN) $(IMAGE_NAME) bash scripts/security/pr_full_scanner.sh

check: check-integrity scan-secrets pr-scan index-advisor ## Roda todas as verificações de segurança locais

full-check: check test-all ## O "Veredito Supremo": Scanner forense + Execução de todos os testes
