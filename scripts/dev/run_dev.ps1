# veraprob — Run DEV Environment
# Usage: .\scripts\dev\run_dev.ps1
#
# Reads credentials from .env (local dev file, never committed).
# If .env doesn't exist, copy .env.example and fill in your credentials first.

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".env")) {
    Write-Error @"
❌ Arquivo .env não encontrado.
Execute: copy .env.example .env
Depois preencha com as credenciais do projeto veraprob-dev no Supabase.
"@
    exit 1
}

# 0. Kill lingering processes to prevent file locks (INV-28)
Write-Host "[VeraProb] Verificando processos órfãos (dart, flutter)..." -ForegroundColor DarkGray
Get-Process -Name "dart", "flutter" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "[DEV] Iniciando veraprob com credenciais de desenvolvimento..." -ForegroundColor Cyan
Write-Host "   Credenciais lidas de: .env" -ForegroundColor DarkGray

# 1. Garante que o Supabase local está rodando e reseta o banco.
Write-Host "Supabase: Iniciando serviços (supabase start)..." -ForegroundColor Green
supabase start

# Pequena pausa para garantir que o proxy está aceitando conexões antes do reset
Write-Host "⏳ Aguardando serviços estabilizarem..." -ForegroundColor DarkGray
Start-Sleep -Seconds 2

Write-Host "DB: Resetando banco local (supabase db reset)..." -ForegroundColor Green
supabase db reset

# 2. Seed the DB with test data.
Write-Host "SEED: Populando banco com dados de teste..." -ForegroundColor Green
node scripts/dev/bootstrap_dev.mjs

# 3. Start Edge Functions in a background job.
Write-Host "EDGE: Iniciando Edge Functions localmente..." -ForegroundColor Yellow
$efJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD
    supabase functions serve --env-file .env 2>&1
}
Write-Host "   Edge Functions job ID: $($efJob.Id)" -ForegroundColor DarkGray

# 4. Clean and get dependencies.
Write-Host "FLUTTER: Limpando cache e baixando dependências..." -ForegroundColor Cyan
flutter clean
flutter pub get

# 5. Run on Web Server (Port 8080).
# Note: --dart-define=SKIP_MFA_DEV=true is used to bypass 2FA locally.
Write-Host "RUN: Iniciando Flutter Web (Server na porta 8080)..." -ForegroundColor Cyan
flutter run -d web-server `
    --web-port=8080 `
    --dart-define=ENV=dev `
    --dart-define=SKIP_MFA_DEV=true

# Cleanup Edge Function job when Flutter exits
Write-Host "STOP: Encerrando serviços de fundo..." -ForegroundColor DarkGray
Stop-Job $efJob -ErrorAction SilentlyContinue
Remove-Job $efJob -ErrorAction SilentlyContinue
Write-Host "DONE: Ambiente encerrado." -ForegroundColor DarkGray
