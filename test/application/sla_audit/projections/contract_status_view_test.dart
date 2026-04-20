import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';

void main() {
  group('ContractStatusView Coverage', () {
    test('ContractStatusView.label', () {
      expect(ContractStatusView.draft.label, 'RASCUNHO');
      expect(
        ContractStatusView.awaitingContractorAcceptance.label,
        'AGUARDANDO ACEITE',
      );
      expect(ContractStatusView.active.label, 'ATIVO');
      expect(ContractStatusView.closed.label, 'ENCERRADO');
    });
  });
}
