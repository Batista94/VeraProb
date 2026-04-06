import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/sla_audit/reporting_service.dart';
import 'package:veraprob/application/sla_audit/export_service.dart';
import 'package:veraprob/state/providers/sla_financial_providers.dart';

final reportingServiceProvider = Provider<ReportingService>((ref) {
  final snapshotRepo = ref.watch(financialSnapshotRepositoryProvider);
  return ReportingService(snapshotRepo: snapshotRepo);
});

final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService();
});
