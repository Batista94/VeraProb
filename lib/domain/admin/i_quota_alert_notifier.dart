import 'package:veraprob/domain/admin/quota_alert_payload.dart';

abstract class IQuotaAlertNotifier {
  Future<void> dispatch(QuotaAlertPayload payload);
}
