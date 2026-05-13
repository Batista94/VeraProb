@echo off
SETLOCAL

:: ==============================================================================
:: VeraProb - Hermetic Golden Generator (Tier 1) - Pure Goldens Only
:: ==============================================================================

SET IMAGE_NAME=veraprob-test-env
SET DOCKERFILE_PATH=scripts\docker\Dockerfile.test

:: Definimos os arquivos especificos que contem Goldens
SET TEST_FILES=test/features/super_admin/presentation/screens/tenant_list_panel_test.dart ^
test/features/super_admin/presentation/screens/super_admin_audit_log_screen_test.dart ^
test/features/super_admin/presentation/widgets/impersonation_banner_test.dart

echo Gerenciando ambiente esteril (Build local)...

:: Verifica se a imagem existe
docker image inspect %IMAGE_NAME% >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Imagem nao encontrada. Construindo pela primeira vez...
    docker build -t %IMAGE_NAME% -f %DOCKERFILE_PATH% .
)

echo Gerando Goldens em ambiente Linux (Exclusivamente imagens)...

:: Usamos o filtro --name=[Gg]olden para garantir que apenas os goldenTests sejam executados,
:: ignorando testes de acessibilidade ou logica que possam falhar no container.
docker run --rm ^
  -v "%cd%":/app ^
  -v /app/.dart_tool ^
  -v /app/build ^
  -w /app ^
  %IMAGE_NAME% ^
  bash -c "flutter pub get && flutter test --update-goldens --name=[Gg]olden %TEST_FILES%"

if %ERRORLEVEL% NEQ 0 (
    echo Erro na geracao dos goldens.
    exit /b %ERRORLEVEL%
)

echo Goldens atualizados com sucesso via ambiente Linux!
