# =============================================================================
# VeraProb — Orchestration Makefile
# =============================================================================
# Uso:
#   make <comando>
#
# Exemplo:
#   make help
# =============================================================================

.PHONY: help setup run scan-secrets test-security pr-scan load-tokens

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

scan-secrets: ## Executa o scanner de segredos nos arquivos staged
	python scripts/security/scan_secrets.py

test-security: ## Valida se os 3 níveis do motor do scanner estão operacionais
	python scripts/internal/test_scan_secrets.py

pr-scan: ## [Lead Reviewer] Executa o scanner determinístico completo de PR
	bash scripts/security/pr_full_scanner.sh

# ── QA & Performance ──────────────────────────────────────────────────────────

load-tokens: ## Gera tokens JWT para testes de estresse (K6)
	node scripts/qa/generate_load_test_tokens.mjs

coverage: ## Gera relatório de cobertura de testes Dart/Flutter
	dart scripts/qa/coverage_report.dart

chaos-test: ## Executa a suite de testes de caos (resiliência)
	bash scripts/qa/chaos/run_chaos_suite.sh

# ── Atalhos ───────────────────────────────────────────────────────────────────

check: scan-secrets pr-scan ## Roda todas as verificações de segurança locais
