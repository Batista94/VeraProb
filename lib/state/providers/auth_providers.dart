import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/enums/user_role.dart';

/// Temporarily mocks the currently authenticated user's role.
///
/// In Sprint 6, this defaults to [UserRole.operator] to easily test
/// UI restrictions (e.g. hiding the 'Delete' button on the Driver screen).
/// When Supabase Auth is integrated, this will read from the JWT claims.
final currentUserRoleProvider = StateProvider<UserRole>((ref) {
  return UserRole.supervisor;
});
