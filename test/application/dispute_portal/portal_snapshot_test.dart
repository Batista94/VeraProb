import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';

void main() {
  group('PortalEvidenceItem.fromJson', () {
    test('maps fields and normalizes attached_at to UTC', () {
      final e = PortalEvidenceItem.fromJson({
        'id': 'ev-1',
        'file_name': 'doc.pdf',
        'mime_type': 'application/pdf',
        'file_size_bytes': 2048,
        'sha256_hash': 'b' * 64,
        'verification_status': 'VERIFIED',
        'attached_at': '2026-06-02T10:00:00Z',
      });
      expect(e.fileName, 'doc.pdf');
      expect(e.fileSizeBytes, 2048);
      expect(e.verificationStatus, 'VERIFIED');
      expect(e.attachedAtUtc.isUtc, isTrue);
    });

    test('applies safe defaults for missing optional fields', () {
      final e = PortalEvidenceItem.fromJson({
        'id': 'ev-2',
        'attached_at': '2026-06-02T10:00:00Z',
      });
      expect(e.fileName, 'evidence');
      expect(e.mimeType, 'application/octet-stream');
      expect(e.fileSizeBytes, 0);
      expect(e.verificationStatus, 'PENDING');
    });
  });

  group('PortalSnapshot.fromJson', () {
    test('projects summary + verdict + evidence', () {
      final s = PortalSnapshot.fromJson({
        'dispute_summary': {
          'status': 'disputed',
          'disputed_at': '2026-06-01T00:00:00Z',
          'resolution_due_at': '2026-06-08T00:00:00Z',
        },
        'verdict_summary': {
          'rule_type': 'Atraso',
          'description': 'SLA excedido',
        },
        'evidence': [
          {'id': 'ev-1', 'attached_at': '2026-06-02T10:00:00Z'},
        ],
        'snapshot_hash': 'a' * 64,
      });
      expect(s.status, 'disputed');
      expect(s.isDisputed, isTrue);
      expect(s.isApplied, isFalse);
      expect(s.ruleType, 'Atraso');
      expect(s.evidence, hasLength(1));
      expect(s.snapshotHash, 'a' * 64);
    });

    test('defaults to unknown status + empty evidence when absent', () {
      final s = PortalSnapshot.fromJson({});
      expect(s.status, 'unknown');
      expect(s.isApplied, isFalse);
      expect(s.isDisputed, isFalse);
      expect(s.evidence, isEmpty);
      expect(s.snapshotHash, '');
    });

    test('isApplied true only for applied status', () {
      final s = PortalSnapshot.fromJson({
        'dispute_summary': {'status': 'applied'},
      });
      expect(s.isApplied, isTrue);
      expect(s.isDisputed, isFalse);
    });
  });

  test('PortalDisputeException carries a domain message', () {
    const e = PortalDisputeException('Link inválido ou expirado.');
    expect(e.message, 'Link inválido ou expirado.');
    expect(e.toString(), contains('Link inválido'));
  });
}
