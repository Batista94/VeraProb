import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/shared/security_context.dart';

void main() {
  group('SecurityContext', () {
    test('creates with required fields only', () {
      const ctx = SecurityContext(
        correlationId: '550e8400-e29b-41d4-a716-446655440000',
        edgeFunction: 'create_contract',
        requestIp: '192.168.1.1',
      );

      expect(ctx.correlationId, '550e8400-e29b-41d4-a716-446655440000');
      expect(ctx.edgeFunction, 'create_contract');
      expect(ctx.requestIp, '192.168.1.1');
      expect(ctx.rawPayloadId, isNull);
      expect(ctx.canonicalFactId, isNull);
      expect(ctx.payloadHash, isNull);
    });

    test('creates with all fields', () {
      const ctx = SecurityContext(
        correlationId: '550e8400-e29b-41d4-a716-446655440000',
        edgeFunction: 'ingest-sascar',
        rawPayloadId: 'raw_payload_abc123',
        canonicalFactId: 'fact_def456',
        requestIp: '10.0.0.1',
        payloadHash: 'a1b2c3d4e5f6',
      );

      expect(ctx.correlationId, '550e8400-e29b-41d4-a716-446655440000');
      expect(ctx.edgeFunction, 'ingest-sascar');
      expect(ctx.rawPayloadId, 'raw_payload_abc123');
      expect(ctx.canonicalFactId, 'fact_def456');
      expect(ctx.requestIp, '10.0.0.1');
      expect(ctx.payloadHash, 'a1b2c3d4e5f6');
    });

    test('toSentryTags returns all tags as map', () {
      const ctx = SecurityContext(
        correlationId: 'corr-123',
        edgeFunction: 'test_fn',
        requestIp: '1.2.3.4',
        payloadHash: 'sha256hash',
      );

      final tags = ctx.toSentryTags();

      expect(tags['correlation_id'], 'corr-123');
      expect(tags['edge_function'], 'test_fn');
      expect(tags['request_ip'], '1.2.3.4');
      expect(tags['payload_hash'], 'sha256hash');
    });

    test('toSentryTags omits null payloadHash', () {
      const ctx = SecurityContext(
        correlationId: 'corr-123',
        edgeFunction: 'test_fn',
        requestIp: '1.2.3.4',
      );

      final tags = ctx.toSentryTags();

      expect(tags['correlation_id'], 'corr-123');
      expect(tags.containsKey('payload_hash'), isFalse);
    });

    test('toSentryContext returns full context map', () {
      const ctx = SecurityContext(
        correlationId: 'corr-123',
        edgeFunction: 'test_fn',
        rawPayloadId: 'raw_123',
        canonicalFactId: 'fact_456',
        requestIp: '1.2.3.4',
        payloadHash: 'sha256hash',
      );

      final context = ctx.toSentryContext();

      expect(context['correlationId'], 'corr-123');
      expect(context['edgeFunction'], 'test_fn');
      expect(context['rawPayloadId'], 'raw_123');
      expect(context['canonicalFactId'], 'fact_456');
      expect(context['requestIp'], '1.2.3.4');
      expect(context['payloadHash'], 'sha256hash');
    });

    // ── Branch coverage for toSentryTags() optional fields ──────────────────

    test('toSentryTags includes rawPayloadId when set, omits when null', () {
      const withRaw = SecurityContext(
        correlationId: 'corr-1',
        edgeFunction: 'fn',
        requestIp: '1.1.1.1',
        rawPayloadId: 'raw-abc',
      );
      final tagsWith = withRaw.toSentryTags();
      expect(tagsWith['raw_payload_id'], 'raw-abc');
      expect(tagsWith.containsKey('canonical_fact_id'), isFalse);

      const withoutRaw = SecurityContext(
        correlationId: 'corr-1',
        edgeFunction: 'fn',
        requestIp: '1.1.1.1',
      );
      final tagsWithout = withoutRaw.toSentryTags();
      expect(tagsWithout.containsKey('raw_payload_id'), isFalse);
    });

    test('toSentryTags includes canonicalFactId when set, omits when null', () {
      const withFact = SecurityContext(
        correlationId: 'corr-2',
        edgeFunction: 'fn',
        requestIp: '2.2.2.2',
        canonicalFactId: 'fact-xyz',
      );
      final tagsWith = withFact.toSentryTags();
      expect(tagsWith['canonical_fact_id'], 'fact-xyz');
      expect(tagsWith.containsKey('raw_payload_id'), isFalse);

      const withoutFact = SecurityContext(
        correlationId: 'corr-2',
        edgeFunction: 'fn',
        requestIp: '2.2.2.2',
      );
      final tagsWithout = withoutFact.toSentryTags();
      expect(tagsWithout.containsKey('canonical_fact_id'), isFalse);
    });

    test('toSentryContext exposes null optional fields as null entries', () {
      // INV-1 note: org/role enforcement is at the Use Case layer, not here.
      // This DTO is a pure observability carrier — no business invariants.
      const ctx = SecurityContext(
        correlationId: 'corr-null',
        edgeFunction: 'fn-null',
        requestIp: '0.0.0.0',
      );

      final context = ctx.toSentryContext();

      expect(context['correlationId'], 'corr-null');
      expect(context['edgeFunction'], 'fn-null');
      expect(context['requestIp'], '0.0.0.0');
      expect(context.containsKey('rawPayloadId'), isTrue);
      expect(context['rawPayloadId'], isNull);
      expect(context.containsKey('canonicalFactId'), isTrue);
      expect(context['canonicalFactId'], isNull);
      expect(context.containsKey('payloadHash'), isTrue);
      expect(context['payloadHash'], isNull);
    });
  });
}
