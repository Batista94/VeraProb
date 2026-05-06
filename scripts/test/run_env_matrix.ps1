#!/usr/bin/env pwsh
# scripts/test/run_env_matrix.ps1
#
# Runs test/core/config/environment_config_test.dart four times — once per
# (ENV, SKIP_MFA_DEV) permutation — to validate the INV-6 dual-guard on
# EnvironmentConfig.skipMfaForSuperAdmin.
#
# `String.fromEnvironment` / `bool.fromEnvironment` are const-driven: their
# values are frozen at compile time. Each invocation passes a DIFFERENT
# --dart-define payload so the test sees a different EnvironmentConfig.
#
# Exit code: 0 if all four runs pass; non-zero on first failure.
#
# Usage:
#   pwsh scripts/test/run_env_matrix.ps1

$ErrorActionPreference = 'Stop'

$matrix = @(
    @{ Env = 'dev';     Skip = 'true';  Label = 'dev + SKIP=true (bypass=true)' }
    @{ Env = 'prod';    Skip = 'true';  Label = 'prod + SKIP=true (CRITICAL bypass=false)' }
    @{ Env = 'staging'; Skip = 'true';  Label = 'staging + SKIP=true (bypass=false)' }
    @{ Env = 'dev';     Skip = 'false'; Label = 'dev + SKIP=false (bypass=false)' }
)

$failures = @()

foreach ($cell in $matrix) {
    Write-Host ""
    Write-Host "[matrix] $($cell.Label)" -ForegroundColor Cyan
    & flutter test test/core/config/environment_config_test.dart `
        --no-pub `
        --dart-define=ENV=$($cell.Env) `
        --dart-define=SKIP_MFA_DEV=$($cell.Skip)
    if ($LASTEXITCODE -ne 0) {
        $failures += $cell.Label
        Write-Host "[matrix] FAIL: $($cell.Label)" -ForegroundColor Red
    } else {
        Write-Host "[matrix] PASS: $($cell.Label)" -ForegroundColor Green
    }
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Matrix FAILED ($($failures.Count)/$($matrix.Count)):" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "Matrix PASSED ($($matrix.Count)/$($matrix.Count))" -ForegroundColor Green
    exit 0
}
