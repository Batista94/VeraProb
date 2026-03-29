-- Verificar se o gatilho cinemático disparou no ledger
SELECT event_type, metadata->>'anomaly_type' as anomaly, financial_impact_cents 
FROM public.audit_ledger 
WHERE event_type = 'KINEMATIC_ANOMALY' 
ORDER BY created_at DESC LIMIT 5;
