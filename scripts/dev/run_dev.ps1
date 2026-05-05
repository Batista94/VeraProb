param (
    [switch]$FullVisual,
    [switch]$Clean
)

# veraprob — Run DEV Environment
# Usage: .\scripts\dev\run_dev.ps1 [-FullVisual] [-Clean]
#
# -FullVisual: Use CanvasKit renderer for pixel-perfect UI validation.
# -Clean: Force 'flutter clean' before starting (use when build is broken).
# Default: Uses HTML renderer for 5x faster load times.

$ErrorActionPreference = "Stop"

# Cleanup any previous background jobs
Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue

if (-not (Test-Path ".env")) {
    Write-Error "❌ Arquivo .env não encontrado. Execute: copy .env.example .env"
    exit 1
}

# 0. Kill lingering processes (INV-28)
Write-Host "[VeraProb] Verificando processos órfãos..." -ForegroundColor DarkGray
Get-Process -Name "dart", "flutter", "analysis_server" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

Write-Host "[DEV] Iniciando veraprob..." -ForegroundColor Cyan

# 1. Supabase & DB
Write-Host "Supabase: Iniciando e resetando banco..." -ForegroundColor Green
supabase start
Start-Sleep -Seconds 1
supabase db reset

# 2. Seed
Write-Host "SEED: Populando banco..." -ForegroundColor Green
node scripts/dev/bootstrap_dev.mjs

# 3. Edge Functions
Write-Host "EDGE: Iniciando Edge Functions..." -ForegroundColor Yellow
$efJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD
    supabase functions serve --env-file .env
}

# 4. Flutter Prep
if ($Clean) {
    Write-Host "FLUTTER: Limpando cache..." -ForegroundColor Cyan
    flutter clean
}
Write-Host "FLUTTER: Baixando dependências..." -ForegroundColor Cyan
flutter pub get

# 5. Run
$renderer = if ($FullVisual) { "canvaskit" } else { "html" }
$modeText = if ($FullVisual) { "🎨 VISUAL (CanvasKit)" } else { "🚀 SPEED (HTML)" }

Write-Host "RUN: Iniciando Flutter Web ($modeText na porta 8080)..." -ForegroundColor Cyan

# Execução direta para evitar problemas de parsing de argumentos
flutter run -d chrome --web-port=8080 --web-renderer $renderer --dart-define=ENV=dev --dart-define=SKIP_MFA_DEV=true

# Cleanup
Write-Host "STOP: Encerrando serviços..." -ForegroundColor DarkGray
Stop-Job $efJob -ErrorAction SilentlyContinue
Remove-Job $efJob -ErrorAction SilentlyContinue
