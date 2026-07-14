import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/domain/legal/i_legal_consent_repository.dart';
import 'package:veraprob/domain/legal/legal_consent_status.dart';
import 'package:veraprob/infrastructure/config/environment.dart';
import 'package:veraprob/infrastructure/legal/supabase_legal_consent_repository.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/provider_timeout.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:flutter/foundation.dart';

/// DI for the Legal Gate consent port.
final legalConsentRepositoryProvider = Provider<ILegalConsentRepository>((ref) {
  return SupabaseLegalConsentRepository(ref.watch(supabaseClientProvider));
});

/// Notifies [GoRouter] when consent status changes (accept / invalidate).
class ConsentRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final consentRefreshNotifierProvider = Provider<ConsentRefreshNotifier>((ref) {
  final notifier = ConsentRefreshNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// Session-scoped consent status — one RPC per user session.
///
/// Rebuilds when [currentOperatorIdProvider] changes (login/logout).
/// Dev/E2E bypass via [EnvironmentConfig.skipLgpdConsentDev].
final legalConsentStatusProvider = FutureProvider<LegalConsentStatus>((
  ref,
) async {
  final userId = ref.watch(currentOperatorIdProvider);
  if (userId == null) {
    return const LegalConsentStatus(state: LegalConsentState.current);
  }

  if (EnvironmentConfig.skipLgpdConsentDev) {
    return const LegalConsentStatus(state: LegalConsentState.current);
  }

  final repo = ref.watch(legalConsentRepositoryProvider);
  return repo.getConsentStatus().withProviderTimeout();
});
