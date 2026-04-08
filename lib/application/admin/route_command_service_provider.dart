import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/admin/route_command_service.dart';
import 'package:veraprob/state/providers/assets_providers.dart';

final routeCommandServiceProvider = Provider<RouteCommandService>((ref) {
  return RouteCommandServiceImpl(ref.read(transitRouteRepositoryProvider));
});
