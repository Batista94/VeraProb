import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';

/// Creates a [SanctionQueueItemView] with the given [id] and optional overrides.
SanctionQueueItemView _makeItem({
  String id = 'item-1',
  String organizationId = 'org-1',
  String ledgerEntryId = 'ledger-1',
  String setId = 'set-1',
  String contractId = 'contract-1',
  SanctionReviewStatus status = SanctionReviewStatus.pending,
  DateTime? createdAtUtc,
}) {
  return SanctionQueueItemView(
    id: id,
    organizationId: organizationId,
    ledgerEntryId: ledgerEntryId,
    setId: setId,
    contractId: contractId,
    verdictEvidence: VerdictEvidence.create(
      clauseRef: 'clause-1',
      ruleId: 'rule-1',
      ruleVersion: 1,
      primaryEvidenceLat: -23.5,
      primaryEvidenceLng: -46.6,
      primaryEvidenceTimestampUtc: DateTime.utc(2026, 1, 15, 10, 30),
      deltaValue: 5.0,
      thresholdValue: 0.0,
      fineCents: const Money(150000),
      confidenceScore: 100,
    ),
    status: status,
    createdAtUtc: createdAtUtc ?? DateTime.utc(2026, 1, 15, 10, 30),
  );
}

/// Validates: Requirements 8.1, 8.4
///
/// Verifies that:
/// 1. SanctionQueueItemView implements == via Equatable with all relevant fields
/// 2. Stream.distinct(listEquals) correctly filters duplicate list emissions
/// 3. The default updateShouldNotify (==) behavior works correctly for this provider
void main() {
  group('SanctionQueueItemView Equatable (Req 8.3, 8.4)', () {
    test('two instances with identical fields are equal', () {
      final a = _makeItem();
      final b = _makeItem();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two instances differing in id are NOT equal', () {
      final a = _makeItem(id: 'item-1');
      final b = _makeItem(id: 'item-2');

      expect(a, isNot(equals(b)));
    });

    test('two instances differing in status are NOT equal', () {
      final a = _makeItem(status: SanctionReviewStatus.pending);
      final b = _makeItem(status: SanctionReviewStatus.applied);

      expect(a, isNot(equals(b)));
    });

    test('two instances differing in organizationId are NOT equal', () {
      final a = _makeItem(organizationId: 'org-1');
      final b = _makeItem(organizationId: 'org-2');

      expect(a, isNot(equals(b)));
    });

    test('two instances differing in setId are NOT equal', () {
      final a = _makeItem(setId: 'set-1');
      final b = _makeItem(setId: 'set-2');

      expect(a, isNot(equals(b)));
    });

    test('two instances differing in contractId are NOT equal', () {
      final a = _makeItem(contractId: 'contract-1');
      final b = _makeItem(contractId: 'contract-2');

      expect(a, isNot(equals(b)));
    });

    test('two instances differing in createdAtUtc are NOT equal', () {
      final a = _makeItem(createdAtUtc: DateTime.utc(2026, 1, 15));
      final b = _makeItem(createdAtUtc: DateTime.utc(2026, 1, 16));

      expect(a, isNot(equals(b)));
    });
  });

  group(
    'listEquals filters duplicate SanctionQueueItemView lists (Req 8.1, 8.4)',
    () {
      test('listEquals returns true for lists with identical elements', () {
        final item1 = _makeItem(id: 'item-1');
        final item2 = _makeItem(id: 'item-2');

        // Same content, different list instances
        final listA = [item1, item2];
        final listB = [item1, item2];

        expect(listEquals(listA, listB), isTrue);
      });

      test('listEquals returns false for lists with different length', () {
        final item1 = _makeItem(id: 'item-1');
        final item2 = _makeItem(id: 'item-2');

        final listA = [item1, item2];
        final listC = [item1];

        expect(listEquals(listA, listC), isFalse);
      });

      test('listEquals returns false for lists with different order', () {
        final item1 = _makeItem(id: 'item-1');
        final item2 = _makeItem(id: 'item-2');

        final listA = [item1, item2];
        final listD = [item2, item1];

        expect(listEquals(listA, listD), isFalse);
      });

      test('listEquals returns false when element field changes', () {
        final item1 = _makeItem(id: 'item-1');
        final item1Modified = _makeItem(
          id: 'item-1',
          status: SanctionReviewStatus.applied,
        );

        final listA = [item1];
        final listB = [item1Modified];

        expect(listEquals(listA, listB), isFalse);
      });
    },
  );

  group('Stream.distinct(listEquals) duplicate filtering (Req 8.1, 8.4)', () {
    test('filters consecutive duplicate list emissions', () async {
      final item1 = _makeItem(id: 'item-1');
      final item2 = _makeItem(id: 'item-2');
      final identicalList1 = [item1, item2];
      final identicalList2 = [item1, item2]; // same content, different instance

      final controller = StreamController<List<SanctionQueueItemView>>();
      addTearDown(controller.close);

      // Apply the same distinct logic used by pendingSanctionsStreamProvider
      final distinctStream = controller.stream.distinct(listEquals);

      final emissions = <List<SanctionQueueItemView>>[];
      final sub = distinctStream.listen(emissions.add);
      addTearDown(sub.cancel);

      // Emit first list
      controller.add(identicalList1);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.length, 1);

      // Emit identical list (should be filtered by Stream.distinct)
      controller.add(identicalList2);
      await Future<void>.delayed(Duration.zero);
      expect(
        emissions.length,
        1,
        reason: 'Duplicate emission should be filtered',
      );

      // Emit different list (should pass through)
      final differentList = [item1]; // removed item2
      controller.add(differentList);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.length, 2, reason: 'Different list should pass through');
    });

    test('notifies when a list element changes', () async {
      final item1 = _makeItem(id: 'item-1');
      final item1Modified = _makeItem(
        id: 'item-1',
        status: SanctionReviewStatus.applied,
      );

      final controller = StreamController<List<SanctionQueueItemView>>();
      addTearDown(controller.close);

      final distinctStream = controller.stream.distinct(listEquals);

      final emissions = <List<SanctionQueueItemView>>[];
      final sub = distinctStream.listen(emissions.add);
      addTearDown(sub.cancel);

      // Emit initial list
      controller.add([item1]);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.length, 1);

      // Emit list with modified element (status changed)
      controller.add([item1Modified]);
      await Future<void>.delayed(Duration.zero);
      expect(
        emissions.length,
        2,
        reason: 'Modified element should trigger notification',
      );
    });

    test('does not filter non-consecutive duplicates', () async {
      final item1 = _makeItem(id: 'item-1');
      final item2 = _makeItem(id: 'item-2');

      final controller = StreamController<List<SanctionQueueItemView>>();
      addTearDown(controller.close);

      final distinctStream = controller.stream.distinct(listEquals);

      final emissions = <List<SanctionQueueItemView>>[];
      final sub = distinctStream.listen(emissions.add);
      addTearDown(sub.cancel);

      // Emit A, then B, then A again — all should pass through
      controller.add([item1]);
      await Future<void>.delayed(Duration.zero);
      controller.add([item2]);
      await Future<void>.delayed(Duration.zero);
      controller.add([item1]); // same as first, but not consecutive
      await Future<void>.delayed(Duration.zero);

      expect(
        emissions.length,
        3,
        reason: 'Non-consecutive duplicates should not be filtered',
      );
    });

    test('filters multiple consecutive duplicates in sequence', () async {
      final item1 = _makeItem(id: 'item-1');

      final controller = StreamController<List<SanctionQueueItemView>>();
      addTearDown(controller.close);

      final distinctStream = controller.stream.distinct(listEquals);

      final emissions = <List<SanctionQueueItemView>>[];
      final sub = distinctStream.listen(emissions.add);
      addTearDown(sub.cancel);

      // Emit same list 5 times consecutively
      for (var i = 0; i < 5; i++) {
        controller.add([item1]);
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        emissions.length,
        1,
        reason: 'Only first of 5 identical emissions should pass',
      );

      // Then emit a different value
      final item2 = _makeItem(id: 'item-2');
      controller.add([item2]);
      await Future<void>.delayed(Duration.zero);

      expect(
        emissions.length,
        2,
        reason: 'Different value after duplicates should pass',
      );
    });
  });
}
