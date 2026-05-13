#!/bin/bash

# ==============================================================================
# VeraProb - Hermetic Golden Generator (Tier 1) - Pure Goldens Only
# ==============================================================================

set -e

IMAGE_NAME="veraprob-test-env"
DOCKERFILE_PATH="scripts/docker/Dockerfile.test"

# Arquivos específicos com Goldens
TEST_FILES="test/features/super_admin/presentation/screens/tenant_list_panel_test.dart \
test/features/super_admin/presentation/screens/super_admin_audit_log_screen_test.dart \
test/features/super_admin/presentation/widgets/impersonation_banner_test.dart"

echo "🚀 Garantindo ambiente estéril (Build local)..."

if [[ "$(docker images -q $IMAGE_NAME 2> /dev/null)" == "" ]]; then
  echo "📦 Imagem não encontrada. Construindo pela primeira vez..."
  docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH .
fi

echo "🧪 Gerando Goldens em ambiente Linux (Exclusivamente imagens)..."

docker run --rm \
  -v "$PWD":/app \
  -w /app \
  $IMAGE_NAME \
  bash -c "flutter pub get && flutter test --update-goldens --name=[Gg]olden $TEST_FILES"

echo "✅ Goldens atualizados com sucesso via ambiente Linux!"
