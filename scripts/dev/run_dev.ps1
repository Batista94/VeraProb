# veraprob — Run DEV Environment (Optimized for UI Validation)
# Usage: .\scripts\dev\run_dev.ps1 (from project root)

$ErrorActionPreference = "Stop"

# Limpeza de jobs anteriores
Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue

if (-not (Test-Path ".env")) {
    Write-Error "❌ Arquivo .env não encontrado. Copie o .env.example e preencha as credenciais."
    exit 1
}

# 1. Kill lingering processes (focado em performance)
Write-Host "[VeraProb] Liberando descritores de arquivo..." -ForegroundColor DarkGray
Get-Process -Name "dart", "flutter", "analysis_server" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

Write-Host "[DEV] Iniciando ambiente VeraProb..." -ForegroundColor Cyan

# 2. Supabase — só inicia se não estiver rodando
Write-Host "Supabase: Verificando status..." -ForegroundColor Green
$supabaseRunning = $false
try {
    $statusOutput = supabase status 2>&1 | Out-String
    if ($statusOutput -match "API URL") {
        $supabaseRunning = $true
        Write-Host "  → Supabase já está rodando. Pulando 'supabase start'." -ForegroundColor DarkGreen
    }
} catch { }

if (-not $supabaseRunning) {
    Write-Host "  → Iniciando Supabase..." -ForegroundColor Green
    supabase start
}

# 3. DB Reset + Seed
Write-Host "DB: Resetando banco..." -ForegroundColor Green
supabase db reset

# 4. Seed/Bootstrap
Write-Host "SEED: Populando banco (bootstrap_dev.mjs)..." -ForegroundColor Green
node scripts/dev/bootstrap_dev.mjs

# 5. Edge Functions em Background
Write-Host "EDGE: Iniciando Edge Functions..." -ForegroundColor Yellow
$efJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD
    supabase functions serve --env-file .env 2>&1
}

# 6. Flutter — pula pub get se pubspec.lock não mudou desde último build
$pubspecHash = ""
$cacheFile = ".dart_tool/.pubget_hash"
if (Test-Path "pubspec.lock") {
    $pubspecHash = (Get-FileHash "pubspec.lock" -Algorithm MD5).Hash
}

$needsPubGet = $true
if ((Test-Path $cacheFile) -and $pubspecHash) {
    $cachedHash = Get-Content $cacheFile -ErrorAction SilentlyContinue
    if ($cachedHash -eq $pubspecHash) {
        $needsPubGet = $false
        Write-Host "FLUTTER: Dependências em cache (pub get pulado)." -ForegroundColor DarkCyan
    }
}

if ($needsPubGet) {
    Write-Host "FLUTTER: Baixando dependências..." -ForegroundColor Cyan
    flutter pub get
    if ($pubspecHash) {
        $pubspecHash | Out-File -FilePath $cacheFile -NoNewline
    }
}

# 7. Servir portal — HTML renderer para boot rápido (validação de UI)
Write-Host "RUN: Servindo portal em http://localhost:50185..." -ForegroundColor Cyan
Write-Host "     (web-renderer html = boot rápido para validação)" -ForegroundColor DarkGray
flutter run -d web-server `
    --web-port=50185 `
    --web-renderer html `
    --dart-define=SKIP_MFA_DEV=true

# Cleanup ao encerrar
Write-Host "STOP: Encerrando Edge Functions..." -ForegroundColor DarkGray
Stop-Job $efJob -ErrorAction SilentlyContinue
Remove-Job $efJob -ErrorAction SilentlyContinue
Write-Host "DONE: Ambiente encerrado." -ForegroundColor DarkGray
