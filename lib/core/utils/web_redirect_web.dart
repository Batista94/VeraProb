import 'package:web/web.dart' as web;

/// Implementação web para redirecionar a janela do navegador.
void replaceWindowLocation(String url) {
  web.window.location.replace(url);
}
