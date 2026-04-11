import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// INV-26: Base repository for all Postgres-backed implementations.
///
/// Provides:
/// - [PostgresErrorInterceptor] mixin for automatic error translation
/// - Standard try/catch pattern for Supabase calls
///
/// Usage:
/// ```dart
/// class MyRepository extends BasePostgresRepository implements IMyRepository {
///   Future<MyEntity?> findById(String id) async {
///     return withErrorHandler(
///       'my_entity',
///       id,
///       () async {
///         final data = await client.from('my_table').select().eq('id', id).maybeSingle();
///         if (data == null) return null;
///         return _mapToEntity(data);
///       },
///     );
///   }
/// }
/// ```
abstract class BasePostgresRepository with PostgresErrorInterceptor {
  final SupabaseClient client;

  BasePostgresRepository(this.client);

  /// Executes a Supabase operation with automatic PostgREST error handling.
  ///
  /// [resourceType] and [resourceId] are used for forensic logging.
  Future<T> withErrorHandler<T>(
    String resourceType,
    String? resourceId,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: resourceType,
        resourceId: resourceId,
      );
    }
  }
}
