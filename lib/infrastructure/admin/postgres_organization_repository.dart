import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/admin/org_api_secret.dart';
import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/admin/organization_repository.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

class PostgresOrganizationRepository
    with PostgresErrorInterceptor
    implements OrganizationRepository {
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

      return _mapToOrganization(data);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'organization');
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> update(Organization organization) async {
    try {
      await _client
          .from('organizations')
          .update({
            'name': organization.name,
            'timezone': organization.timezone,
            'currency_code': organization.currencyCode,
            'logo_url': organization.logoUrl,
            'organization_type': organization.organizationType,
            'capabilities': organization.capabilities.toJson(),
            'dwell_time_seconds': organization.dwellTimeSeconds,
          })
          .eq('id', organization.id);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'organization');
    }
  }

  @override
  Future<List<Organization>> findAll({OrgStatus? status}) async {
    try {
      var query = _client.from('organizations').select();
      if (status != null) {
        query = query.eq('status', status.dbValue);
      }
      final data = await query.order('name');
      return (data as List).map((row) => _mapToOrganization(row)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'organization');
    }
  }

  @override
  Future<void> updateStatus(
    String orgId,
    OrgStatus status,
    String reason,
    String actorId,
    String actorType,
  ) async {
    try {
      await _client
          .from('organizations')
          .update({'status': status.dbValue})
          .eq('id', orgId);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'organization');
    }
  }

  @override
  Future<OrgApiSecret?> findApiSecret(String orgId) async {
    try {
      final data = await _client
          .from('org_api_secrets')
          .select()
          .eq('organization_id', orgId)
          .isFilter('revoked_at', null)
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) return null;
      return OrgApiSecret.fromJson(data);
    } on PostgrestException {
      return null;
    }
  }

  Organization _mapToOrganization(Map<String, dynamic> data) {
    final rawCaps = data['capabilities'];
    final capabilities = rawCaps is Map<String, dynamic>
        ? OrgCapabilities.fromJson(rawCaps)
        : OrgCapabilities.defaults;

    // Parse status: fallback to is_active boolean for retro-compatibility
    final statusStr = data['status'] as String?;
    final OrgStatus status;
    if (statusStr != null) {
      status = OrgStatus.fromString(statusStr);
    } else {
      status = (data['is_active'] as bool? ?? true)
          ? OrgStatus.active
          : OrgStatus.suspended;
    }

    return Organization(
      id: data['id'] as String,
      name: data['name'] as String,
      timezone: data['timezone'] as String,
      currencyCode: data['currency_code'] as String,
      logoUrl: data['logo_url'] as String?,
      status: status,
      createdAt: DateTime.parse(data['created_at'] as String),
      legalName: data['legal_name'] as String?,
      cnpj: data['cnpj'] as String?,
      planType: data['plan_type'] as String?,
      maxVehicles: data['max_vehicles'] as int?,
      maxActiveContracts: data['max_active_contracts'] as int?,
      organizationType: data['organization_type'] as String?,
      capabilities: capabilities,
      billingDay: data['billing_day'] as int?,
      contactEmail: data['contact_email'] as String?,
      externalId: data['external_id'] as String?,
      dwellTimeSeconds: data['dwell_time_seconds'] as int? ?? 300,
    );
  }
}
