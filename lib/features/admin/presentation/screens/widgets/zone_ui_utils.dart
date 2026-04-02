import 'package:flutter/material.dart';

import 'package:veraprob/domain/sla_audit/operational_zone.dart';

extension ZoneTypeUi on ZoneType {
  IconData get icon => switch (this) {
    ZoneType.garagem => Icons.garage_outlined,
    ZoneType.cliente => Icons.business_outlined,
    ZoneType.apoio => Icons.support_agent_outlined,
  };

  String get label => switch (this) {
    ZoneType.garagem => 'Garagem',
    ZoneType.cliente => 'Cliente',
    ZoneType.apoio => 'Apoio',
  };
}
