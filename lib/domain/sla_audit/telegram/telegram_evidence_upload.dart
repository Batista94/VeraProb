import 'package:equatable/equatable.dart';

/// Immutable evidence record uploaded via Telegram bot (INV-7, INV-9).
///
/// Maps to `telegram_evidence_uploads` table.
/// Fully immutable after INSERT — no UPDATE or DELETE allowed.
class TelegramEvidenceUpload extends Equatable {
  final String id;
  final String organizationId;
  final String driverId;
  final int chatId;
  final int telegramMessageId;
  final String fileName;
  final String forensicHash;
  final String storagePath;
  final String source;
  final String? linkedSetId;
  final DateTime uploadedAtUtc;
  final DateTime telegramMessageDate;
  final bool requiresManualLink;

  const TelegramEvidenceUpload({
    required this.id,
    required this.organizationId,
    required this.driverId,
    required this.chatId,
    required this.telegramMessageId,
    required this.fileName,
    required this.forensicHash,
    required this.storagePath,
    required this.source,
    this.linkedSetId,
    required this.uploadedAtUtc,
    required this.telegramMessageDate,
    required this.requiresManualLink,
  });

  /// Whether this evidence is an orphan (not linked to any execution).
  bool get isOrphan => requiresManualLink && linkedSetId == null;

  @override
  List<Object?> get props => [
    id,
    organizationId,
    driverId,
    chatId,
    telegramMessageId,
    fileName,
    forensicHash,
    storagePath,
    source,
    linkedSetId,
    uploadedAtUtc,
    telegramMessageDate,
    requiresManualLink,
  ];
}
