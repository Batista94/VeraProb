// Webhook Providers — P1 (Reveal-Once).
//
// Padrão: Provider manual (sem generator), autoDispose para segredo.
// INV-28: webhookSecretRevealProvider é o ÚNICO holder do plaintext em RAM.
// Destruição em camadas:
//   1. autoDispose — modal é o único listener; Navigator.pop → dispose → GC.
//   2. invalidate explícito em _close() (belt-and-suspenders).
//   3. lifecycle scrub via WidgetsBindingObserver no modal (Passo 6).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/webhooks/i_webhook_repository.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_log_view.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';
import 'package:veraprob/application/webhooks/webhook_endpoint_view.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/webhooks/supabase_webhook_repository.dart';

// ── Repository Provider ──────────────────────────────────────────────────────

/// Fornece a implementação concreta de IWebhookRepository.
/// INV-13: features/ importam apenas IWebhookRepository (application),
/// nunca SupabaseWebhookRepository diretamente.
final webhookRepositoryProvider = Provider<IWebhookRepository>((ref) {
  return SupabaseWebhookRepository(ref.watch(supabaseClientProvider));
});

// ── RevealState ──────────────────────────────────────────────────────────────

/// Estado efêmero do modal Reveal-Once.
///
/// INV-28: secretHex existe APENAS durante o modal aberto.
/// keepAlive = PROIBIDO neste provider.
class RevealState {
  final String? secretHex;
  final int? version;
  final bool loading;
  final String? error;

  const RevealState({
    this.secretHex,
    this.version,
    this.loading = false,
    this.error,
  });

  RevealState copyWith({
    String? secretHex,
    int? version,
    bool? loading,
    String? error,
    bool clearSecret = false,
    bool clearError = false,
  }) {
    return RevealState(
      secretHex: clearSecret ? null : (secretHex ?? this.secretHex),
      version: clearSecret ? null : (version ?? this.version),
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

/// Notifier autoDispose para o segredo de assinatura.
///
/// autoDispose = modal é o único listener. Ao fechar (Navigator.pop) o widget
/// desmonta, o listener cai, o provider é destruído → GC recupera o plaintext.
class WebhookSecretRevealNotifier extends Notifier<RevealState> {
  @override
  RevealState build() => const RevealState();

  /// Injeta o segredo após retorno bem-sucedido da edge fn.
  /// Chamado por RevealSecretModal logo após provision/rotate.
  void setRevealed(String secretHex, int version) {
    state = RevealState(secretHex: secretHex, version: version);
  }

  /// Anula o segredo da RAM explicitamente (belt-and-suspenders).
  /// Chamado em _close() ANTES de Navigator.pop e por lifecycle scrub.
  void scrub() {
    state = const RevealState();
  }

  void setLoading() {
    state = state.copyWith(loading: true, clearError: true);
  }

  void setError(String message) {
    state = state.copyWith(loading: false, error: message, clearSecret: true);
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

/// Único holder do plaintext do segredo de assinatura.
///
/// INV-28: autoDispose garante que o segredo é elegível a GC quando o modal
/// fecha. Nenhum outro provider deve watch/read este provider fora do modal.
final webhookSecretRevealProvider =
    NotifierProvider.autoDispose<WebhookSecretRevealNotifier, RevealState>(
      WebhookSecretRevealNotifier.new,
    );

// ── P2: Webhook Management Providers ─────────────────────────────────────────

class SelectedEndpointIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

/// Endpoint atualmente selecionado no Master-Detail.
final selectedEndpointIdProvider =
    NotifierProvider<SelectedEndpointIdNotifier, String?>(
      SelectedEndpointIdNotifier.new,
    );

class DeliveryLogFilterNotifier extends Notifier<WebhookDeliveryStatusView?> {
  @override
  WebhookDeliveryStatusView? build() => null;
  void setFilter(WebhookDeliveryStatusView? filter) => state = filter;
}

/// Filtro de status de entrega selecionado no Detail.
final deliveryLogFilterProvider =
    NotifierProvider<DeliveryLogFilterNotifier, WebhookDeliveryStatusView?>(
      DeliveryLogFilterNotifier.new,
    );

/// Lista de endpoints com health view rollup.
final webhookEndpointHealthProvider =
    FutureProvider.autoDispose<List<WebhookEndpointView>>((ref) async {
      final repo = ref.watch(webhookRepositoryProvider);
      return repo.findEndpointHealth();
    });

/// Stream de logs de entrega para o endpoint selecionado.
final deliveryLogStreamProvider = StreamProvider.autoDispose
    .family<List<WebhookDeliveryLogView>, String>((ref, endpointId) {
      final repo = ref.watch(webhookRepositoryProvider);
      return repo.watchDeliveryLogs(endpointId);
    });
