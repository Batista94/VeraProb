BEGIN;
SELECT plan(5);

-- Setup
INSERT INTO public.organizations (id, name, cnpj)
VALUES ('11111111-1111-1111-1111-111111111111'::uuid, 'Test Org', '12345678901234')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue (id, organization_id, vehicle_plate, verdict_evidence, status, ledger_entry_id, set_id, contract_id)
VALUES (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'ABC1234',
  '{"fine_cents": 150000, "delta_value": 85, "threshold_value": 80, "primary_evidence_timestamp_utc": "2026-08-21T10:00:00Z", "clause_ref": "VEL-123", "primary_evidence_lat": -23.5, "primary_evidence_lng": -46.6}'::jsonb,
  'pending',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaab'::uuid,
  'set-test-001',
  'contract-test-001'
);

-- Token 1: Valid
INSERT INTO public.dispute_portal_tokens (id, organization_id, queue_entry_id, token, access_count, max_access_count, expires_at_utc, created_by_user_id)
VALUES ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444444', 0, 5, NOW() + INTERVAL '1 day', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid);

-- Token 2: Expired
-- created_at_utc set explicitly to 2 days ago so expires_at_utc (1 day ago) satisfies
-- chk_dpt_expires_window: expires > created AND expires <= created + 48h
INSERT INTO public.dispute_portal_tokens (id, organization_id, queue_entry_id, token, access_count, max_access_count, created_at_utc, expires_at_utc, created_by_user_id)
VALUES ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', '66666666-6666-6666-6666-666666666666', 0, 5, NOW() - INTERVAL '2 days', NOW() - INTERVAL '1 day', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid);

-- Token 3: Revoked
INSERT INTO public.dispute_portal_tokens (id, organization_id, queue_entry_id, token, access_count, max_access_count, expires_at_utc, revoked_at_utc, created_by_user_id)
VALUES ('77777777-7777-7777-7777-777777777777', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', '88888888-8888-8888-8888-888888888888', 0, 5, NOW() + INTERVAL '1 day', NOW(), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid);

-- Token 4: Exhausted
INSERT INTO public.dispute_portal_tokens (id, organization_id, queue_entry_id, token, access_count, max_access_count, expires_at_utc, created_by_user_id)
VALUES ('99999999-9999-9999-9999-999999999999', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 5, 5, NOW() + INTERVAL '1 day', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid);

-- Success Case
SELECT is(
  (public.read_infraction_context('44444444-4444-4444-4444-444444444444'::uuid) ->> 'penalty_value_cents')::int,
  150000,
  'read_infraction_context correctly extracts data for a valid token'
);

-- Anti-Oracle Error Checking
SELECT throws_ok(
  $$SELECT public.read_infraction_context('00000000-0000-0000-0000-000000000000'::uuid)$$,
  '42501',
  'Portal access denied.',
  'Missing token returns 42501'
);

SELECT throws_ok(
  $$SELECT public.read_infraction_context('66666666-6666-6666-6666-666666666666'::uuid)$$,
  '42501',
  'Portal access denied.',
  'Expired token returns 42501'
);

SELECT throws_ok(
  $$SELECT public.read_infraction_context('88888888-8888-8888-8888-888888888888'::uuid)$$,
  '42501',
  'Portal access denied.',
  'Revoked token returns 42501'
);

SELECT throws_ok(
  $$SELECT public.read_infraction_context('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid)$$,
  '42501',
  'Portal access denied.',
  'Exhausted token returns 42501'
);

SELECT * FROM finish();
ROLLBACK;
