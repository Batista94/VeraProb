import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/shared/evidence_url_service.dart';
import 'package:veraprob/infrastructure/shared/trip_repository_impl.dart';
import 'package:veraprob/application/shared/app_types.dart';

final evidenceUrlServiceProvider = Provider<EvidenceUrlService>((ref) {
  return const EvidenceUrlService();
});

// Deterministic time provider — injects IDateTimeProvider for testability.
final dateTimeProviderProvider = Provider<IDateTimeProvider>(
  (ref) => BrazilDateTimeProvider(),
);

final tripRepositoryProvider = Provider<ITripRepository>((ref) {
  return TripRepositoryImpl(
    ref.watch(supabaseClientProvider),
    ref.watch(dateTimeProviderProvider),
  );
});

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);
