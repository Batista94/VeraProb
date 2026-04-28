import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Structured audit log payload viewer.
///
/// When [payload] contains `before` and `after` keys, renders a field-level
/// diff with changed values highlighted. Otherwise falls back to a key-value list.
///
/// [source] drives the actor icon:
///   - 'system' or 'edge_function' → robot icon
///   - anything else (admin, user) → shield icon
class AuditPayloadDiffView extends StatelessWidget {
  const AuditPayloadDiffView({super.key, required this.payload, this.source});

  final Map<String, Object?>? payload;
  final String? source;

  @override
  Widget build(BuildContext context) {
    if (payload == null || payload!.isEmpty) {
      return const Text(
        'Sem payload.',
        style: TextStyle(color: VeraProbColors.textSecondary),
      );
    }

    final hasDiff =
        payload!.containsKey('before') && payload!.containsKey('after');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActorBadge(source: source),
        const SizedBox(height: 12),
        if (hasDiff)
          _DiffView(payload: payload!)
        else
          _RawView(payload: payload!),
      ],
    );
  }
}

class _ActorBadge extends StatelessWidget {
  const _ActorBadge({this.source});
  final String? source;

  @override
  Widget build(BuildContext context) {
    final isSystem =
        source == 'system' || source == 'edge_function' || source == null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isSystem
              ? Icons.smart_toy_outlined
              : Icons.admin_panel_settings_outlined,
          size: 16,
          color: isSystem ? VeraProbColors.info : VeraProbColors.secondary,
        ),
        const SizedBox(width: 6),
        Text(
          isSystem ? 'Sistema' : 'Administrador',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSystem ? VeraProbColors.info : VeraProbColors.secondary,
          ),
        ),
        if (source != null) ...[
          const SizedBox(width: 4),
          Text(
            '($source)',
            style: const TextStyle(
              fontSize: 11,
              color: VeraProbColors.textDisabled,
            ),
          ),
        ],
      ],
    );
  }
}

class _DiffView extends StatelessWidget {
  const _DiffView({required this.payload});
  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final before = payload['before'];
    final after = payload['after'];
    final beforeMap = before is Map
        ? Map<String, Object?>.from(before)
        : <String, Object?>{};
    final afterMap = after is Map
        ? Map<String, Object?>.from(after)
        : <String, Object?>{};
    final allKeys = {...beforeMap.keys, ...afterMap.keys};

    if (allKeys.isEmpty) {
      return const Text('Nenhuma alteração registrada.');
    }

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(3),
        2: FlexColumnWidth(3),
      },
      border: TableBorder.all(color: VeraProbColors.border, width: 0.5),
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: VeraProbColors.superAdminSurface.withValues(alpha: 0.3),
          ),
          children: const [
            _TableHeader('Campo'),
            _TableHeader('Antes'),
            _TableHeader('Depois'),
          ],
        ),
        ...allKeys.map((key) {
          final oldVal = beforeMap[key];
          final newVal = afterMap[key];
          final changed = oldVal.toString() != newVal.toString();
          return TableRow(
            decoration: changed
                ? BoxDecoration(
                    color: VeraProbColors.warning.withValues(alpha: 0.08),
                  )
                : null,
            children: [
              _TableCell(
                key,
                style: changed
                    ? const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)
                    : null,
              ),
              _TableCell(_fmt(oldVal)),
              _TableCell(
                _fmt(newVal),
                style: changed
                    ? const TextStyle(
                        color: VeraProbColors.success,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      )
                    : null,
              ),
            ],
          );
        }),
      ],
    );
  }

  String _fmt(Object? v) {
    if (v == null) return '—';
    if (v is Map || v is List) return v.toString();
    return v.toString();
  }
}

class _RawView extends StatelessWidget {
  const _RawView({required this.payload});
  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: payload.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  e.key,
                  style: const TextStyle(
                    fontSize: 12,
                    color: VeraProbColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  e.value?.toString() ?? '—',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: VeraProbColors.textSecondary,
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell(this.text, {this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SelectableText(
        text,
        style:
            style ??
            const TextStyle(fontSize: 12, color: VeraProbColors.textPrimary),
      ),
    );
  }
}
