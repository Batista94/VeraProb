import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../infrastructure/postgres/postgres_test_config.dart';

const _uuid = Uuid();
final _orgAId = _uuid.v4();
final _orgBId = _uuid.v4();
final _userBEmail = 'attacker_b_${_uuid.v4().substring(0, 8)}@veraprob.test';
const _testPassword = 'TestPassword123!';

Future<String> _ensureUser(
  String email,
  String password, {
  required String supabaseUrl,
  required String serviceRoleKey,
}) async {
  final response = await http.post(
    Uri.parse('$supabaseUrl/auth/v1/admin/users'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'email': email,
      'password': password,
      'email_confirm': true,
    }),
  );

  if (response.statusCode == 200 || response.statusCode == 201) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['id'] as String;
  }

  if (response.statusCode == 422) {
    final listResponse = await http.get(
      Uri.parse('$supabaseUrl/auth/v1/admin/users?email=$email'),
      headers: {
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
      },
    );
    final list =
        (jsonDecode(listResponse.body) as Map<String, dynamic>)['users']
            as List<dynamic>;
    return (list.first as Map<String, dynamic>)['id'] as String;
  }

  throw Exception('Failed to create user $email: ${response.body}');
}

Future<void> _ensureOrg(
  SupabaseClient adminClient, {
  required String id,
  required String name,
}) async {
  final cnpj = id.replaceAll('-', '').substring(0, 14);
  await adminClient.from('organizations').upsert({
    'id': id,
    'name': name,
    'cnpj': cnpj,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  }, onConflict: 'id');
}

Future<void> _ensureUserRole(
  SupabaseClient adminClient, {
  required String userId,
  required String orgId,
  required String role,
}) async {
  await adminClient.from('user_roles').upsert({
    'user_id': userId,
    'organization_id': orgId,
    'role': role,
  }, onConflict: 'user_id');
}

Future<SupabaseClient> _signIn(
  String email,
  String password, {
  required String supabaseUrl,
  required String anonKey,
}) async {
  final client = SupabaseClient(supabaseUrl, anonKey);
  await client.auth.signInWithPassword(email: email, password: password);
  return client;
}

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'Database RLS Policy Cross-Org Efficacy Test',
    skip: !isRunning ? 'Supabase not running' : null,
    () {
      late SupabaseClient adminClient;
      late SupabaseClient orgBClient;
      late String orgAContractId;

      setUpAll(() async {
        adminClient = SupabaseClient(
          PostgresTestConfig.supabaseUrl,
          PostgresTestConfig.serviceRoleKey,
        );

        // 1. Seed Org A and Org B
        await _ensureOrg(adminClient, id: _orgAId, name: 'Target Org A');
        await _ensureOrg(adminClient, id: _orgBId, name: 'Attacker Org B');

        // 2. Seed User B in Org B
        final userBId = await _ensureUser(
          _userBEmail,
          _testPassword,
          supabaseUrl: PostgresTestConfig.supabaseUrl,
          serviceRoleKey: PostgresTestConfig.serviceRoleKey,
        );
        await _ensureUserRole(
          adminClient,
          userId: userBId,
          orgId: _orgBId,
          role: 'TENANT_ADMIN',
        );

        // 3. Seed confidential data into Org A that User B will try to read
        orgAContractId = _uuid.v4();
        await adminClient.from('contracts').insert({
          'id': orgAContractId,
          'organization_id': _orgAId,
          'name': 'Highly Confidential Contract A',
          'contractor_name': 'Contractor A',
          'status': 'draft',
          'valid_from_utc': DateTime.now().toUtc().toIso8601String(),
          'valid_until_utc': (DateTime.now().toUtc())
              .add(const Duration(days: 30))
              .toIso8601String(),
        });

        // 4. Sign in User B to get their JWT (bound to Org B)
        orgBClient = await _signIn(
          _userBEmail,
          _testPassword,
          supabaseUrl: PostgresTestConfig.supabaseUrl,
          anonKey: PostgresTestConfig.supabaseAnonKey,
        );
      });

      tearDownAll(() async {
        await orgBClient.auth.signOut();
      });

      test(
        'User from Org B attempting to read Org A data returns empty list (RLS filtering)',
        () async {
          // Act: Try to read data from Org A using a JWT from Org B
          final result = await orgBClient
              .from('contracts')
              .select('id, name')
              .eq('organization_id', _orgAId);

          // Assert: The test MUST return empty in order to pass (proving RLS works)
          expect(
            result,
            isEmpty,
            reason:
                'RLS policies should prevent a user bounded to Org B from reading data belonging to Org A.',
          );
        },
      );

      test(
        'User from Org B attempting direct ID access to Org A data returns empty list',
        () async {
          // Act: Try to fetch the specific Org A record by its known ID
          final result = await orgBClient
              .from('contracts')
              .select('*')
              .eq('id', orgAContractId);

          // Assert: Even with a direct ID reference, RLS must block it
          expect(
            result,
            isEmpty,
            reason:
                'Direct ID queries must also be blocked by RLS if the tenant organization_id does not match the JWT.',
          );
        },
      );
    },
  );
}
