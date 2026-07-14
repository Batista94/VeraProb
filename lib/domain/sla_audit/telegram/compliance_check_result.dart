import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Label map matching the webhook's CATEGORY_MAP.
const _categoryLabels = {
  'estado': 'Estado / Visual',
  'doc': 'Documental / NF',
  'oper': 'Operacional',
  'incidente': 'Incidente / SLA',
  'outros': 'Outros / Info',
};

/// A single required evidence type and its fulfillment status.
class ComplianceCheckItem extends Equatable {
  final String typeKey;
  final bool isFulfilled;
  final int count;

  const ComplianceCheckItem({
    required this.typeKey,
    required this.isFulfilled,
    required this.count,
  });

  /// Human-readable label. Falls back to [typeKey] for unknown categories.
  String get label => _categoryLabels[typeKey] ?? typeKey;

  factory ComplianceCheckItem.fromJson(Map<String, dynamic> json) {
    return ComplianceCheckItem(
      typeKey: json['type_key'] as String,
      isFulfilled: json['is_fulfilled'] as bool,
      count: json['count'] as int,
    );
  }

  @override
  List<Object?> get props => [typeKey, isFulfilled, count];
}

/// Result of a trip compliance status check.
///
/// Three variants:
/// - [ActiveCompliance]: active trip with REQUIRED_EVIDENCE rule defined.
/// - [NoActiveTrip]: driver has no active execution.
/// - [NoRequirements]: active trip but no REQUIRED_EVIDENCE rule on contract.
sealed class ComplianceCheckResult extends Equatable {
  const ComplianceCheckResult();

  factory ComplianceCheckResult.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String;
    return switch (status) {
      'active' => ActiveCompliance(
        setId: json['set_id'] as String,
        items: (json['items'] as List<dynamic>)
            .map((e) => ComplianceCheckItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalRequired: json['total_required'] as int,
        totalFulfilled: json['total_fulfilled'] as int,
      ),
      'no_active_trip' => const NoActiveTrip(),
      'no_requirements' => NoRequirements(
        setId: json['set_id'] as String,
        evidenceCount: json['evidence_count'] as int,
      ),
      _ => throw IntegrityException('Unknown compliance status: $status'),
    };
  }
}

/// Active trip with REQUIRED_EVIDENCE rule — contains the checklist.
class ActiveCompliance extends ComplianceCheckResult {
  final String setId;
  final List<ComplianceCheckItem> items;
  final int totalRequired;
  final int totalFulfilled;

  const ActiveCompliance({
    required this.setId,
    required this.items,
    required this.totalRequired,
    required this.totalFulfilled,
  });

  bool get isComplete => totalFulfilled >= totalRequired;
  int get pendingCount => totalRequired - totalFulfilled;

  List<ComplianceCheckItem> get pendingItems =>
      items.where((i) => !i.isFulfilled).toList();

  List<ComplianceCheckItem> get fulfilledItems =>
      items.where((i) => i.isFulfilled).toList();

  @override
  List<Object?> get props => [setId, items, totalRequired, totalFulfilled];
}

/// Driver has no active execution within the temporal window.
class NoActiveTrip extends ComplianceCheckResult {
  const NoActiveTrip();

  @override
  List<Object?> get props => [];
}

/// Active trip exists but the contract has no REQUIRED_EVIDENCE rule.
class NoRequirements extends ComplianceCheckResult {
  final String setId;
  final int evidenceCount;

  const NoRequirements({required this.setId, required this.evidenceCount});

  @override
  List<Object?> get props => [setId, evidenceCount];
}
