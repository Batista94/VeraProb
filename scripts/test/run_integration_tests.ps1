param (
    [string]$SupabaseUrl = "http://127.0.0.1:54321",
    [string]$SupabaseKey = ""
)

$files = Get-ChildItem -Path "test/integration" -Recurse -Filter "*_test.dart" | Where-Object { $_.FullName -notmatch '[\\/]e2e[\\/]' }
$filePaths = $files | ForEach-Object { $_.FullName }

if ($filePaths.Count -eq 0) {
    Write-Host "Nenhum arquivo de teste de integração (não-E2E) encontrado." -ForegroundColor Yellow
    exit 0
}

Write-Host "Encontrados $($filePaths.Count) arquivos de teste de integração não-E2E." -ForegroundColor DarkCyan

$argsList = @("test", "-j", "1")
foreach ($path in $filePaths) {
    $argsList += $path
}
$argsList += "--dart-define=SKIP_MFA_DEV=true"
$argsList += "--dart-define=ENV=dev"
$argsList += "--dart-define=SUPABASE_URL=$SupabaseUrl"
$argsList += "--dart-define=SUPABASE_KEY=$SupabaseKey"

Write-Host "Executando flutter test..." -ForegroundColor Cyan
$process = Start-Process -FilePath "flutter" -ArgumentList $argsList -NoNewWindow -Wait -PassThru
exit $process.ExitCode
