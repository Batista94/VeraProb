// Adversarial tests for TelegramEvidenceUpload + _evidenceFromRow parsing.
// Goal: prove that malformed PostgREST responses don't crash the app.

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_evidence_upload.dart';

/// Mirrors _evidenceFromRow from postgres_telegram_repository.dart.
/// Extracted here to test the parsing logic in isolation without Supabase.
TelegramEvidenceUpload evidenceFromRow(Map<String, dynamic> row) {
  final catList = row['telegram_evidence_categories'] as List<dynamic>?;
  final category = (catList != null && catList.isNotEmpty)
      ? catList[0]['category'] as String?
      : null;

  return TelegramEvidenceUpload(
    id: row['id'] as String,
    organizationId: row['organization_id'] as String,
    driverId: row['driver_id'] as String,
    chatId: row['chat_id'] as int,
    telegramMessageId: row['telegram_message_id'] as int,
    fileName: row['file_name'] as String,
    forensicHash: row['forensic_hash'] as String,
    storagePath: row['storage_path'] as String,
    source: row['source'] as String,
    linkedSetId: row['linked_set_id'] as String?,
    uploadedAtUtc: DateTime.parse(row['uploaded_at_utc'] as String).toUtc(),
    telegramMessageDate: DateTime.parse(
      row['telegram_message_date'] as String,
    ).toUtc(),
    requiresManualLink: row['requires_manual_link'] as bool,
    category: category,
    mimeType: row['mime_type'] as String?,
  );
}

Map<String, dynamic> _baseRow({List<dynamic>? categories, String? mimeType}) =>
    {
      'id': 'ev-001',
      'organization_id': 'org-1',
      'driver_id': 'drv-1',
      'chat_id': 12345,
      'telegram_message_id': 99,
      'file_name': 'photo.jpg',
      'forensic_hash': 'abc123def456',
      'storage_path': '/evidence/photo.jpg',
      'source': 'telegram',
      'linked_set_id': null,
      'uploaded_at_utc': '2026-04-22T12:00:00Z',
      'telegram_message_date': '2026-04-22T11:55:00Z',
      'requires_manual_link': true,
      'telegram_evidence_links': <dynamic>[],
      'telegram_evidence_categories': categories,
      'mime_type': mimeType,
    };

void main() {
  // =========================================================================
  // _evidenceFromRow — PostgREST embedding edge cases
  // =========================================================================
  group('_evidenceFromRow — PostgREST embedding parsing', () {
    test('null categories array → category is null', () {
      final e = evidenceFromRow(_baseRow(categories: null));
      expect(e.category, isNull);
    });

    test('empty categories array → category is null', () {
      final e = evidenceFromRow(_baseRow(categories: []));
      expect(e.category, isNull);
    });

    test('valid single-element array → extracts category', () {
      final e = evidenceFromRow(
        _baseRow(
          categories: [
            {'category': 'incidente'},
          ],
        ),
      );
      expect(e.category, 'incidente');
    });

    test('category value is null inside map → category is null', () {
      final e = evidenceFromRow(
        _baseRow(
          categories: [
            {'category': null},
          ],
        ),
      );
      expect(e.category, isNull);
    });

    test('first element is null → throws (production data corruption)', () {
      // If PostgREST returns [null], catList[0]['category'] will throw NoSuchMethodError.
      // This test documents the failure mode — it SHOULD crash loudly, not silently.
      expect(
        () => evidenceFromRow(_baseRow(categories: [null])),
        throwsA(isA<NoSuchMethodError>()),
      );
    });

    test('category is int instead of String → throws TypeError', () {
      // DB corruption: category column somehow has an int.
      // as String? on an int throws TypeError — this is correct fail-fast behavior.
      expect(
        () => evidenceFromRow(
          _baseRow(
            categories: [
              {'category': 42},
            ],
          ),
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test(
      'map missing "category" key → category is null (Dart map returns null for absent key)',
      () {
        // PostgREST schema mismatch: embedding returns different columns.
        // Dart maps return null for missing keys, so `as String?` succeeds with null.
        final e = evidenceFromRow(
          _baseRow(
            categories: [
              {'wrong_key': 'val'},
            ],
          ),
        );
        expect(e.category, isNull);
      },
    );

    test('multiple elements in array → only first is used (UNIQUE FK)', () {
      // Should never happen due to UNIQUE constraint, but if it does:
      final e = evidenceFromRow(
        _baseRow(
          categories: [
            {'category': 'incidente'},
            {'category': 'doc'},
          ],
        ),
      );
      expect(e.category, 'incidente'); // First wins
    });
  });

  // =========================================================================
  // Equatable — category in equality contract
  // =========================================================================
  group('Equatable — category in equality contract', () {
    TelegramEvidenceUpload make({String? category}) => TelegramEvidenceUpload(
      id: 'ev-001',
      organizationId: 'org-1',
      driverId: 'drv-1',
      chatId: 12345,
      telegramMessageId: 99,
      fileName: 'photo.jpg',
      forensicHash: 'abc123',
      storagePath: '/evidence/photo.jpg',
      source: 'telegram',
      uploadedAtUtc: DateTime.utc(2026, 4, 22, 12),
      telegramMessageDate: DateTime.utc(2026, 4, 22, 11, 55),
      requiresManualLink: true,
      category: category,
    );

    test('same category → equal', () {
      expect(make(category: 'doc'), equals(make(category: 'doc')));
    });

    test('different category → NOT equal', () {
      expect(make(category: 'doc'), isNot(equals(make(category: 'oper'))));
    });

    test('null vs non-null → NOT equal', () {
      expect(make(category: null), isNot(equals(make(category: 'doc'))));
    });

    test('null vs null → equal', () {
      expect(make(category: null), equals(make(category: null)));
    });

    test('empty string vs null → NOT equal (distinct states)', () {
      // Empty string from DB corruption is NOT the same as "not yet tagged"
      expect(make(category: ''), isNot(equals(make(category: null))));
    });
  });

  // =========================================================================
  // isOrphan — boundary conditions
  // =========================================================================
  group('isOrphan — boundary conditions', () {
    TelegramEvidenceUpload make({bool manual = true, String? linked}) =>
        TelegramEvidenceUpload(
          id: 'ev-001',
          organizationId: 'org-1',
          driverId: 'drv-1',
          chatId: 12345,
          telegramMessageId: 99,
          fileName: 'photo.jpg',
          forensicHash: 'abc123',
          storagePath: '/evidence/photo.jpg',
          source: 'telegram',
          uploadedAtUtc: DateTime.utc(2026, 4, 22, 12),
          telegramMessageDate: DateTime.utc(2026, 4, 22, 11, 55),
          requiresManualLink: manual,
          linkedSetId: linked,
        );

    test('requiresManualLink=true + linkedSetId=null → orphan', () {
      expect(make(manual: true, linked: null).isOrphan, isTrue);
    });

    test(
      'requiresManualLink=true + linkedSetId="" → NOT orphan (empty is not null)',
      () {
        // Edge: empty string from DB is truthy for null check
        expect(make(manual: true, linked: '').isOrphan, isFalse);
      },
    );

    test('requiresManualLink=false + linkedSetId=null → NOT orphan', () {
      expect(make(manual: false, linked: null).isOrphan, isFalse);
    });

    test('requiresManualLink=true + linkedSetId=set-1 → NOT orphan', () {
      expect(make(manual: true, linked: 'set-1').isOrphan, isFalse);
    });
  });

  // =========================================================================
  // _evidenceFromRow — mime_type parsing
  // =========================================================================
  group('_evidenceFromRow — mime_type parsing', () {
    test('mime_type null → mimeType is null', () {
      final e = evidenceFromRow(_baseRow(mimeType: null));
      expect(e.mimeType, isNull);
    });

    test('mime_type "audio/ogg" → mimeType is audio/ogg', () {
      final e = evidenceFromRow(_baseRow(mimeType: 'audio/ogg'));
      expect(e.mimeType, 'audio/ogg');
    });

    test('mime_type "image/jpeg" → mimeType is image/jpeg', () {
      final e = evidenceFromRow(_baseRow(mimeType: 'image/jpeg'));
      expect(e.mimeType, 'image/jpeg');
    });

    test('mime_type as int → throws TypeError (fail-fast)', () {
      final row = _baseRow();
      row['mime_type'] = 42;
      expect(() => evidenceFromRow(row), throwsA(isA<TypeError>()));
    });
  });

  // =========================================================================
  // isAudio — adversarial boundary conditions
  // =========================================================================
  group('isAudio — adversarial', () {
    TelegramEvidenceUpload make({String? mimeType}) => TelegramEvidenceUpload(
      id: 'ev-001',
      organizationId: 'org-1',
      driverId: 'drv-1',
      chatId: 12345,
      telegramMessageId: 99,
      fileName: 'file.ogg',
      forensicHash: 'abc123',
      storagePath: '/evidence/file.ogg',
      source: 'telegram',
      uploadedAtUtc: DateTime.utc(2026, 4, 22, 12),
      telegramMessageDate: DateTime.utc(2026, 4, 22, 11, 55),
      requiresManualLink: false,
      mimeType: mimeType,
    );

    test('audio/ogg → isAudio true', () {
      expect(make(mimeType: 'audio/ogg').isAudio, isTrue);
    });

    test('audio/opus → isAudio true', () {
      expect(make(mimeType: 'audio/opus').isAudio, isTrue);
    });

    test('audio/ (bare prefix) → isAudio true', () {
      expect(make(mimeType: 'audio/').isAudio, isTrue);
    });

    test('image/jpeg → isAudio false', () {
      expect(make(mimeType: 'image/jpeg').isAudio, isFalse);
    });

    test('video/mp4 → isAudio false', () {
      expect(make(mimeType: 'video/mp4').isAudio, isFalse);
    });

    test('null → isAudio false', () {
      expect(make(mimeType: null).isAudio, isFalse);
    });

    test('empty string → isAudio false', () {
      expect(make(mimeType: '').isAudio, isFalse);
    });

    test('AUDIO/OGG (uppercase) → isAudio false (case sensitive)', () {
      // Webhook always writes lowercase — uppercase means data corruption
      expect(make(mimeType: 'AUDIO/OGG').isAudio, isFalse);
    });

    test('<script>alert(1)</script> → isAudio false, no crash', () {
      expect(make(mimeType: '<script>alert(1)</script>').isAudio, isFalse);
    });
  });

  // =========================================================================
  // Equatable — mimeType in equality contract
  // =========================================================================
  group('Equatable — mimeType in equality contract', () {
    TelegramEvidenceUpload make({String? mimeType}) => TelegramEvidenceUpload(
      id: 'ev-001',
      organizationId: 'org-1',
      driverId: 'drv-1',
      chatId: 12345,
      telegramMessageId: 99,
      fileName: 'photo.jpg',
      forensicHash: 'abc123',
      storagePath: '/evidence/photo.jpg',
      source: 'telegram',
      uploadedAtUtc: DateTime.utc(2026, 4, 22, 12),
      telegramMessageDate: DateTime.utc(2026, 4, 22, 11, 55),
      requiresManualLink: true,
      mimeType: mimeType,
    );

    test('same mimeType → equal', () {
      expect(make(mimeType: 'audio/ogg'), equals(make(mimeType: 'audio/ogg')));
    });

    test('different mimeType → NOT equal', () {
      expect(
        make(mimeType: 'audio/ogg'),
        isNot(equals(make(mimeType: 'image/jpeg'))),
      );
    });

    test('null vs non-null → NOT equal', () {
      expect(make(mimeType: null), isNot(equals(make(mimeType: 'audio/ogg'))));
    });

    test('null vs null → equal', () {
      expect(make(mimeType: null), equals(make(mimeType: null)));
    });
  });
}
