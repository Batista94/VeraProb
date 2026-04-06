// application/ CAN import domain/ — permitted by C4 architecture.
// features/ MUST import this barrel instead of domain/ directly.
import 'package:veraprob/application/super_admin/system_audit_log_view.dart';
import 'package:veraprob/application/super_admin/mfa_result_view.dart';

export 'package:veraprob/domain/enums/user_role.dart';
export 'package:veraprob/domain/enums/user_permissions.dart';
export 'package:veraprob/domain/enums/vehicle_status.dart';
export 'package:veraprob/domain/enums/incident_lifecycle_status.dart';
export 'package:veraprob/domain/sla_audit/execution_status.dart';
export 'package:veraprob/domain/sla_audit/transport_vertical.dart';
export 'package:veraprob/domain/sla_audit/vehicle_category.dart';
export 'package:veraprob/domain/sla_audit/week_cycle.dart';
export 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
export 'package:veraprob/domain/sla_audit/justification/justification_category.dart';
export 'package:veraprob/domain/super_admin/plan_type.dart';
export 'package:veraprob/domain/services/rbac_service.dart';
export 'package:veraprob/application/admin/operational_zone_view.dart';
export 'package:veraprob/domain/shared/money.dart';
export 'package:veraprob/domain/sla_audit/operational_zone.dart'
    show ZoneType, ZoneScope;
export 'package:veraprob/domain/sla_audit/contractual_rule.dart'
    show SlaRuleType;
export 'package:veraprob/domain/entities/driver.dart';
export 'package:veraprob/domain/entities/trip.dart';
export 'package:veraprob/domain/entities/bus_stop.dart';
export 'package:veraprob/domain/entities/vehicle_position.dart';
export 'package:veraprob/domain/entities/transit_route.dart';
export 'package:veraprob/domain/entities/vehicle.dart';
export 'package:veraprob/domain/assets/i_transit_route_repository.dart';
export 'package:veraprob/domain/assets/i_vehicle_asset_repository.dart';
export 'package:veraprob/domain/shared/i_trip_repository.dart';
export 'package:veraprob/domain/sla_audit/operational_alert.dart';
export 'package:veraprob/domain/super_admin/mfa_enrollment_result.dart';
export 'package:veraprob/domain/super_admin/mfa_exception.dart';
export 'package:veraprob/domain/sla_audit/domain_exception.dart';
export 'package:veraprob/domain/sla_audit/shift_pattern.dart';
export 'package:veraprob/domain/sla_audit/sla_penalties.dart';
export 'package:veraprob/domain/sla_audit/justification/justification_submission_token.dart';
export 'package:veraprob/domain/admin/invitation.dart';
export 'package:veraprob/domain/sla_audit/evaluation_trace.dart';
export 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
export 'package:veraprob/domain/sla_audit/heartbeat_classification.dart';
export 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
export 'package:veraprob/domain/sla_audit/contractual_rule.dart';
export 'package:veraprob/domain/sla_audit/geocoding_repository.dart'
    show PlaceSuggestion;
export 'package:veraprob/domain/sla_audit/signal_integrity_monitor.dart';
export 'package:veraprob/domain/sla_audit/sla_breach_risk_calculator.dart';
export 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
export 'package:veraprob/domain/sla_audit/infraction_recurrence_report.dart';
export 'package:veraprob/domain/sla_audit/billing_cycle_report.dart';
export 'package:veraprob/domain/sla_audit/contractor.dart';
export 'package:veraprob/domain/super_admin/system_audit_log_entry.dart';
export 'package:veraprob/application/super_admin/system_audit_log_view.dart';
export 'package:veraprob/domain/super_admin/mfa_challenge_result.dart';
export 'package:veraprob/application/super_admin/mfa_result_view.dart';

typedef AuditLogEntry = SystemAuditLogView;
typedef MfaResult = MfaVerificationView;
