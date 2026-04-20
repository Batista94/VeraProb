INSERT INTO public.sla_audit_ledger_v2 (
  organization_id, 
  contract_id,      -- Vamos usar o ID padrão do contrato de teste
  set_id, 
  occurred_at_utc, 
  type, 
  operator_id, 
  payload
) VALUES (
  '80cd7794-6106-451f-884f-a8af8fc13b9a', -- Sua Logística ABC ✅
  '00000000-0000-0000-0000-ca0000000001',   -- ID de Contrato válido (Seed) ✅
  'SET-VLV-001', 
  now(), 
  'SANCTION_RECOMMENDED', 
  'SYSTEM_ENGINE', 
  '{
    "clause_ref": "VEL-01",
    "fine_cents": 150000,
    "verdict_evidence": {
      "rule_id": "rule-vel-01",
      "rule_version": "1.0",
      "gps_lat": -23.5505,
      "gps_lng": -46.6333,
      "primary_evidence_timestamp_utc": "2026-03-20T10:00:00Z",
      "delta_value": 15,
      "threshold_value": 80,
      "confidence_score": 0.97,
      "evidence_hash": "a3f1c2d4e5b6a7f8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
    }
  }'::jsonb
);
