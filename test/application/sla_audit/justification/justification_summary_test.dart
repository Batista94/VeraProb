import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/justification/justification_summary.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  Map<String, dynamic> row({
    String id = 'just-1',
    String status = 'PENDING',
    String? contractId = 'contract-123',
    String? setId = 'SET-9',
    String? category = 'mechanical',
    String? description = 'Pane mecânica',
    String? createdAt = '2026-04-20T10:00:00Z',
    String? reviewedBy,
    String? reviewedAt,
  }) {
    return {
      'id': id,
      'status': status,
      'contract_id': contractId,
      'set_id': setId,
      'category': category,
      'description': description,
      'created_at_utc': createdAt,
      'reviewed_by_user_id': reviewedBy,
      'reviewed_at_utc': reviewedAt,
    };
  }

  group('JustificationSummary.fromRealtimeRow', () {
    test('maps every field from a complete row', () {
      final s = JustificationSummary.fromRealtimeRow(
        row(reviewedBy: 'admin-7', reviewedAt: '2026-04-21T08:30:00Z'),
      );

      expect(s.id, 'just-1');
      expect(s.status, JustificationStatus.pending);
      expect(s.contractId, 'contract-123');
      expect(s.setId, 'SET-9');
      expect(s.category, 'mechanical');
      expect(s.description, 'Pane mecânica');
      expect(s.reviewedByUserId, 'admin-7');
    });

    test('parses timestamps as UTC (INV-6)', () {
      final s = JustificationSummary.fromRealtimeRow(row());
      expect(s.createdAtUtc, DateTime.utc(2026, 4, 20, 10));
      expect(s.createdAtUtc!.isUtc, isTrue);
    });

    test('keeps nullable columns null when absent', () {
      final s = JustificationSummary.fromRealtimeRow(
        row(
          contractId: null,
          setId: null,
          category: null,
          description: null,
          createdAt: null,
        ),
      );
      expect(s.contractId, isNull);
      expect(s.setId, isNull);
      expect(s.category, isNull);
      expect(s.description, isNull);
      expect(s.createdAtUtc, isNull);
      expect(s.reviewedAtUtc, isNull);
    });

    test('throws on an unknown status — zero-trust, no silent mis-bucket', () {
      expect(
        () => JustificationSummary.fromRealtimeRow(row(status: 'pending')),
        throwsA(isA<IntegrityException>()),
      );
      expect(
        () => JustificationSummary.fromRealtimeRow(row(status: 'GARBAGE')),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  group('derived getters', () {
    JustificationSummary withCategory(String? c) =>
        JustificationSummary.fromRealtimeRow(row(category: c));

    test('isPending reflects status', () {
      expect(withCategory('traffic').isPending, isTrue);
      expect(
        JustificationSummary.fromRealtimeRow(row(status: 'APPROVED')).isPending,
        isFalse,
      );
    });

    test('categoryLabel maps every known category to Portuguese', () {
      expect(withCategory('mechanical').categoryLabel, 'Mecânico');
      expect(withCategory('force_majeure').categoryLabel, 'Força Maior');
      expect(withCategory('traffic').categoryLabel, 'Trânsito');
      expect(withCategory('route_deviation').categoryLabel, 'Desvio de Rota');
      expect(withCategory('communication').categoryLabel, 'Comunicação');
    });

    test('categoryLabel falls back to Outro for unknown/null', () {
      expect(withCategory('quantum').categoryLabel, 'Outro');
      expect(withCategory(null).categoryLabel, 'Outro');
    });
  });

  test('value equality holds for identical rows (Equatable)', () {
    expect(
      JustificationSummary.fromRealtimeRow(row()),
      equals(JustificationSummary.fromRealtimeRow(row())),
    );
  });
}
