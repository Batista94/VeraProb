import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/admin/organization.dart';
import '../../domain/admin/organization_repository.dart';

/// PostgreSQL implementation of [OrganizationRepository] using Supabase.
class PostgresOrganizationRepository implements OrganizationRepository {
  final SupabaseClient _client;

  PostgresOrganizationRepository(this._client);

  @override
  Future<Organization?> findById(String id) async {
    try {
      final data = await _client
          .from('organizations')
          .select()
          .eq('id', id)
          .single();
      
      return Organization(
        id: data['id'] as String,
        name: data['name'] as String,
        timezone: data['timezone'] as String,
        currencyCode: data['currency_code'] as String,
        logoUrl: data['logo_url'] as String?,
        isActive: data['is_active'] as bool,
        createdAt: DateTime.parse(data['created_at'] as String),
      );
    } catch (e) {
      // If single() fails (not found or multiple), return null
      return null;
    }
  }

  @override
  Future<void> update(Organization organization) async {
    await _client
        .from('organizations')
        .update({
          'name': organization.name,
          'timezone': organization.timezone,
          'currency_code': organization.currencyCode,
          'logo_url': organization.logoUrl,
        })
        .eq('id', organization.id);
  }
}
