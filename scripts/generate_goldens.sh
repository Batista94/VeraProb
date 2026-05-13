#!/bin/bash
set -e

# ==============================================================================
# VeraProb - Hermetic Golden Generator (Tier 1) - Pure Goldens Only
# ==============================================================================

IMAGE_NAME="veraprob-test-env"
DOCKERFILE_PATH="scripts/docker/Dockerfile.test"

# Definimos os arquivos especificos que contem Goldens
TEST_FILES="test/features/super_admin/presentation/screens/tenant_list_panel_test.dart \
test/features/super_admin/presentation/screens/super_admin_audit_log_screen_test.dart \
test/features/super_admin/presentation/widgets/impersonation_banner_test.dart"

echo "Gerenciando ambiente esteril (Build local)..."

# Verifica se a imagem existe
if ! docker image inspect $IMAGE_NAME >/dev/null 2>&1; then
    echo "Imagem nao encontrada. Construindo pela primeira vez..."
    docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH .
fi

echo "Gerando Goldens em ambiente Linux (Exclusivamente imagens)..."

# Usamos volumes anonimos para isolar .dart_tool e build, evitando conflitos com o host.
docker run --rm \
  -v "$(pwd)":/app \
  -v /app/.dart_tool \
  -v /app/build \
  -w /app \
  $IMAGE_NAME \
  bash -c "flutter pub get && flutter test --update-goldens --name=[Gg]olden $TEST_FILES"

echo "Goldens atualizados com sucesso via ambiente Linux!"
