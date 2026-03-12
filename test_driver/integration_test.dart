// Ponto de entrada para `flutter drive` (headless CI / Chrome).
// Roteia para os testes em integration_test/.
//
// Uso:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/smoke_test.dart \
//     -d web-server \
//     --dart-define=SUPABASE_URL=... \
//     --dart-define=SUPABASE_KEY=...
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver();
