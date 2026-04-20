-- Migration: Forensic Integrity Guard (INV-1.1)
-- Purpose: Prevents deletion of trips that have already been audited/ledgered.

CREATE OR REPLACE FUNCTION public.prevent_deletion_of_audited_trip()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if any ledger entry points to this trip ID
    -- We cast OLD.id to text because set_id is polymorphic (varchar)
    IF EXISTS (
        SELECT 1 
        FROM public.sla_audit_ledger_v2 
        WHERE set_id = OLD.id::text
        LIMIT 1
    ) THEN
        RAISE EXCEPTION '🚨 VIOLAÇÃO DE INTEGRIDADE (INV-1): A viagem % não pode ser excluída pois já possui vereditos de auditoria selados no Ledger.', OLD.id;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Apply the trigger to the trips_audit table
DROP TRIGGER IF EXISTS tr_prevent_audited_trip_deletion ON public.trips_audit;
CREATE TRIGGER tr_prevent_audited_trip_deletion
BEFORE DELETE ON public.trips_audit
FOR EACH ROW
EXECUTE FUNCTION public.prevent_deletion_of_audited_trip();
