import 'package:veraprob/domain/shared/authorization_exception.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/shared/concurrent_modification_exception.dart';
import 'package:veraprob/domain/sla_audit/dual_control_self_approval_exception.dart';

/// Maps a captured action error to a clean, auditor-facing message.
///
/// Lesson 5 / INV-10: the UI speaks domain language only — never a raw
/// `toString()` (type prefix, `(field: …)` tags, stack traces, or infra error
/// codes leak debugging detail to the operator). Typed domain exceptions carry
/// a curated [message]; anything unrecognised degrades to one safe sentence.
String humanizeDomainError(Object? error) => switch (error) {
  ConflictException(:final message) => message,
  IntegrityException(:final message) => message,
  AuthorizationException(:final message) => message,
  SovereigntyViolationException(:final message) => message,
  ResourceNotFoundException(:final message) => message,
  IdempotencyProcessingException(:final message) => message,
  ConcurrentModificationException(:final message) => message,
  DualControlSelfApprovalException(:final message) => message,
  _ => 'Erro Desconhecido: ${error?.toString() ?? "null"}',
};
