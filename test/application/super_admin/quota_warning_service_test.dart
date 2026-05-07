import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/super_admin/quota_warning_service.dart';
import 'package:veraprob/domain/admin/i_quota_alert_notifier.dart';
import 'package:veraprob/domain/admin/i_quota_alert_state_cache.dart';
import 'package:veraprob/domain/admin/quota_alert_context.dart';
import 'package:veraprob/domain/admin/quota_alert_payload.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────────

class _MockNotifier extends Mock implements IQuotaAlertNotifier {}

class _MockStateCache extends Mock implements IQuotaAlertStateCache {}

// ── Fixtures ───────────────────────────────────────────────────────────────────

const _orgAId = 'org-a-uuid';

QuotaAlertContext _ctx({
  String orgId = _orgAId,
  String orgName = 'Transportes Alfa Ltda',
  String resource = 'vehicles',
  int currentCount = 85,
  int maxAllowed = 100,
  List<String> adminEmails = const ['admin@orga.com'],
}) => QuotaAlertContext(
  orgId: orgId,
  orgName: orgName,
  resource: resource,
  currentCount: currentCount,
  maxAllowed: maxAllowed,
  adminEmails: adminEmails,
);

QuotaAlertPayload _fallbackPayload() => const QuotaAlertPayload(
  orgName: '',
  resource: '',
  usagePct: 0,
  threshold: 0,
  currentCount: 0,
  maxAllowed: 100,
  recipientEmails: [],
);

// ── Test setup helpers ─────────────────────────────────────────────────────────

void _stubCacheMiss(_MockStateCache cache) {
  when(
    () => cache.wasAlertSent(
      orgId: any(named: 'orgId'),
      resource: any(named: 'resource'),
      threshold: any(named: 'threshold'),
    ),
  ).thenAnswer((_) async => false);
  when(
    () => cache.markAlertSent(
      orgId: any(named: 'orgId'),
      resource: any(named: 'resource'),
      threshold: any(named: 'threshold'),
    ),
  ).thenAnswer((_) async {});
}

void _stubCacheHit(_MockStateCache cache) {
  when(
    () => cache.wasAlertSent(
      orgId: any(named: 'orgId'),
      resource: any(named: 'resource'),
      threshold: any(named: 'threshold'),
    ),
  ).thenAnswer((_) async => true);
}

void _stubNotifierOk(_MockNotifier notifier) {
  when(() => notifier.dispatch(any())).thenAnswer((_) async {});
}

// ── Suite ──────────────────────────────────────────────────────────────────────

void main() {
  late _MockNotifier notifier;
  late _MockStateCache stateCache;
  late QuotaWarningService service;

  setUp(() {
    notifier = _MockNotifier();
    stateCache = _MockStateCache();
    service = QuotaWarningService.notifierOnly(
      notifier: notifier,
      stateCache: stateCache,
    );
  });

  setUpAll(() {
    registerFallbackValue(_ctx());
    registerFallbackValue(_fallbackPayload());
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // C — CONFIDENTIALITY
  // ═══════════════════════════════════════════════════════════════════════════

  group('[C] Cross-Tenant Alert Isolation (INV-1)', () {
    test(
      'payload.recipientEmails contains only Org A admin — not Org B',
      () async {
        _stubCacheMiss(stateCache);
        _stubNotifierOk(notifier);

        await service.checkAndDispatchAlerts(
          _ctx(orgId: _orgAId, adminEmails: ['admin@orga.com']),
        );

        final captured = verify(() => notifier.dispatch(captureAny())).captured;
        expect(
          captured,
          isNotEmpty,
          reason: '85% must trigger at least one dispatch',
        );

        for (final raw in captured) {
          final p = raw as QuotaAlertPayload;
          expect(p.recipientEmails, equals(['admin@orga.com']));
          expect(p.recipientEmails, isNot(contains('admin@orgb.com')));
          expect(p.recipientEmails, isNot(contains('superadmin@veraprob.com')));
        }
      },
    );

    test('dispatch for Org A does not reach Org B admin list', () async {
      _stubCacheMiss(stateCache);
      _stubNotifierOk(notifier);

      const orgBAdmin = 'admin@orgb.com';

      await service.checkAndDispatchAlerts(
        _ctx(orgId: _orgAId, adminEmails: ['admin@orga.com']),
      );

      final captured = verify(() => notifier.dispatch(captureAny())).captured;
      for (final raw in captured) {
        final p = raw as QuotaAlertPayload;
        expect(p.recipientEmails, isNot(contains(orgBAdmin)));
      }
    });
  });

  group('[C] Payload Metadata Hygiene', () {
    test('payload.orgName is friendly name — no raw UUID', () async {
      _stubCacheMiss(stateCache);
      _stubNotifierOk(notifier);

      await service.checkAndDispatchAlerts(
        _ctx(
          orgId: 'abc-def-0000-0000-raw-uuid',
          orgName: 'Transportes Alfa Ltda',
        ),
      );

      final captured = verify(() => notifier.dispatch(captureAny())).captured;
      expect(captured, isNotEmpty);

      final uuidPattern = RegExp(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
        caseSensitive: false,
      );
      for (final raw in captured) {
        final p = raw as QuotaAlertPayload;
        expect(
          p.orgName,
          isNot(matches(uuidPattern)),
          reason: 'orgName must not expose raw UUID',
        );
        expect(p.orgName, equals('Transportes Alfa Ltda'));
      }
    });

    test(
      'payload has no stacktrace, orgId field, or internal DB reference',
      () async {
        _stubCacheMiss(stateCache);
        _stubNotifierOk(notifier);

        await service.checkAndDispatchAlerts(_ctx());

        final captured = verify(() => notifier.dispatch(captureAny())).captured;
        expect(captured, isNotEmpty);

        for (final raw in captured) {
          final p = raw as QuotaAlertPayload;
          expect(p.usagePct, greaterThanOrEqualTo(0));
          expect(p.threshold, greaterThan(0));
          expect(p.maxAllowed, greaterThan(0));
          expect(p.orgName, isNotEmpty);
          expect(p.resource, isNotEmpty);
        }
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // I — INTEGRITY
  // ═══════════════════════════════════════════════════════════════════════════

  group('[I] Math Resilience', () {
    test('over-limit usage (150/100) does not throw and dispatches', () async {
      _stubCacheMiss(stateCache);
      _stubNotifierOk(notifier);

      await expectLater(
        service.checkAndDispatchAlerts(
          _ctx(currentCount: 150, maxAllowed: 100),
        ),
        completes,
      );
    });

    test('usagePct is never negative on over-limit input', () async {
      _stubCacheMiss(stateCache);
      _stubNotifierOk(notifier);

      await service.checkAndDispatchAlerts(
        _ctx(currentCount: 150, maxAllowed: 100),
      );

      final captured = verify(() => notifier.dispatch(captureAny())).captured;
      expect(captured, isNotEmpty);
      for (final raw in captured) {
        final p = raw as QuotaAlertPayload;
        expect(
          p.usagePct,
          greaterThanOrEqualTo(0),
          reason: 'usagePct must not be negative',
        );
      }
    });

    test('zero maxAllowed does not throw DivisionByZeroError', () async {
      _stubCacheMiss(stateCache);
      when(() => notifier.dispatch(any())).thenAnswer((_) async {});

      await expectLater(
        service.checkAndDispatchAlerts(_ctx(currentCount: 0, maxAllowed: 0)),
        completes,
      );

      verifyNever(() => notifier.dispatch(any()));
    });

    test('zero maxAllowed with non-zero count does not throw', () async {
      _stubCacheMiss(stateCache);

      await expectLater(
        service.checkAndDispatchAlerts(_ctx(currentCount: 50, maxAllowed: 0)),
        completes,
      );
    });
  });

  group('[I] Anti-Spam Idempotency', () {
    test('10 calls at 80% threshold invoke notifier exactly once', () async {
      var sentCount = 0;

      when(
        () => stateCache.wasAlertSent(
          orgId: any(named: 'orgId'),
          resource: any(named: 'resource'),
          threshold: any(named: 'threshold'),
        ),
      ).thenAnswer((_) async => sentCount > 0);
      when(
        () => stateCache.markAlertSent(
          orgId: any(named: 'orgId'),
          resource: any(named: 'resource'),
          threshold: any(named: 'threshold'),
        ),
      ).thenAnswer((_) async {
        sentCount++;
      });
      _stubNotifierOk(notifier);

      for (var i = 0; i < 10; i++) {
        await service.checkAndDispatchAlerts(
          _ctx(currentCount: 80, maxAllowed: 100),
        );
      }

      verify(() => notifier.dispatch(any())).called(1);
    });

    test('stateCache consulted on every call to gate dispatch', () async {
      _stubCacheHit(stateCache);

      await service.checkAndDispatchAlerts(
        _ctx(currentCount: 80, maxAllowed: 100),
      );

      verifyNever(() => notifier.dispatch(any()));
      verify(
        () => stateCache.wasAlertSent(
          orgId: any(named: 'orgId'),
          resource: any(named: 'resource'),
          threshold: any(named: 'threshold'),
        ),
      ).called(greaterThan(0));
    });

    test('markAlertSent called after successful dispatch', () async {
      _stubCacheMiss(stateCache);
      _stubNotifierOk(notifier);

      await service.checkAndDispatchAlerts(
        _ctx(currentCount: 85, maxAllowed: 100),
      );

      verify(
        () => stateCache.markAlertSent(
          orgId: any(named: 'orgId'),
          resource: any(named: 'resource'),
          threshold: any(named: 'threshold'),
        ),
      ).called(greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // A — AVAILABILITY
  // ═══════════════════════════════════════════════════════════════════════════

  group('[A] Happy Path — Threshold Detection', () {
    test('85% usage triggers >= 80% threshold alert', () async {
      _stubCacheMiss(stateCache);
      _stubNotifierOk(notifier);

      await service.checkAndDispatchAlerts(
        _ctx(currentCount: 85, maxAllowed: 100),
      );

      final captured = verify(() => notifier.dispatch(captureAny())).captured;
      expect(captured, isNotEmpty);
      final payloads = captured.cast<QuotaAlertPayload>();
      expect(
        payloads.any((p) => p.threshold >= 80),
        isTrue,
        reason: '85% must fire >= 80 threshold',
      );
    });

    test('95% usage triggers >= 90% threshold alert', () async {
      _stubCacheMiss(stateCache);
      _stubNotifierOk(notifier);

      await service.checkAndDispatchAlerts(
        _ctx(currentCount: 95, maxAllowed: 100),
      );

      final captured = verify(() => notifier.dispatch(captureAny())).captured;
      expect(captured, isNotEmpty);
      final payloads = captured.cast<QuotaAlertPayload>();
      expect(
        payloads.any((p) => p.threshold >= 90),
        isTrue,
        reason: '95% must fire >= 90 threshold',
      );
    });

    test('payload threshold and usagePct are consistent', () async {
      _stubCacheMiss(stateCache);
      _stubNotifierOk(notifier);

      await service.checkAndDispatchAlerts(
        _ctx(currentCount: 95, maxAllowed: 100),
      );

      final captured = verify(() => notifier.dispatch(captureAny())).captured;
      for (final raw in captured) {
        final p = raw as QuotaAlertPayload;
        expect(
          p.usagePct,
          greaterThanOrEqualTo(p.threshold),
          reason: 'threshold must never exceed actual usagePct',
        );
      }
    });

    test('50% usage does not trigger 80% or 90% alert', () async {
      _stubCacheMiss(stateCache);
      _stubNotifierOk(notifier);

      await service.checkAndDispatchAlerts(
        _ctx(currentCount: 50, maxAllowed: 100),
      );

      final captured = verify(() => notifier.dispatch(captureAny())).captured;
      final payloads = captured.cast<QuotaAlertPayload>();
      expect(payloads.any((p) => p.threshold >= 80), isFalse);
    });
  });

  group('[A] Fail-Safe — Cascade Failure Isolation', () {
    test('SMTP 500 does not propagate exception to caller', () async {
      _stubCacheMiss(stateCache);
      when(
        () => notifier.dispatch(any()),
      ).thenThrow(Exception('SMTP gateway 500 — connection refused'));

      await expectLater(
        service.checkAndDispatchAlerts(_ctx(currentCount: 85, maxAllowed: 100)),
        completes,
        reason: 'Notifier failure must be absorbed (fail-safe)',
      );
    });

    test('notifier timeout does not propagate exception', () async {
      _stubCacheMiss(stateCache);
      when(
        () => notifier.dispatch(any()),
      ).thenThrow(TimeoutException('Edge Function timeout after 30s'));

      await expectLater(
        service.checkAndDispatchAlerts(_ctx(currentCount: 95, maxAllowed: 100)),
        completes,
      );
    });

    test('stateCache still consulted even when notifier throws', () async {
      _stubCacheMiss(stateCache);
      when(() => notifier.dispatch(any())).thenThrow(Exception('SMTP offline'));

      await service.checkAndDispatchAlerts(
        _ctx(currentCount: 85, maxAllowed: 100),
      );

      verify(
        () => stateCache.wasAlertSent(
          orgId: any(named: 'orgId'),
          resource: any(named: 'resource'),
          threshold: any(named: 'threshold'),
        ),
      ).called(greaterThan(0));
    });
  });
}
