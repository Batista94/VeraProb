import 'dart:js_interop';

@JS('initPosthog')
external void _jsInitPosthog(
  JSString apiKey,
  JSString apiHost,
  JSBoolean enableSessionReplay,
);

/// Inicializa o PostHog injetando o script JS no ambiente web.
void initPosthogWeb(String apiKey, String apiHost, bool enableSessionReplay) {
  _jsInitPosthog(apiKey.toJS, apiHost.toJS, enableSessionReplay.toJS);
}
