# veraprob — Run STAGING Environment
# Usage: .\scripts\run_staging.ps1
#
# Requires environment variables to be set before running:
#   $env:SUPABASE_URL_STAGING = "https://..."
#   $env:SUPABASE_KEY_STAGING = "eyJ..."
#   $env:SENTRY_DSN_STAGING   = "https://..."    (optional)
#
# In CI/CD these are injected as GitHub Actions secrets automatically.

$ErrorActionPreference = "Stop"

$supabaseUrl = $env:SUPABASE_URL_STAGING
$supabaseKey = $env:SUPABASE_KEY_STAGING
$sentryDsn   = $env:SENTRY_DSN_STAGING ?? ""

if (-not $supabaseUrl -or -not $supabaseKey) {
    Write-Error @"
❌ Variáveis de staging não encontradas.
Defina antes de executar:
  `$env:SUPABASE_URL_STAGING = "https://<seu-ref-staging>.supabase.co"
  `$env:SUPABASE_KEY_STAGING = "eyJ..."
"@
    exit 1
}

Write-Host "🧪 [STAGING] Iniciando veraprob contra ambiente de staging..." -ForegroundColor Yellow
Write-Host "   URL: $($supabaseUrl.Substring(0, [Math]::Min(40, $supabaseUrl.Length)))..." -ForegroundColor DarkGray

flutter run -d chrome `
    --dart-define=ENV=staging `
    --dart-define=SUPABASE_URL=$supabaseUrl `
    --dart-define=SUPABASE_KEY=$supabaseKey `
    --dart-define=SENTRY_DSN=$sentryDsn
