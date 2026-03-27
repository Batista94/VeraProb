# veraprob — Run DEV Environment
# Usage: .\scripts\run_dev.ps1
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

Write-Host "🔧 [DEV] Iniciando veraprob com credenciais de desenvolvimento..." -ForegroundColor Cyan
Write-Host "   Credenciais lidas de: .env" -ForegroundColor DarkGray

# 1. Garante que o Supabase local está rodando e reseta o banco.
#    Usar 'db reset' em vez de 'start' porque o schema muda com frequência.
Write-Host "🐘 Iniciando e resetando banco local (supabase start && supabase db reset)..." -ForegroundColor Green
supabase start
supabase db reset

# 2. Seed the DB with test data.
Write-Host "🌱 Populando banco com dados de teste..." -ForegroundColor Green
node scripts/bootstrap_dev.mjs

# 3. Start Edge Functions in a background job.
#    Required for super-admin-proxy (TenantHealthSnapshot, AuditLog) to resolve locally.
Write-Host "⚡ Iniciando Edge Functions localmente (super-admin-proxy)..." -ForegroundColor Yellow
$efJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD
    supabase functions serve super-admin-proxy --env-file .env 2>&1
}
Write-Host "   Edge Functions job ID: $($efJob.Id)" -ForegroundColor DarkGray

# 3. Run on Chrome (Flutter Web). .env is read automatically by flutter_dotenv.
flutter run -d chrome --dart-define=ENV=dev

# Cleanup Edge Function job when Flutter exits
Stop-Job $efJob -ErrorAction SilentlyContinue
Remove-Job $efJob -ErrorAction SilentlyContinue
Write-Host "✅ Edge Functions encerradas." -ForegroundColor DarkGray
