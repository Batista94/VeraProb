import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_log_view.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';
import 'package:veraprob/features/admin/presentation/widgets/forensic_log_view.dart';

void main() {
  group('ForensicLogView Golden Tests', () {
    final fakeLog = WebhookDeliveryLogView(
      id: '550e8400-e29b-41d4-a716-446655440000',
      endpointId: 'ep_123',
      eventType: 'sla.breached',
      payload: const {'tenant': 'ACME', 'amount': 50000},
      status: WebhookDeliveryStatusView.failed,
      attemptCount: 3,
      createdAt: DateTime.utc(2026, 7, 1, 10, 0, 0),
      ledgerEntryId: 'ledger_abc',
      signature: 'sha256=abcdef1234567890',
      lastError: 'Timeout after 10000ms\nSocketException: Connection refused',
    );

    goldenTest(
      'renders forensic log details (narrow width)',
      fileName: 'forensic_log_view_narrow',
      builder: () => GoldenTestGroup(
        children: [
          GoldenTestScenario(
            name: 'Failed Status',
            constraints: const BoxConstraints(maxWidth: 320),
            child: ProviderScope(
              child: Material(child: ForensicLogView(log: fakeLog)),
            ),
          ),
          GoldenTestScenario(
            name: 'Success Status',
            constraints: const BoxConstraints(maxWidth: 320),
            child: ProviderScope(
              child: Material(
                child: ForensicLogView(
                  log: WebhookDeliveryLogView(
                    id: fakeLog.id,
                    endpointId: fakeLog.endpointId,
                    eventType: fakeLog.eventType,
                    payload: fakeLog.payload,
                    status: WebhookDeliveryStatusView.success,
                    attemptCount: fakeLog.attemptCount,
                    createdAt: fakeLog.createdAt,
                    ledgerEntryId: fakeLog.ledgerEntryId,
                    signature: fakeLog.signature,
                    lastError: null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  });
}
