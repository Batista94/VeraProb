import 'dart:io';

void main() {
  final dir = Directory('test');
  if (!dir.existsSync()) return;

  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    var content = file.readAsStringSync();
    var original = content;

    content = content.replaceAll(
      'ContractualExecutionState.create(',
      "ContractualExecutionState.create(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'PlanDeclaration.create(',
      "PlanDeclaration.create(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'ContractualExecutionState.reconstitute(',
      "ContractualExecutionState.reconstitute(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'PlanDeclaration.reconstitute(',
      "PlanDeclaration.reconstitute(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'ExecutionBoundEvent(',
      "ExecutionBoundEvent(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'NoShowDeclaredEvent(',
      "NoShowDeclaredEvent(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'EvidenceGapDeclaredEvent(',
      "EvidenceGapDeclaredEvent(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'OccurrenceRegisteredEvidence(',
      "OccurrenceRegisteredEvidence(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'TripInterruptedEvidence(',
      "TripInterruptedEvidence(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'TripCancelledEvidence(',
      "TripCancelledEvidence(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'DeclareContractualPlanCommand(',
      "DeclareContractualPlanCommand(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'ContractualPlanDeclaredEvent(',
      "ContractualPlanDeclaredEvent(organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      'SlaLedgerEntry(',
      "SlaLedgerEntry(organizationId: 'org-1', ",
    );

    if (content != original) {
      file.writeAsStringSync(content);
      print('Updated \${file.path}');
    }
  }
}
