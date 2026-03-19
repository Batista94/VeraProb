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

# Run on Chrome (Flutter Web). .env is read automatically by flutter_dotenv.
flutter run -d chrome --dart-define=ENV=dev
