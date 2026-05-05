# veraprob — Run DEV Environment (Optimized for E2E Tests)
# Usage: .\scripts\dev\run_dev.ps1 (from project root)

$ErrorActionPreference = "Stop"

# Limpeza de jobs anteriores
Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue

if (-not (Test-Path ".env")) {
    Write-Error "❌ Arquivo .env não encontrado. Copie o .env.example e preencha as credenciais."
    exit 1
}

# 1. Kill lingering processes (INV-28) - Focado em performance
Write-Host "[VeraProb] Liberando descritores de arquivo..." -ForegroundColor DarkGray
Get-Process -Name "dart", "flutter", "analysis_server" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

Write-Host "[DEV] Iniciando ambiente VeraProb..." -ForegroundColor Cyan

# 2. Supabase & DB Reset
Write-Host "Supabase: Iniciando e resetando banco..." -ForegroundColor Green
supabase start
supabase db reset

# 3. Seed/Bootstrap
Write-Host "SEED: Populando banco (bootstrap_dev.mjs)..." -ForegroundColor Green
node scripts/dev/bootstrap_dev.mjs

# 4. Edge Functions em Background (INV-31)
Write-Host "EDGE: Iniciando Edge Functions..." -ForegroundColor Yellow
$efJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD
    supabase functions serve --env-file .env 2>&1
}

# 5. Flutter Web Server (Porta Fixa 50185)
# Removido 'flutter clean' para acelerar o boot. Use manualmente se necessário.
Write-Host "FLUTTER: Baixando dependências..." -ForegroundColor Cyan
flutter pub get

Write-Host "RUN: Servindo portal em http://localhost:50185..." -ForegroundColor Cyan
# Usando -d web-server para evitar abrir janela do Chrome local e poupar RAM para o Playwright
flutter run -d web-server `
    --web-port=50185 `
    --dart-define=SKIP_MFA_DEV=true

# Cleanup ao encerrar
Write-Host "STOP: Encerrando Edge Functions..." -ForegroundColor DarkGray
Stop-Job $efJob -ErrorAction SilentlyContinue
Remove-Job $efJob -ErrorAction SilentlyContinue
Write-Host "DONE: Ambiente encerrado." -ForegroundColor DarkGray