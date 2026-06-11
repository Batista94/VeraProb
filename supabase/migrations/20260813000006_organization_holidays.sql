-- =============================================================================
-- Migration: organization_holidays — Deterministic Business-Day Calendar
-- H4: seed_brazilian_national_holidays is a LOCALE PACK — NEVER auto-invoked by
--     generic tenant provisioning. The agnostic core only ships the empty table
--     + the deadline function that reads it.
-- M-arch: soft-delete (deleted_at), no client DELETE grant.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.organization_holidays (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   UUID        NOT NULL REFERENCES public.organizations(id),
  holiday_date      DATE        NOT NULL,
  label             TEXT        NOT NULL,
  is_national       BOOLEAN     NOT NULL DEFAULT FALSE,
  deleted_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_org_holiday_date UNIQUE (organization_id, holiday_date)
);

CREATE INDEX IF NOT EXISTS idx_oh_org_date
  ON public.organization_holidays (organization_id, holiday_date)
  WHERE deleted_at IS NULL;

ALTER TABLE public.organization_holidays ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS oh_select_own_org ON public.organization_holidays;
CREATE POLICY oh_select_own_org ON public.organization_holidays FOR SELECT
  USING (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID));

DROP POLICY IF EXISTS oh_insert_own_org ON public.organization_holidays;
CREATE POLICY oh_insert_own_org ON public.organization_holidays FOR INSERT
  WITH CHECK (
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  );

DROP POLICY IF EXISTS oh_update_own_org ON public.organization_holidays;
CREATE POLICY oh_update_own_org ON public.organization_holidays FOR UPDATE
  USING (
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  )
  WITH CHECK (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID));

-- M-arch: soft-delete only. No client DELETE.
GRANT SELECT, INSERT, UPDATE ON TABLE public.organization_holidays TO authenticated;
GRANT ALL ON TABLE public.organization_holidays TO service_role;
-- Legacy ALTER DEFAULT PRIVILEGES grants DELETE to authenticated on new public
-- tables; strip it so soft-delete is the only path (M-arch). service_role keeps
-- DELETE for backend retention/GC only.
REVOKE DELETE ON TABLE public.organization_holidays FROM authenticated, anon;

-- ── Easter (Anonymous Gregorian) — verified 2026 = Apr 5 (Senior F5) ─────────
CREATE OR REPLACE FUNCTION public._compute_easter(p_year INT)
RETURNS DATE LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE a INT;b INT;c INT;d INT;e INT;f INT;g INT;h INT;i INT;k INT;l INT;m INT;n INT;
BEGIN
  a := p_year % 19; b := p_year / 100; c := p_year % 100;
  d := b / 4; e := b % 4; f := (b + 8) / 25; g := (b - f + 1) / 3;
  h := (19*a + b - d - g + 15) % 30; i := c / 4; k := c % 4;
  l := (32 + 2*e + 2*i - h - k) % 7; m := (a + 11*h + 22*l) / 451;
  n := h + l - 7*m + 114;
  RETURN make_date(p_year, n / 31, (n % 31) + 1);
END;
$$;

-- ── LOCALE PACK: BR national holidays (NEVER auto-called on provisioning) ─────
CREATE OR REPLACE FUNCTION public.seed_brazilian_national_holidays(
  p_organization_id UUID, p_year INT)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_count INT := 0; v_easter DATE; v_h DATE[];
BEGIN
  v_easter := public._compute_easter(p_year);
  v_h := ARRAY[
    make_date(p_year,1,1), make_date(p_year,4,21), make_date(p_year,5,1),
    make_date(p_year,9,7), make_date(p_year,10,12), make_date(p_year,11,2),
    make_date(p_year,11,15), make_date(p_year,12,25),
    (v_easter - INTERVAL '47 days')::date, (v_easter - INTERVAL '48 days')::date,
    (v_easter - INTERVAL '2 days')::date,  (v_easter + INTERVAL '60 days')::date
  ];
  INSERT INTO public.organization_holidays (organization_id, holiday_date, label, is_national)
  VALUES
    (p_organization_id,v_h[1],'Ano Novo',TRUE),(p_organization_id,v_h[2],'Tiradentes',TRUE),
    (p_organization_id,v_h[3],'Dia do Trabalho',TRUE),(p_organization_id,v_h[4],'Independência do Brasil',TRUE),
    (p_organization_id,v_h[5],'Nossa Sra. Aparecida',TRUE),(p_organization_id,v_h[6],'Finados',TRUE),
    (p_organization_id,v_h[7],'Proclamação da República',TRUE),(p_organization_id,v_h[8],'Natal',TRUE),
    (p_organization_id,v_h[9],'Carnaval (Terça)',TRUE),(p_organization_id,v_h[10],'Carnaval (Segunda)',TRUE),
    (p_organization_id,v_h[11],'Sexta-feira Santa',TRUE),(p_organization_id,v_h[12],'Corpus Christi',TRUE)
  ON CONFLICT (organization_id, holiday_date) DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ── Business-day deadline (Q1: deterministic; ISODOW Sat=6 Sun=7) ────────────
CREATE OR REPLACE FUNCTION public._compute_business_day_deadline(
  p_organization_id UUID, p_start_date DATE, p_business_days INT)
RETURNS TIMESTAMPTZ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_current DATE := p_start_date; v_counted INT := 0;
BEGIN
  IF p_business_days <= 0 THEN
    RETURN (v_current::TIMESTAMPTZ + INTERVAL '23 hours 59 minutes 59 seconds');
  END IF;
  WHILE v_counted < p_business_days LOOP
    v_current := v_current + 1;
    IF EXTRACT(ISODOW FROM v_current) IN (6, 7) THEN CONTINUE; END IF;  -- Sat/Sun
    IF EXISTS (SELECT 1 FROM public.organization_holidays
                WHERE organization_id = p_organization_id
                  AND holiday_date = v_current AND deleted_at IS NULL) THEN
      CONTINUE;
    END IF;
    v_counted := v_counted + 1;
  END LOOP;
  RETURN (v_current::TIMESTAMPTZ + INTERVAL '23 hours 59 minutes 59 seconds');
END;
$$;

REVOKE ALL ON FUNCTION public._compute_business_day_deadline(UUID, DATE, INT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public._compute_easter(INT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.seed_brazilian_national_holidays(UUID, INT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.seed_brazilian_national_holidays(UUID, INT) TO service_role;
