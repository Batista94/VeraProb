import 'package:intl/intl.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';
import 'package:veraprob/domain/sla_audit/contractor.dart';

/// Transforms validated, header-keyed CSV rows into DB-shaped maps whose keys
/// match the `batch_upsert_<entity>` RPC recordsets (Bloco 1D).
///
/// Pure: type coercion only. Structural/format validity is already guaranteed
/// by [CsvPreflightValidator]; FK existence by [CsvForeignKeyValidator].
class CsvRowMapper {
  const CsvRowMapper();

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  List<Map<String, dynamic>> toDbRows({
    required String targetEntity,
    required List<Map<String, String>> rows,
    required CsvMappingTemplate template,
    required Map<String, Contractor> resolvedContractors,
  }) {
    return [
      for (final row in rows)
        switch (targetEntity) {
          'asset' => _asset(row, template),
          'operator' => _operator(row, template),
          'contractor' => _contractor(row, template),
          'contract' => _contract(row, template, resolvedContractors),
          'zone' => _zone(row, template),
          _ => <String, dynamic>{},
        },
    ];
  }

  String? _raw(
    Map<String, String> row,
    CsvMappingTemplate template,
    CsvTargetField field,
  ) {
    for (final ColumnMapping m in template.columnMappings) {
      if (m.targetField == field) {
        final v = row[m.csvHeader]?.trim();
        return (v == null || v.isEmpty) ? null : v;
      }
    }
    return null;
  }

  String? _formatHint(CsvMappingTemplate template, CsvTargetField field) {
    for (final ColumnMapping m in template.columnMappings) {
      if (m.targetField == field) return m.formatHint;
    }
    return null;
  }

  /// Parses a date as UTC to avoid local-timezone drift (INV-6 / INV-15).
  String? _isoUtc(String? raw, String? formatHint) {
    if (raw == null) return null;
    final DateTime parsed = formatHint != null
        ? DateFormat(formatHint).parseUtc(raw)
        : DateTime.parse(raw).toUtc();
    return parsed.toIso8601String();
  }

  void _putIfPresent(Map<String, dynamic> map, String key, Object? value) {
    if (value != null) map[key] = value;
  }

  Map<String, dynamic> _asset(Map<String, String> row, CsvMappingTemplate t) {
    final map = <String, dynamic>{};
    _putIfPresent(map, 'plate', _raw(row, t, CsvTargetField.identifier));
    _putIfPresent(map, 'model', _raw(row, t, CsvTargetField.assetModel));
    final cap = _raw(row, t, CsvTargetField.capacity);
    _putIfPresent(map, 'capacity', cap == null ? null : int.tryParse(cap));
    _putIfPresent(map, 'status', _raw(row, t, CsvTargetField.assetStatus));
    _putIfPresent(map, 'external_id', _raw(row, t, CsvTargetField.externalId));
    return map;
  }

  Map<String, dynamic> _operator(
    Map<String, String> row,
    CsvMappingTemplate t,
  ) {
    final map = <String, dynamic>{};
    _putIfPresent(map, 'full_name', _raw(row, t, CsvTargetField.operatorName));
    _putIfPresent(
      map,
      'license_number',
      _raw(row, t, CsvTargetField.operatorLicense),
    );
    _putIfPresent(map, 'external_id', _raw(row, t, CsvTargetField.externalId));
    return map;
  }

  Map<String, dynamic> _contractor(
    Map<String, String> row,
    CsvMappingTemplate t,
  ) {
    final map = <String, dynamic>{};
    _putIfPresent(map, 'name', _raw(row, t, CsvTargetField.contractorName));
    _putIfPresent(
      map,
      'tax_id',
      _raw(row, t, CsvTargetField.contractorDocument),
    );
    _putIfPresent(
      map,
      'primary_email',
      _raw(row, t, CsvTargetField.contractorEmail),
    );
    _putIfPresent(
      map,
      'contact_name',
      _raw(row, t, CsvTargetField.contractorContactName),
    );
    _putIfPresent(map, 'external_id', _raw(row, t, CsvTargetField.externalId));
    return map;
  }

  Map<String, dynamic> _contract(
    Map<String, String> row,
    CsvMappingTemplate t,
    Map<String, Contractor> resolved,
  ) {
    final map = <String, dynamic>{};
    _putIfPresent(map, 'name', _raw(row, t, CsvTargetField.contractCode));

    final doc = _raw(row, t, CsvTargetField.contractorDocument);
    if (doc != null) {
      _putIfPresent(map, 'contractor_name', resolved[_digits(doc)]?.name);
    }

    _putIfPresent(
      map,
      'valid_from_utc',
      _isoUtc(
        _raw(row, t, CsvTargetField.startDate),
        _formatHint(t, CsvTargetField.startDate),
      ),
    );
    _putIfPresent(
      map,
      'valid_until_utc',
      _isoUtc(
        _raw(row, t, CsvTargetField.endDate),
        _formatHint(t, CsvTargetField.endDate),
      ),
    );
    _putIfPresent(map, 'external_id', _raw(row, t, CsvTargetField.externalId));
    return map;
  }

  Map<String, dynamic> _zone(Map<String, String> row, CsvMappingTemplate t) {
    final map = <String, dynamic>{};
    _putIfPresent(map, 'name', _raw(row, t, CsvTargetField.zoneName));
    final lat = _raw(row, t, CsvTargetField.latitude);
    _putIfPresent(
      map,
      'latitude',
      lat == null
          ? null
          : double.tryParse(lat), // Physical Metric - Double Required
    );
    final lng = _raw(row, t, CsvTargetField.longitude);
    _putIfPresent(
      map,
      'longitude',
      lng == null
          ? null
          : double.tryParse(lng), // Physical Metric - Double Required
    );
    final radius = _raw(row, t, CsvTargetField.radiusMeters);
    _putIfPresent(
      map,
      'radius_meters',
      radius == null ? null : int.tryParse(radius),
    );
    _putIfPresent(map, 'external_id', _raw(row, t, CsvTargetField.externalId));
    return map;
  }
}
