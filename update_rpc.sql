CREATE OR REPLACE FUNCTION public.find_execution_for_telegram(
  p_org_id     UUID,
  p_driver_id  UUID,
  p_message_ts BIGINT
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'set_id', es.set_id,
    'display_name', COALESCE(oz_origin.name, 'Origem') || ' ➔ ' || COALESCE(oz_dest.name, 'Destino') || ' (' || to_char(cse.scheduled_start_time_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI') || ')'
  )
  FROM public.execution_states es
  INNER JOIN public.contractual_service_executions cse ON es.set_id = cse.set_id
  INNER JOIN public.plan_declarations pd ON cse.plan_declaration_id = pd.id
  LEFT JOIN public.operational_zones oz_origin ON cse.origin_zone_id = oz_origin.id
  LEFT JOIN public.operational_zones oz_dest ON cse.destination_zone_id = oz_dest.id
  INNER JOIN public.drivers d ON d.id = p_driver_id
  WHERE pd.organization_id = p_org_id
    AND es.status IN ('pending', 'executed', 'evidenceGap')
    AND (cse.planned_vehicle_id IS NULL OR cse.planned_vehicle_id = d.license_number OR cse.planned_vehicle_id = d.id::text)
    AND es.window_start_utc >= to_timestamp(p_message_ts - 4 * 3600) AT TIME ZONE 'UTC'
    AND es.window_start_utc <= to_timestamp(p_message_ts + 600) AT TIME ZONE 'UTC'
  ORDER BY es.window_start_utc DESC
  LIMIT 1;
$$;
