import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Structured audit log payload viewer.
///
/// When [payload] contains `before` and `after` keys, renders a field-level
/// diff with changed values highlighted. Otherwise falls back to a key-value list.
///
/// [source] drives the actor icon:
///   - 'system' or 'edge_function' → 🤖 robot icon
///   - 'impersonator' → 👁️ visibility icon
///   - anything else (admin, user) → 🛡️ shield icon
///
/// [actorType] overrides source-based detection when present (Stage C).
class AuditPayloadDiffView extends StatelessWidget {
  const AuditPayloadDiffView({
    super.key,
    required this.payload,
    this.source,
    this.actorType,
    this.reason,
  });

  final Map<String, Object?>? payload;
  final String? source;
  final String? actorType;
  final String? reason;

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
    final contextMap = payload!['context'];
    final hasContext = contextMap is Map && contextMap.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActorBadge(source: source, actorType: actorType),
        if (reason != null && reason!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ReasonBanner(reason: reason!),
        ],
        if (hasContext) ...[
          const SizedBox(height: 12),
          _ContextView(
            context: Map<String, Object?>.from(
              // pr_scanner: ignore
              contextMap as Map<Object?, Object?>,
            ),
          ),
        ],
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
  const _ActorBadge({this.source, this.actorType});
  final String? source;
  final String? actorType;

  @override
  Widget build(BuildContext context) {
    final effectiveType = actorType?.toUpperCase() ?? _inferType(source);

    final IconData icon;
    final Color color;
    final String label;

    switch (effectiveType) {
      case 'SYSTEM':
        icon = Icons.smart_toy_outlined;
        color = VeraProbColors.info;
        label = 'Sistema';
      case 'IMPERSONATOR':
        icon = Icons.visibility_outlined;
        color = VeraProbColors.error;
        label = 'Impersonation';
      case 'HUMAN':
      default:
        icon = Icons.admin_panel_settings_outlined;
        color = VeraProbColors.secondary;
        label = 'Administrador';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
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

  String _inferType(String? source) {
    if (source == 'system' || source == 'edge_function' || source == null) {
      return 'SYSTEM';
    }
    return 'HUMAN';
  }
}

/// Displays the governance justification reason.
class _ReasonBanner extends StatelessWidget {
  const _ReasonBanner({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: VeraProbColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: VeraProbColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notes_outlined,
            size: 14,
            color: VeraProbColors.info,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              reason,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: VeraProbColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Exibe campos de contexto fixo (não entram no diff porque são imutáveis).
///
/// Exemplos: email do usuário afetado, user_id, org_id.
class _ContextView extends StatelessWidget {
  const _ContextView({required this.context});
  final Map<String, Object?> context;

  static const _labels = {
    'email': 'E-mail',
    'user_id': 'User ID',
    'org_id': 'Org ID',
  };

  @override
  Widget build(BuildContext buildContext) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: VeraProbColors.superAdminSurface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: VeraProbColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(
                Icons.fingerprint,
                size: 13,
                color: VeraProbColors.textSecondary,
              ),
              SizedBox(width: 5),
              Text(
                'Contexto',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...context.entries.map((e) {
            final label = _labels[e.key] ?? e.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: VeraProbColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      e.value?.toString() ?? '—',
                      style: const TextStyle(
                        fontSize: 11,
                        color: VeraProbColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
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
        ? Map<String, Object?>.from(before) // pr_scanner: ignore
        : <String, Object?>{};
    final afterMap = after is Map
        ? Map<String, Object?>.from(after) // pr_scanner: ignore
        : <String, Object?>{};
    final allKeys = {...beforeMap.keys, ...afterMap.keys};

    if (allKeys.isEmpty) {
      return const Text('Nenhuma alteração registrada.');
    }

    // Stage C: Only show fields that actually changed
    final changedKeys = allKeys.where((key) {
      return beforeMap[key]?.toString() != afterMap[key]?.toString();
    }).toList();

    if (changedKeys.isEmpty) {
      return const Text(
        'Nenhum campo alterado.',
        style: TextStyle(color: VeraProbColors.textSecondary),
      );
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
        ...changedKeys.map((key) {
          final oldVal = beforeMap[key];
          final newVal = afterMap[key];
          return TableRow(
            decoration: BoxDecoration(
              color: VeraProbColors.warning.withValues(alpha: 0.08),
            ),
            children: [
              _TableCell(
                key,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              _TableCell(
                _fmt(oldVal),
                style: const TextStyle(
                  color: VeraProbColors.error,
                  fontSize: 12,
                ),
              ),
              _TableCell(
                _fmt(newVal),
                style: const TextStyle(
                  color: VeraProbColors.success,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
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
