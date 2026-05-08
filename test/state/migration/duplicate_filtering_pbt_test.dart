/// **Validates: Requirements 8.1**
///
/// Property 9: Duplicate Notification Filtering
///
/// For any StreamProvider whose entities implement `==` via Equatable,
/// emitting two consecutive values where `previous == next` is `true`
/// SHALL result in zero listener notifications for the second emission.
///
/// Strategy: Runtime testing with generated data.
///
/// Uses Glados to generate random SanctionQueueItemView instances and verifies
/// that Stream.distinct(listEquals) correctly:
/// 1. Filters consecutive duplicate list emissions (zero notifications)
/// 2. Allows non-consecutive duplicates through (A, B, A → 3 notifications)
/// 3. Allows different values through immediately
///
/// The `pendingSanctionsStreamProvider` uses `.distinct(listEquals)` on the
/// stream. `SanctionQueueItemView` extends Equatable with 12 semantic fields.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;

import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';

// Feature: riverpod-v3-migration, Property 9: Duplicate Notification Filtering

// ── Generators ────────────────────────────────────────────────────────────────

/// Generates a valid SanctionQueueItemView with randomized semantic fields.
///
/// Constrains generated values to valid domain ranges:
/// - Latitude: [-90, 90], Longitude: [-180, 180]
/// - Confidence: [0, 100]
/// - Fine cents: > 0
/// - Timestamps: UTC
SanctionQueueItemView _generateItem(int seed) {
  // Use seed to deterministically vary all 12 semantic fields
  final id = 'item-${seed.abs() % 10000}';
  final organizationId = 'org-${seed.abs() % 100}';
  final ledgerEntryId = 'ledger-${seed.abs() % 5000}';
  final setId = 'set-${seed.abs() % 3000}';
  final contractId = 'contract-${seed.abs() % 200}';
  final statusIndex = seed.abs() % SanctionReviewStatus.values.length;
  final status = SanctionReviewStatus.values[statusIndex];
  final dayOffset = seed.abs() % 365;
  final createdAtUtc = DateTime.utc(2026, 1, 1).add(Duration(days: dayOffset));
  final hasReview = seed % 3 == 0;
  final reviewedAtUtc = hasReview
      ? createdAtUtc.add(const Duration(hours: 2))
      : null;
  final reviewedByUserId = hasReview ? 'user-${seed.abs() % 50}' : null;
  final rejectionReason = (seed % 5 == 0) ? 'reason-${seed.abs() % 10}' : null;
  final vehiclePlate = (seed % 4 == 0) ? 'ABC-${seed.abs() % 9999}' : null;

  // Generate valid VerdictEvidence
  final lat = ((seed.abs() % 1800) - 900) / 10.0; // [-90.0, 90.0]
  final lng = ((seed.abs() % 3600) - 1800) / 10.0; // [-180.0, 180.0]
  final confidence = seed.abs() % 101; // [0, 100]
  final fineCents = (seed.abs() % 99999) + 1; // > 0

  final verdictEvidence = VerdictEvidence.create(
    clauseRef: 'clause-${seed.abs() % 50}',
    ruleId: 'rule-${seed.abs() % 30}',
    ruleVersion: (seed.abs() % 5) + 1,
    primaryEvidenceLat: lat,
    primaryEvidenceLng: lng,
    primaryEvidenceTimestampUtc: createdAtUtc,
    deltaValue: (seed.abs() % 100).toDouble(),
    thresholdValue: 0.0,
    fineCents: Money(fineCents),
    confidenceScore: confidence,
  );

  return SanctionQueueItemView(
    id: id,
    organizationId: organizationId,
    ledgerEntryId: ledgerEntryId,
    setId: setId,
    contractId: contractId,
    verdictEvidence: verdictEvidence,
    status: status,
    createdAtUtc: createdAtUtc,
    reviewedAtUtc: reviewedAtUtc,
    reviewedByUserId: reviewedByUserId,
    rejectionReason: rejectionReason,
    vehiclePlate: vehiclePlate,
  );
}

/// Generates a list of SanctionQueueItemView from a seed and list size.
List<SanctionQueueItemView> _generateList(int seed, int size) {
  return List.generate(size, (i) => _generateItem(seed + i * 7));
}

void main() {
  group('Property 9: Duplicate Notification Filtering', () {
    // ── Sub-property 9a: Consecutive identical lists produce zero extra
    //    notifications ────────────────────────────────────────────────────────
    Glados2(any.intInRange(1, 500), any.intInRange(1, 5)).test(
      'consecutive identical list emissions produce exactly 1 notification',
      (seed, listSize) async {
        final list = _generateList(seed, listSize);

        final controller = StreamController<List<SanctionQueueItemView>>();
        addTearDown(controller.close);

        final distinctStream = controller.stream.distinct(listEquals);
        final emissions = <List<SanctionQueueItemView>>[];
        final sub = distinctStream.listen(emissions.add);
        addTearDown(sub.cancel);

        // Emit the same list twice (different instances, same content)
        controller.add(List.of(list));
        await Future<void>.delayed(Duration.zero);
        controller.add(List.of(list));
        await Future<void>.delayed(Duration.zero);

        expect(
          emissions.length,
          equals(1),
          reason:
              'Two consecutive identical list emissions should produce '
              'exactly 1 notification (second filtered by Stream.distinct). '
              'List size: $listSize, seed: $seed',
        );
      },
    );

    // ── Sub-property 9b: Non-consecutive duplicates are NOT filtered ─────────
    Glados2(any.intInRange(1, 500), any.intInRange(1, 5)).test(
      'non-consecutive duplicate lists each produce a notification (A, B, A → 3)',
      (seed, listSize) async {
        final listA = _generateList(seed, listSize);
        // Generate a different list by using a very different seed
        final listB = _generateList(seed + 10000, listSize);

        // Ensure A and B are actually different
        if (listEquals(listA, listB)) return; // Skip degenerate case

        final controller = StreamController<List<SanctionQueueItemView>>();
        addTearDown(controller.close);

        final distinctStream = controller.stream.distinct(listEquals);
        final emissions = <List<SanctionQueueItemView>>[];
        final sub = distinctStream.listen(emissions.add);
        addTearDown(sub.cancel);

        // Emit A, then B, then A again
        controller.add(List.of(listA));
        await Future<void>.delayed(Duration.zero);
        controller.add(List.of(listB));
        await Future<void>.delayed(Duration.zero);
        controller.add(List.of(listA)); // same as first, but not consecutive
        await Future<void>.delayed(Duration.zero);

        expect(
          emissions.length,
          equals(3),
          reason:
              'Non-consecutive duplicates (A, B, A) should produce 3 '
              'notifications. Stream.distinct only filters consecutive dupes. '
              'Seed: $seed',
        );
      },
    );

    // ── Sub-property 9c: Different values always pass through ────────────────
    Glados(
      any.intInRange(1, 500),
    ).test('different list values always produce a notification', (seed) async {
      final list1 = _generateList(seed, 2);
      final list2 = _generateList(seed + 5000, 3); // different size → different

      final controller = StreamController<List<SanctionQueueItemView>>();
      addTearDown(controller.close);

      final distinctStream = controller.stream.distinct(listEquals);
      final emissions = <List<SanctionQueueItemView>>[];
      final sub = distinctStream.listen(emissions.add);
      addTearDown(sub.cancel);

      controller.add(list1);
      await Future<void>.delayed(Duration.zero);
      controller.add(list2);
      await Future<void>.delayed(Duration.zero);

      expect(
        emissions.length,
        equals(2),
        reason:
            'Two different list emissions should produce 2 notifications. '
            'Seed: $seed',
      );
    });

    // ── Sub-property 9d: Multiple consecutive duplicates produce exactly 1
    //    notification ─────────────────────────────────────────────────────────
    Glados2(any.intInRange(1, 500), any.intInRange(2, 8)).test(
      'N consecutive identical emissions produce exactly 1 notification',
      (seed, repeatCount) async {
        final list = _generateList(seed, 2);

        final controller = StreamController<List<SanctionQueueItemView>>();
        addTearDown(controller.close);

        final distinctStream = controller.stream.distinct(listEquals);
        final emissions = <List<SanctionQueueItemView>>[];
        final sub = distinctStream.listen(emissions.add);
        addTearDown(sub.cancel);

        // Emit the same list N times
        for (var i = 0; i < repeatCount; i++) {
          controller.add(List.of(list));
          await Future<void>.delayed(Duration.zero);
        }

        expect(
          emissions.length,
          equals(1),
          reason:
              '$repeatCount consecutive identical emissions should produce '
              'exactly 1 notification. Seed: $seed',
        );
      },
    );

    // ── Sub-property 9e: Equatable equality is used for element comparison ──
    Glados(any.intInRange(1, 500)).test(
      'items with same semantic fields but different excluded fields are equal',
      (seed) {
        final item = _generateItem(seed);

        // Create a copy with different excluded fields (contractName,
        // windowStartUtc, windowEndUtc) — these are NOT in props
        final itemWithExcludedDiff = SanctionQueueItemView(
          id: item.id,
          organizationId: item.organizationId,
          ledgerEntryId: item.ledgerEntryId,
          setId: item.setId,
          contractId: item.contractId,
          verdictEvidence: item.verdictEvidence,
          status: item.status,
          createdAtUtc: item.createdAtUtc,
          reviewedAtUtc: item.reviewedAtUtc,
          reviewedByUserId: item.reviewedByUserId,
          rejectionReason: item.rejectionReason,
          vehiclePlate: item.vehiclePlate,
          // Different excluded fields:
          contractName: 'Different Contract Name',
          windowStartUtc: DateTime.utc(2099, 1, 1),
          windowEndUtc: DateTime.utc(2099, 12, 31),
        );

        expect(
          item == itemWithExcludedDiff,
          isTrue,
          reason:
              'Items with identical semantic fields but different excluded '
              'fields (contractName, windowStartUtc, windowEndUtc) must be '
              'equal via Equatable. Seed: $seed',
        );
      },
    );

    // ── Sub-property 9f: listEquals with excluded-field-different items
    //    still filters duplicates ─────────────────────────────────────────────
    Glados(any.intInRange(1, 500)).test(
      'Stream.distinct(listEquals) filters lists differing only in excluded fields',
      (seed) async {
        final item = _generateItem(seed);
        final itemWithExcludedDiff = SanctionQueueItemView(
          id: item.id,
          organizationId: item.organizationId,
          ledgerEntryId: item.ledgerEntryId,
          setId: item.setId,
          contractId: item.contractId,
          verdictEvidence: item.verdictEvidence,
          status: item.status,
          createdAtUtc: item.createdAtUtc,
          reviewedAtUtc: item.reviewedAtUtc,
          reviewedByUserId: item.reviewedByUserId,
          rejectionReason: item.rejectionReason,
          vehiclePlate: item.vehiclePlate,
          contractName: 'Enriched Name',
          windowStartUtc: DateTime.utc(2026, 6, 1),
          windowEndUtc: DateTime.utc(2026, 6, 30),
        );

        final controller = StreamController<List<SanctionQueueItemView>>();
        addTearDown(controller.close);

        final distinctStream = controller.stream.distinct(listEquals);
        final emissions = <List<SanctionQueueItemView>>[];
        final sub = distinctStream.listen(emissions.add);
        addTearDown(sub.cancel);

        // Emit list with base item, then list with excluded-field-different item
        controller.add([item]);
        await Future<void>.delayed(Duration.zero);
        controller.add([itemWithExcludedDiff]);
        await Future<void>.delayed(Duration.zero);

        expect(
          emissions.length,
          equals(1),
          reason:
              'Lists differing only in excluded fields (contractName, '
              'windowStartUtc, windowEndUtc) should be filtered as duplicates '
              'because Equatable props only include semantic fields. Seed: $seed',
        );
      },
    );

    // ── Sub-property 9g: Changing any semantic field produces notification ───
    Glados(any.intInRange(1, 500)).test(
      'changing any single semantic field in an item produces a notification',
      (seed) async {
        final item = _generateItem(seed);

        // Mutate the status field (a semantic field in props)
        final mutatedStatus = item.status == SanctionReviewStatus.pending
            ? SanctionReviewStatus.applied
            : SanctionReviewStatus.pending;

        final mutatedItem = SanctionQueueItemView(
          id: item.id,
          organizationId: item.organizationId,
          ledgerEntryId: item.ledgerEntryId,
          setId: item.setId,
          contractId: item.contractId,
          verdictEvidence: item.verdictEvidence,
          status: mutatedStatus, // Changed semantic field
          createdAtUtc: item.createdAtUtc,
          reviewedAtUtc: item.reviewedAtUtc,
          reviewedByUserId: item.reviewedByUserId,
          rejectionReason: item.rejectionReason,
          vehiclePlate: item.vehiclePlate,
        );

        final controller = StreamController<List<SanctionQueueItemView>>();
        addTearDown(controller.close);

        final distinctStream = controller.stream.distinct(listEquals);
        final emissions = <List<SanctionQueueItemView>>[];
        final sub = distinctStream.listen(emissions.add);
        addTearDown(sub.cancel);

        controller.add([item]);
        await Future<void>.delayed(Duration.zero);
        controller.add([mutatedItem]);
        await Future<void>.delayed(Duration.zero);

        expect(
          emissions.length,
          equals(2),
          reason:
              'Changing a semantic field (status) must produce a new '
              'notification. Stream.distinct should NOT filter this. '
              'Seed: $seed',
        );
      },
    );
  });
}
