import '_sla_justification_manager_test_helpers.dart';

/// Malformed-input and boundary-condition behavior for [SLAJustificationManager]:
/// absent or ill-formed evidence hashes, count mismatches, and field-length
/// boundaries. Distinct from active tampering (see forensic_integrity suite) —
/// these are rejections of input that never had valid shape.
void main() {
  setUpAll(registerJustificationFallbacks);

  late JustificationTestHarness h;
  setUp(() => h = JustificationTestHarness.create());

  group('CX05-INV-23 — Evidence Sealing (malformed input)', () {
    test('REJECTS submission without evidence hashes', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final command = buildCommand(evidenceHashes: []);

      expect(
        () => h.manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Evidence required'),
          ),
        ),
      );
    });

    test('REJECTS when evidence URL count mismatches hash count', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final command = buildCommand(
        evidenceUrls: [
          'https://storage.supabase.co/photo1.jpg',
          'https://storage.supabase.co/photo2.jpg',
        ],
        evidenceHashes: [validHash],
      );

      expect(
        () => h.manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('URL count must match hash count'),
              contains('CX05-INV-23'),
            ),
          ),
        ),
      );
    });

    test('REJECTS invalid SHA-256 hash (wrong length)', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final command = buildCommand(evidenceHashes: ['abc123']);

      expect(
        () => h.manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Invalid SHA-256 hash'),
          ),
        ),
      );
    });

    test('REJECTS invalid SHA-256 hash (non-hex characters)', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final invalidHash = 'g' * 64;
      final command = buildCommand(evidenceHashes: [invalidHash]);

      expect(
        () => h.manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Invalid SHA-256 hash'),
          ),
        ),
      );
    });
  });

  group('Resolution Notes Validation', () {
    test('reject with short resolution notes throws DomainException', () async {
      expect(
        () => h.manager.rejectJustification(
          justificationId: 'j-3',
          organizationId: 'org-1',
          reviewerId: 'gestor-1',
          callerRole: UserRole.admin,
          resolutionNotes: 'Short',
        ),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('at least 10 characters'),
          ),
        ),
      );
    });
  });

  group('Description Validation', () {
    test('REJECTS description shorter than 10 characters', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final command = buildCommand(description: 'Too short');

      expect(
        () => h.manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('at least 10 characters'),
          ),
        ),
      );
    });

    test('ACCEPTS description with exactly 10 characters', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final command = buildCommand(description: 'Exatamente');

      final result = await h.manager.submitJustification(command);
      expect(result.description, 'Exatamente');
    });
  });

  group('Category Validation', () {
    test('REJECTS invalid category string', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final command = buildCommand(category: 'INEXISTENTE');

      expect(
        () => h.manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Invalid justification category'),
          ),
        ),
      );
    });
  });
}
