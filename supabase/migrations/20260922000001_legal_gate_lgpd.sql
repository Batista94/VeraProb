-- pr_scanner: ignore-regression — Legal Gate LGPD package (Council: Architect+Senior+QA+UX+Lead); user-scoped consent via JWT sub (INV-2), not tenant org claim
-- =============================================================================
-- Migration: Legal Gate & Terms of Use (LGPD)
-- Purpose:   Shared legal_documents SSOT + Flutter user_legal_consents ledger
--            + Telegram consent enrichment (consent-before-binding, version sync).
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · UX ✅ · Lead ✅
-- Invariants: INV-1, INV-2, INV-3, INV-6, INV-22, INV-26, INV-DATA-API-GRANT.
-- Depends on: telegram_user_consents (20260421000002), consume_telegram_binding_token.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. legal_documents (global catalog, versioned) ───────────────────────────

CREATE TABLE IF NOT EXISTS public.legal_documents (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_type          TEXT        NOT NULL
    CONSTRAINT chk_legal_doc_type CHECK (
      doc_type IN ('terms_of_use', 'privacy_policy', 'telegram_bot_terms')
    ),
  version           TEXT        NOT NULL,
  title             TEXT        NOT NULL,
  body_markdown     TEXT        NOT NULL,
  content_sha256    TEXT        NOT NULL
    CONSTRAINT chk_legal_doc_hash CHECK (content_sha256 ~ '^[a-f0-9]{64}$'),
  changelog         TEXT,
  status            TEXT        NOT NULL DEFAULT 'draft'
    CONSTRAINT chk_legal_doc_status CHECK (status IN ('draft', 'published')),
  published_at_utc  TIMESTAMPTZ,
  active_to_utc     TIMESTAMPTZ,
  created_at_utc    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_legal_doc_published_shape CHECK (
    (status = 'draft' AND published_at_utc IS NULL)
    OR (status = 'published' AND published_at_utc IS NOT NULL)
  )
);

COMMENT ON TABLE public.legal_documents IS
  'Platform legal document versions (LGPD SSOT). One active published row per doc_type.';

-- One active published version per doc_type
CREATE UNIQUE INDEX IF NOT EXISTS idx_legal_docs_one_active
  ON public.legal_documents (doc_type)
  WHERE active_to_utc IS NULL AND status = 'published';

CREATE UNIQUE INDEX IF NOT EXISTS idx_legal_docs_type_version
  ON public.legal_documents (doc_type, version);

CREATE INDEX IF NOT EXISTS idx_legal_docs_status
  ON public.legal_documents (status, doc_type);

-- Immutable once published (draft rows may be updated by service_role before publish)
CREATE OR REPLACE FUNCTION public.prevent_legal_doc_published_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'published' THEN
    -- Allow only closing the version (active_to_utc NULL → non-NULL) via publish RPC
    IF NEW.active_to_utc IS NOT NULL
       AND OLD.active_to_utc IS NULL
       AND NEW.id IS NOT DISTINCT FROM OLD.id
       AND NEW.doc_type IS NOT DISTINCT FROM OLD.doc_type
       AND NEW.version IS NOT DISTINCT FROM OLD.version
       AND NEW.title IS NOT DISTINCT FROM OLD.title
       AND NEW.body_markdown IS NOT DISTINCT FROM OLD.body_markdown
       AND NEW.content_sha256 IS NOT DISTINCT FROM OLD.content_sha256
       AND NEW.changelog IS NOT DISTINCT FROM OLD.changelog
       AND NEW.status IS NOT DISTINCT FROM OLD.status
       AND NEW.published_at_utc IS NOT DISTINCT FROM OLD.published_at_utc
       AND NEW.created_at_utc IS NOT DISTINCT FROM OLD.created_at_utc
    THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION
      'legal_documents: published rows are immutable (INV-3). id: %', OLD.id
      USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_legal_docs_no_published_mutation ON public.legal_documents;
CREATE TRIGGER trg_legal_docs_no_published_mutation
  BEFORE UPDATE ON public.legal_documents
  FOR EACH ROW EXECUTE FUNCTION public.prevent_legal_doc_published_mutation();

CREATE OR REPLACE FUNCTION public.prevent_legal_doc_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'legal_documents: append-only catalog (INV-3). DELETE blocked. id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_legal_docs_no_delete ON public.legal_documents;
CREATE TRIGGER trg_legal_docs_no_delete
  BEFORE DELETE ON public.legal_documents
  FOR EACH ROW EXECUTE FUNCTION public.prevent_legal_doc_delete();

ALTER TABLE public.legal_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS legal_docs_select_published ON public.legal_documents;
CREATE POLICY legal_docs_select_published
  ON public.legal_documents FOR SELECT
  USING (status = 'published');

GRANT SELECT ON TABLE public.legal_documents TO authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.legal_documents FROM authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE ALL ON TABLE public.legal_documents FROM anon; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
GRANT ALL ON TABLE public.legal_documents TO service_role;

-- ── 2. user_legal_consents (Flutter append-only ledger) ──────────────────────

CREATE TABLE IF NOT EXISTS public.user_legal_consents (
  id                        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                   UUID        NOT NULL,
  organization_id           UUID        REFERENCES public.organizations(id),
  document_id               UUID        NOT NULL REFERENCES public.legal_documents(id),
  document_version          TEXT        NOT NULL,
  document_content_sha256   TEXT        NOT NULL
    CONSTRAINT chk_ulc_hash CHECK (document_content_sha256 ~ '^[a-f0-9]{64}$'),
  action                    TEXT        NOT NULL
    CONSTRAINT chk_ulc_action CHECK (action IN ('accepted', 'withdrawn')),
  consented_at_utc          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ip_address                INET,
  user_agent                TEXT
);

COMMENT ON TABLE public.user_legal_consents IS
  'Append-only LGPD consent ledger for auth.users (Flutter Legal Gate). INV-3.';

-- No unique on (user_id, document_id): withdraw then re-accept of the same
-- version must append a new 'accepted' row (Art. 8 §5). Idempotency for
-- double-click is enforced in accept_legal_terms (latest action wins).
CREATE INDEX IF NOT EXISTS idx_ulc_user_doc_action
  ON public.user_legal_consents (user_id, document_id, action, consented_at_utc DESC);

CREATE INDEX IF NOT EXISTS idx_ulc_user_consented
  ON public.user_legal_consents (user_id, consented_at_utc DESC);

CREATE OR REPLACE FUNCTION public.prevent_ulc_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'user_legal_consents is append-only (INV-3). UPDATE blocked. id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_ulc_no_update ON public.user_legal_consents;
CREATE TRIGGER trg_ulc_no_update
  BEFORE UPDATE ON public.user_legal_consents
  FOR EACH ROW EXECUTE FUNCTION public.prevent_ulc_mutation();

CREATE OR REPLACE FUNCTION public.prevent_ulc_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'user_legal_consents is append-only (INV-3). DELETE blocked. id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_ulc_no_delete ON public.user_legal_consents;
CREATE TRIGGER trg_ulc_no_delete
  BEFORE DELETE ON public.user_legal_consents
  FOR EACH ROW EXECUTE FUNCTION public.prevent_ulc_delete();

-- TRUNCATE blocked even for service_role (forensic immutability)
CREATE OR REPLACE FUNCTION public.prevent_ulc_truncate()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'user_legal_consents is append-only (INV-3). TRUNCATE blocked.'
    USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_ulc_no_truncate ON public.user_legal_consents;
CREATE TRIGGER trg_ulc_no_truncate
  BEFORE TRUNCATE ON public.user_legal_consents -- INV-DB: zero-downtime-verified (append-only guard trigger, not DML wipe)
  FOR EACH STATEMENT EXECUTE FUNCTION public.prevent_ulc_truncate();

ALTER TABLE public.user_legal_consents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ulc_select_own ON public.user_legal_consents;
CREATE POLICY ulc_select_own
  ON public.user_legal_consents FOR SELECT
  USING (user_id = (auth.jwt() ->> 'sub')::uuid);

GRANT SELECT ON TABLE public.user_legal_consents TO authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.user_legal_consents FROM authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE ALL ON TABLE public.user_legal_consents FROM anon; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
GRANT ALL ON TABLE public.user_legal_consents TO service_role;

-- ── 3. Enrich telegram_user_consents (additive columns) ──────────────────────

ALTER TABLE public.telegram_user_consents
  ADD COLUMN IF NOT EXISTS document_id UUID REFERENCES public.legal_documents(id),
  ADD COLUMN IF NOT EXISTS document_content_sha256 TEXT,
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id),
  ADD COLUMN IF NOT EXISTS driver_id UUID,
  ADD COLUMN IF NOT EXISTS accepted_via TEXT DEFAULT 'telegram_callback',
  ADD COLUMN IF NOT EXISTS action TEXT NOT NULL DEFAULT 'accepted'
    CONSTRAINT chk_tuc_action CHECK (action IN ('accepted', 'withdrawn'));

-- Allow withdraw rows for the same version (Art. 8 §5). Old unique blocked it.
DROP INDEX IF EXISTS public.idx_tuc_chat_version; -- INV-DB: zero-downtime-verified (replace with partial unique)
CREATE UNIQUE INDEX IF NOT EXISTS idx_tuc_chat_version_accepted
  ON public.telegram_user_consents (chat_id, consent_version)
  WHERE action = 'accepted';

-- ── 4. Helpers & RPCs ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.has_current_legal_consent(
  p_user_id UUID DEFAULT NULLIF(auth.jwt() ->> 'sub', '')::uuid
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.legal_documents d
    WHERE d.doc_type = 'terms_of_use'
      AND d.status = 'published'
      AND d.active_to_utc IS NULL
      AND (
        SELECT c.action
        FROM public.user_legal_consents c
        WHERE c.user_id = p_user_id
          AND c.document_id = d.id
        -- Fail-closed on same-ms ties: withdrawn beats accepted.
        ORDER BY c.consented_at_utc DESC,
                 CASE c.action WHEN 'withdrawn' THEN 1 ELSE 0 END DESC,
                 c.id DESC
        LIMIT 1
      ) = 'accepted'
  );
$$;

REVOKE ALL ON FUNCTION public.has_current_legal_consent(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_current_legal_consent(UUID) TO authenticated, service_role;

-- Version-aware Telegram consent check (current published telegram_bot_terms)
CREATE OR REPLACE FUNCTION public.has_current_telegram_consent(p_chat_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.legal_documents d
    WHERE d.doc_type = 'telegram_bot_terms'
      AND d.status = 'published'
      AND d.active_to_utc IS NULL
      AND (
        SELECT c.action
        FROM public.telegram_user_consents c
        WHERE c.chat_id = p_chat_id
          AND (
            (c.document_id IS NOT NULL AND c.document_id = d.id)
            OR (c.document_id IS NULL AND c.consent_version = d.version)
          )
        ORDER BY c.accepted_at_utc DESC,
                 CASE c.action WHEN 'withdrawn' THEN 1 ELSE 0 END DESC,
                 c.id DESC
        LIMIT 1
      ) = 'accepted'
  );
$$;

REVOKE ALL ON FUNCTION public.has_current_telegram_consent(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_current_telegram_consent(BIGINT) TO service_role, authenticated;

CREATE OR REPLACE FUNCTION public.get_legal_consent_status()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid UUID := NULLIF(auth.jwt() ->> 'sub', '')::uuid;
  v_doc public.legal_documents%ROWTYPE;
  v_has BOOLEAN;
  v_prior_version TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_doc
  FROM public.legal_documents
  WHERE doc_type = 'terms_of_use'
    AND status = 'published'
    AND active_to_utc IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status', 'current',
      'document', NULL
    );
  END IF;

  v_has := public.has_current_legal_consent(v_uid);

  IF v_has THEN
    RETURN jsonb_build_object(
      'status', 'current',
      'document', jsonb_build_object(
        'id', v_doc.id,
        'doc_type', v_doc.doc_type,
        'version', v_doc.version,
        'title', v_doc.title,
        'body_markdown', v_doc.body_markdown,
        'content_sha256', v_doc.content_sha256,
        'changelog', v_doc.changelog,
        'published_at_utc', v_doc.published_at_utc
      )
    );
  END IF;

  SELECT c.document_version INTO v_prior_version
  FROM public.user_legal_consents c
  WHERE c.user_id = v_uid
    AND c.action = 'accepted'
  ORDER BY c.consented_at_utc DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'status', 'pending',
    'prior_version', v_prior_version,
    'document', jsonb_build_object(
      'id', v_doc.id,
      'doc_type', v_doc.doc_type,
      'version', v_doc.version,
      'title', v_doc.title,
      'body_markdown', v_doc.body_markdown,
      'content_sha256', v_doc.content_sha256,
      'changelog', v_doc.changelog,
      'published_at_utc', v_doc.published_at_utc
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_legal_consent_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_legal_consent_status() TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_legal_terms(p_document_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid UUID := NULLIF(auth.jwt() ->> 'sub', '')::uuid;
  v_doc public.legal_documents%ROWTYPE;
  v_org UUID;
  v_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_doc
  FROM public.legal_documents
  WHERE id = p_document_id;

  IF NOT FOUND
     OR v_doc.status <> 'published'
     OR v_doc.active_to_utc IS NOT NULL
     OR v_doc.doc_type <> 'terms_of_use'
  THEN
    -- INV-26 anti-oracle: same error for missing / wrong / stale
    RAISE EXCEPTION 'Document not available'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Idempotent double-click: latest action for this doc is already 'accepted'
  SELECT c.id INTO v_id
  FROM public.user_legal_consents c
  WHERE c.user_id = v_uid
    AND c.document_id = p_document_id
  ORDER BY c.consented_at_utc DESC, c.id DESC
  LIMIT 1;

  IF v_id IS NOT NULL AND (
    SELECT action FROM public.user_legal_consents WHERE id = v_id
  ) = 'accepted' THEN
    RETURN v_id;
  END IF;

  v_org := NULLIF(auth.jwt() -> 'app_metadata' ->> 'org_id', '')::UUID;

  -- clock_timestamp(): wall-clock so accept→withdraw→re-accept within one
  -- transaction still orders correctly (NOW() is transaction-stable).
  INSERT INTO public.user_legal_consents (
    user_id, organization_id, document_id, document_version,
    document_content_sha256, action, consented_at_utc
  ) VALUES (
    v_uid, v_org, v_doc.id, v_doc.version, v_doc.content_sha256, 'accepted',
    clock_timestamp()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_legal_terms(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_legal_terms(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.withdraw_legal_consent()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid UUID := NULLIF(auth.jwt() ->> 'sub', '')::uuid;
  v_doc public.legal_documents%ROWTYPE;
  v_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_doc
  FROM public.legal_documents
  WHERE doc_type = 'terms_of_use'
    AND status = 'published'
    AND active_to_utc IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document not available'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF NOT public.has_current_legal_consent(v_uid) THEN
    RAISE EXCEPTION 'Document not available'
      USING ERRCODE = 'no_data_found';
  END IF;

  INSERT INTO public.user_legal_consents (
    user_id,
    organization_id,
    document_id,
    document_version,
    document_content_sha256,
    action,
    consented_at_utc
  ) VALUES (
    v_uid,
    NULLIF(auth.jwt() -> 'app_metadata' ->> 'org_id', '')::UUID,
    v_doc.id,
    v_doc.version,
    v_doc.content_sha256,
    'withdrawn',
    clock_timestamp()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.withdraw_legal_consent() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.withdraw_legal_consent() TO authenticated;

CREATE OR REPLACE FUNCTION public.publish_legal_document(
  p_doc_type       TEXT,
  p_version        TEXT,
  p_title          TEXT,
  p_body_markdown  TEXT,
  p_changelog      TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
  v_id UUID;
  v_hash TEXT;
  v_lock_key BIGINT;
BEGIN
  -- service_role or SuperAdmin only
  IF current_setting('role', true) <> 'service_role'
     AND COALESCE((auth.jwt() -> 'app_metadata' ->> 'super_admin')::BOOLEAN, false) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'Document not available'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_doc_type NOT IN ('terms_of_use', 'privacy_policy', 'telegram_bot_terms') THEN
    RAISE EXCEPTION 'Document not available'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Serialize publish per doc_type (advisory lock)
  v_lock_key := hashtextextended(p_doc_type, 0);
  PERFORM pg_advisory_xact_lock(v_lock_key);

  v_hash := encode(extensions.digest(p_body_markdown, 'sha256'), 'hex');

  -- Close previous active published version
  UPDATE public.legal_documents
     SET active_to_utc = NOW()
   WHERE doc_type = p_doc_type
     AND status = 'published'
     AND active_to_utc IS NULL;

  INSERT INTO public.legal_documents (
    doc_type, version, title, body_markdown, content_sha256,
    changelog, status, published_at_utc, active_to_utc
  ) VALUES (
    p_doc_type, p_version, p_title, p_body_markdown, v_hash,
    p_changelog, 'published', NOW(), NULL
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_legal_document(TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_legal_document(TEXT, TEXT, TEXT, TEXT, TEXT)
  TO service_role;

-- Accept Telegram bot terms (service_role / webhook)
CREATE OR REPLACE FUNCTION public.accept_telegram_bot_terms(
  p_chat_id BIGINT,
  p_document_id UUID DEFAULT NULL,
  p_organization_id UUID DEFAULT NULL,
  p_driver_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc public.legal_documents%ROWTYPE;
  v_id UUID;
BEGIN
  IF p_document_id IS NOT NULL THEN
    SELECT * INTO v_doc FROM public.legal_documents WHERE id = p_document_id;
  ELSE
    SELECT * INTO v_doc
    FROM public.legal_documents
    WHERE doc_type = 'telegram_bot_terms'
      AND status = 'published'
      AND active_to_utc IS NULL
    LIMIT 1;
  END IF;

  IF NOT FOUND
     OR v_doc.status <> 'published'
     OR v_doc.active_to_utc IS NOT NULL
     OR v_doc.doc_type <> 'telegram_bot_terms'
  THEN
    RAISE EXCEPTION 'Document not available'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Idempotent accept for this version
  SELECT id INTO v_id
  FROM public.telegram_user_consents
  WHERE chat_id = p_chat_id
    AND consent_version = v_doc.version
    AND action = 'accepted'
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  INSERT INTO public.telegram_user_consents (
    chat_id, consent_version, document_id, document_content_sha256,
    organization_id, driver_id, accepted_via, action, accepted_at_utc
  ) VALUES (
    p_chat_id, v_doc.version, v_doc.id, v_doc.content_sha256,
    p_organization_id, p_driver_id, 'telegram_callback', 'accepted',
    clock_timestamp()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_telegram_bot_terms(BIGINT, UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_telegram_bot_terms(BIGINT, UUID, UUID, UUID)
  TO service_role;

CREATE OR REPLACE FUNCTION public.withdraw_telegram_bot_consent(p_chat_id BIGINT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc public.legal_documents%ROWTYPE;
  v_id UUID;
BEGIN
  SELECT * INTO v_doc
  FROM public.legal_documents
  WHERE doc_type = 'telegram_bot_terms'
    AND status = 'published'
    AND active_to_utc IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document not available'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF NOT public.has_current_telegram_consent(p_chat_id) THEN
    RAISE EXCEPTION 'Document not available'
      USING ERRCODE = 'no_data_found';
  END IF;

  INSERT INTO public.telegram_user_consents (
    chat_id, consent_version, document_id, document_content_sha256,
    accepted_via, action, accepted_at_utc
  ) VALUES (
    p_chat_id, v_doc.version, v_doc.id, v_doc.content_sha256,
    'telegram_revoke', 'withdrawn', clock_timestamp()
  )
  RETURNING id INTO v_id;

  -- Unbind chat so personal-data link is severed on revoke
  UPDATE public.telegram_chat_bindings
     SET unbound_at_utc = NOW()
   WHERE chat_id = p_chat_id
     AND unbound_at_utc IS NULL;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.withdraw_telegram_bot_consent(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.withdraw_telegram_bot_consent(BIGINT) TO service_role;

-- Active telegram bot terms payload for webhook
CREATE OR REPLACE FUNCTION public.get_active_telegram_bot_terms()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT jsonb_build_object(
        'id', id,
        'version', version,
        'title', title,
        'body_markdown', body_markdown,
        'content_sha256', content_sha256,
        'published_at_utc', published_at_utc
      )
      FROM public.legal_documents
      WHERE doc_type = 'telegram_bot_terms'
        AND status = 'published'
        AND active_to_utc IS NULL
      LIMIT 1
    ),
    'null'::jsonb
  );
$$;

REVOKE ALL ON FUNCTION public.get_active_telegram_bot_terms() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_telegram_bot_terms() TO service_role, authenticated;

-- ── 5. Consent-before-binding in consume_telegram_binding_token ──────────────

CREATE OR REPLACE FUNCTION public.consume_telegram_binding_token(
  p_code     TEXT,
  p_chat_id  BIGINT
)
RETURNS TABLE(driver_id UUID, organization_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token public.telegram_binding_tokens%ROWTYPE;
BEGIN
  -- LGPD: refuse binding without current telegram_bot_terms consent
  IF NOT public.has_current_telegram_consent(p_chat_id) THEN
    RAISE EXCEPTION 'LGPD consent required before binding.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_token
    FROM public.telegram_binding_tokens
   WHERE code = p_code
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token not found.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF NOW() > v_token.expires_at_utc THEN
    RAISE EXCEPTION 'Token has expired.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_token.used_at_utc IS NOT NULL THEN
    RAISE EXCEPTION 'Token has already been used.'
      USING ERRCODE = 'unique_violation';
  END IF;

  UPDATE public.telegram_chat_bindings
     SET unbound_at_utc = NOW()
   WHERE telegram_chat_bindings.chat_id = p_chat_id
     AND telegram_chat_bindings.unbound_at_utc IS NULL;

  UPDATE public.telegram_chat_bindings
     SET unbound_at_utc = NOW()
   WHERE telegram_chat_bindings.driver_id = v_token.driver_id
     AND telegram_chat_bindings.unbound_at_utc IS NULL;

  INSERT INTO public.telegram_chat_bindings (
    organization_id, driver_id, chat_id, bound_at_utc, binding_token_id
  ) VALUES (
    v_token.organization_id, v_token.driver_id, p_chat_id, NOW(), v_token.id
  );

  UPDATE public.telegram_binding_tokens
     SET used_at_utc = NOW()
   WHERE id = v_token.id;

  RETURN QUERY SELECT v_token.driver_id, v_token.organization_id;
END;
$$;

REVOKE ALL ON FUNCTION public.consume_telegram_binding_token(TEXT, BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_telegram_binding_token(TEXT, BIGINT)
  TO authenticated, service_role;

-- ── 6. Seed v1.0 documents ───────────────────────────────────────────────────

DO $$
DECLARE
  v_terms_body TEXT;
  v_bot_body TEXT;
  v_terms_hash TEXT;
  v_bot_hash TEXT;
BEGIN
  v_terms_body := $md$
# Termos de Uso e Contrato de Custódia de Dados (LGPD)

## 1. Papéis e Objeto
Ao utilizar o VeraProb, você aceita estes Termos e o tratamento de seus dados. A sua Organização atua como **Controladora** dos dados, e a VeraProb atua como **Operadora** (provedora da tecnologia), nos termos da Lei nº 13.709/2018 (LGPD).

## 2. Base Legal e Finalidade
O tratamento ocorre para a **Execução de Contrato** (Art. 7, II) de prestação de serviços de governança forense. A finalidade é garantir rastreabilidade, auditoria de SLA e segurança das operações de sua Organização. É vedado o uso de seus dados para finalidades secundárias (como marketing) por parte da VeraProb.

## 3. Dados Tratados e Compartilhamento
Tratamos seus identificadores de acesso (nome, e-mail, perfil) e logs de auditoria de suas ações no sistema. Para garantir a disponibilidade, os dados são armazenados em infraestruturas de nuvem parceiras (Suboperadores), que cumprem rígidos padrões de segurança e criptografia.

## 4. Segurança e Retenção
Seus dados de auditoria são selados criptograficamente (imutáveis). Eles serão retidos pelo período mínimo de 5 (cinco) anos para fins de defesa legal e compliance, ou conforme estipulado pelo contrato de sua Organização.

## 5. Seus Direitos
Você pode solicitar acesso, correção ou anonimização de seus dados contatando o Encarregado de Dados (DPO) da sua Organização ou através do suporte da VeraProb. A recusa deste termo impede o acesso técnico à plataforma.

## 6. Documentação Integral
Este aviso é um resumo para sua facilidade de leitura. Os limites de responsabilidade, propriedade intelectual e detalhamentos técnicos completos estão regidos pelos nossos [Termos de Serviço Completos e Política de Privacidade Integrais](https://veraprob.dev/legal), aos quais você também declara ciência ao aceitar este termo.
$md$;

  v_bot_body := $md$
# Termos do VeraProb Evidence Bot (LGPD)

Ao utilizar o VeraProb Evidence Bot no Telegram, você concorda que:

1. **Coleta de Dados:** Coletamos seu ID de chat do Telegram, fotos, vídeos, áudios e documentos enviados, além de metadados técnicos (data/hora do dispositivo e localização GPS se presente no arquivo EXIF).
2. **Intermediário:** O **Telegram** atua como intermediário/processador da mensagem; a VeraProb trata os dados recebidos via webhook para fins forenses.
3. **Finalidade:** Geração de evidências forenses em operações logísticas (prova de execução e conformidade).
4. **Segurança:** Evidências são seladas com hash SHA-256 e isoladas por organização.
5. **Compartilhamento:** Visíveis apenas a supervisores/administradores da sua organização no painel VeraProb.
6. **Retenção:** Mantidas pelo período necessário à auditoria contratual e conformidade legal.
7. **Revogação:** Envie /revoke no bot ou solicite ao supervisor. A revogação impede novos envios e desvincula o chat.

O aceite é registrado com a versão e o hash do texto vigente.
$md$;

  v_terms_hash := encode(extensions.digest(v_terms_body, 'sha256'), 'hex');
  v_bot_hash := encode(extensions.digest(v_bot_body, 'sha256'), 'hex');

  IF NOT EXISTS (
    SELECT 1 FROM public.legal_documents
    WHERE doc_type = 'terms_of_use' AND version = '1.0'
  ) THEN
    INSERT INTO public.legal_documents (
      doc_type, version, title, body_markdown, content_sha256,
      changelog, status, published_at_utc, active_to_utc
    ) VALUES (
      'terms_of_use', '1.0',
      'Termos de Uso e Contrato de Custódia de Dados',
      v_terms_body, v_terms_hash, NULL, 'published', NOW(), NULL
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.legal_documents
    WHERE doc_type = 'telegram_bot_terms' AND version = '1.0'
  ) THEN
    INSERT INTO public.legal_documents (
      doc_type, version, title, body_markdown, content_sha256,
      changelog, status, published_at_utc, active_to_utc
    ) VALUES (
      'telegram_bot_terms', '1.0',
      'Termos do VeraProb Evidence Bot (LGPD)',
      v_bot_body, v_bot_hash, NULL, 'published', NOW(), NULL
    );
  END IF;
END;
$$;

RESET client_min_messages;
