import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/reporting/generate_forensic_dossier_handler.dart';
import 'package:veraprob/domain/reporting/i_forensic_pdf_generator.dart';
import 'package:veraprob/domain/reporting/i_pdf_dossier_log_repository.dart';
import 'package:veraprob/domain/reporting/i_static_map_service.dart';
import 'package:veraprob/infrastructure/reporting/maptiler_static_map_service.dart';
import 'package:veraprob/infrastructure/reporting/pdf_dossier_generator.dart';
import 'package:veraprob/infrastructure/reporting/postgres_pdf_dossier_log_repository.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/contract_providers.dart';

// ── Infrastructure adapters ────────────────────────────────────────────────

final staticMapServiceProvider = Provider<IStaticMapService>(
  (_) => MapTilerStaticMapService(),
);

final pdfDossierLogRepositoryProvider = Provider<IPdfDossierLogRepository>(
  (ref) => PostgresPdfDossierLogRepository(ref.watch(supabaseClientProvider)),
);

final forensicPdfGeneratorProvider = Provider<IForensicPdfGenerator>(
  (_) => PdfDossierGenerator(),
);

// ── Application handler ────────────────────────────────────────────────────

final generateForensicDossierHandlerProvider =
    Provider<GenerateForensicDossierHandler>(
      (ref) => GenerateForensicDossierHandler(
        ref.watch(staticMapServiceProvider),
        ref.watch(forensicPdfGeneratorProvider),
        ref.watch(pdfDossierLogRepositoryProvider),
        ref.watch(tenantValidationServiceProvider),
      ),
    );
