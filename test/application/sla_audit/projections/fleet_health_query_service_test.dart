import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/projections/fleet_health_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';

class MockFleetHealthQueryService extends Mock
    implements FleetHealthQueryService {}

class FakeFleetHealthView extends Fake implements FleetHealthView {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeFleetHealthView());
  });

  group('FleetHealthQueryService Contract', () {
    late FleetHealthQueryService service;

    setUp(() {
      service = MockFleetHealthQueryService();
    });

    test(
      'should allow mocking getFleetHealth with default parameters',
      () async {
        final mockView = FakeFleetHealthView();

        when(
          () => service.getFleetHealth(
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((_) async => mockView);

        final result = await service.getFleetHealth(organizationId: 'org-123');

        expect(result, equals(mockView));

        verify(
          () => service.getFleetHealth(organizationId: 'org-123'),
        ).called(1);
      },
    );

    test(
      'should allow mocking getFleetHealth with explicit parameters',
      () async {
        final mockView = FakeFleetHealthView();

        when(
          () => service.getFleetHealth(
            organizationId: any(named: 'organizationId'),
            delayedSec: any(named: 'delayedSec'),
            offlineSec: any(named: 'offlineSec'),
          ),
        ).thenAnswer((_) async => mockView);

        final result = await service.getFleetHealth(
          organizationId: 'org-123',
          delayedSec: 1200,
          offlineSec: 4000,
        );

        expect(result, equals(mockView));

        verify(
          () => service.getFleetHealth(
            organizationId: 'org-123',
            delayedSec: 1200,
            offlineSec: 4000,
          ),
        ).called(1);
      },
    );
  });
}
