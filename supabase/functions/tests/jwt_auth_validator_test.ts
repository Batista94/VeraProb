/**
 * JWT Auth Validator Tests (INV-1, INV-26) — P0 cryptographic verification.
 *
 * Run with: deno test --allow-env --allow-net supabase/functions/tests/jwt_auth_validator_test.ts
 */

import { assertEquals, assert } from "@std/assert";
import {
  JWT_VERIFIER_TIMEOUT_MS,
  validateJwtAuth,
  type JwtClaimsVerifier,
} from "../shared/jwt_auth_validator.ts";
import {
  handleWithSecurity,
  type SecurityContext,
} from "../shared/handle_with_security.ts";
import {
  claimsOf,
  createFakeJwt,
  hangingVerifier,
  rejectAll,
  throwingVerifier,
} from "./jwt_test_helpers.ts";

const TEST_URL = "https://fake.supabase.co";
const EXPECTED_ISS = `${TEST_URL}/auth/v1`;

function withSupabaseUrl(fn: () => Promise<void>): Promise<void> {
  const orig = Deno.env.get("SUPABASE_URL");
  Deno.env.set("SUPABASE_URL", TEST_URL);
  if (!Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")) {
    Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fake-service-role");
  }
  return fn().finally(() => {
    if (orig === undefined) Deno.env.delete("SUPABASE_URL");
    else Deno.env.set("SUPABASE_URL", orig);
  });
}

function withEnv(
  pairs: Record<string, string | undefined>,
  fn: () => Promise<void>,
): Promise<void> {
  const saved: Record<string, string | undefined> = {};
  for (const key of Object.keys(pairs)) {
    saved[key] = Deno.env.get(key);
    const v = pairs[key];
    if (v === undefined) Deno.env.delete(key);
    else Deno.env.set(key, v);
  }
  return fn().finally(() => {
    for (const key of Object.keys(saved)) {
      const v = saved[key];
      if (v === undefined) Deno.env.delete(key);
      else Deno.env.set(key, v);
    }
  });
}

function createRequest(token: string | null, method = "POST"): Request {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }
  return new Request("https://example.com", { method, headers });
}

/** Exact claims verifier (no default merge) for negative claim cases. */
function exactClaims(claims: Record<string, unknown>): JwtClaimsVerifier {
  return (_token, _signal) => Promise.resolve({ claims });
}

function validClaims(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  const meta =
    typeof overrides.app_metadata === "object" &&
      overrides.app_metadata !== null &&
      !Array.isArray(overrides.app_metadata)
      ? overrides.app_metadata as Record<string, unknown>
      : {};
  const { app_metadata: _, ...rest } = overrides;
  return {
    iss: EXPECTED_ISS,
    aud: "authenticated",
    role: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 3600,
    sub: "user-1",
    session_id: "sess-1",
    ...rest,
    app_metadata: { org_id: "org-123", ...meta },
  };
}

function saClaims(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return validClaims({
    aal: "aal2",
    ...overrides,
    app_metadata: {
      super_admin: true,
      org_id: null,
      ...(typeof overrides.app_metadata === "object" &&
          overrides.app_metadata !== null &&
          !Array.isArray(overrides.app_metadata)
        ? overrides.app_metadata as Record<string, unknown>
        : {}),
    },
  });
}

/** handleWithSecurity creates a Supabase client (timers) — disable leak sanitize. */
function securityTest(
  name: string,
  fn: () => Promise<void>,
): void {
  Deno.test({
    name,
    sanitizeOps: false,
    sanitizeResources: false,
    fn,
  });
}

async function callHandle(
  token: string | null,
  opts: {
    requireAuth?: boolean;
    requireSuperAdmin?: boolean;
    requireAAL2?: boolean;
    verifier?: JwtClaimsVerifier;
  } = {},
): Promise<{ response: Response; handlerCalled: boolean }> {
  let handlerCalled = false;
  const response = await handleWithSecurity(
    createRequest(token),
    "test_jwt_p0",
    (_ctx: SecurityContext) => {
      handlerCalled = true;
      return Promise.resolve(new Response("ok", { status: 200 }));
    },
    opts.requireAuth ?? true,
    opts.requireSuperAdmin ?? false,
    opts.requireAAL2 ?? false,
    opts.verifier,
  );
  return { response, handlerCalled };
}

// ── Baseline crypto reject ───────────────────────────────────────────────────

securityTest("validateJwtAuth returns 404 when Authorization header is missing", async () => {
  await withSupabaseUrl(async () => {
    const result = await validateJwtAuth(createRequest(null), {
      verifier: rejectAll,
    });
    assert(!result.ok);
    assertEquals(result.response.status, 404);
  });
});

securityTest("validateJwtAuth returns 404 when token is malformed", async () => {
  await withSupabaseUrl(async () => {
    const result = await validateJwtAuth(createRequest("not-a-jwt"), {
      verifier: rejectAll,
    });
    assert(!result.ok);
    assertEquals(result.response.status, 404);
  });
});

securityTest("forged signature → 404", async () => {
  await withSupabaseUrl(async () => {
    const token = createFakeJwt(validClaims());
    const result = await validateJwtAuth(createRequest(token), {
      verifier: rejectAll,
    });
    assert(!result.ok);
    assertEquals(result.response.status, 404);
  });
});

securityTest("expired token → 404", async () => {
  await withSupabaseUrl(async () => {
    const claims = validClaims({
      exp: Math.floor(Date.now() / 1000) - 3600,
    });
    const result = await validateJwtAuth(createRequest(createFakeJwt(claims)), {
      verifier: exactClaims(claims),
    });
    assert(!result.ok);
    assertEquals(result.response.status, 404);
  });
});

securityTest("incorrect issuer → 404", async () => {
  await withSupabaseUrl(async () => {
    const claims = validClaims({ iss: "https://evil.example/auth/v1" });
    const result = await validateJwtAuth(createRequest(createFakeJwt(claims)), {
      verifier: exactClaims(claims),
    });
    assert(!result.ok);
    assertEquals(result.response.status, 404);
  });
});

securityTest("incorrect audience / role → 404", async () => {
  await withSupabaseUrl(async () => {
    for (const claims of [
      validClaims({ aud: "anon" }),
      validClaims({ role: "service_role" }),
    ]) {
      const result = await validateJwtAuth(
        createRequest(createFakeJwt(claims)),
        { verifier: exactClaims(claims) },
      );
      assert(!result.ok);
      assertEquals(result.response.status, 404);
    }
  });
});

securityTest("missing or invalid sub → 404", async () => {
  await withSupabaseUrl(async () => {
    for (const sub of [undefined, "", 42]) {
      const claims = validClaims({ sub });
      const result = await validateJwtAuth(
        createRequest(createFakeJwt(claims)),
        { verifier: exactClaims(claims) },
      );
      assert(!result.ok);
      assertEquals(result.response.status, 404);
    }
  });
});

securityTest("missing or invalid org_id (tenant) → 404", async () => {
  await withSupabaseUrl(async () => {
    for (const org_id of [undefined, "", 99]) {
      const claims = {
        iss: EXPECTED_ISS,
        aud: "authenticated",
        role: "authenticated",
        exp: Math.floor(Date.now() / 1000) + 3600,
        sub: "user-1",
        app_metadata: { org_id },
      };
      const result = await validateJwtAuth(
        createRequest(createFakeJwt(claims)),
        { verifier: exactClaims(claims) },
      );
      assert(!result.ok);
      assertEquals(result.response.status, 404);
    }
  });
});

securityTest("cryptographically valid tenant → correct context", async () => {
  await withSupabaseUrl(async () => {
    const claims = validClaims({
      sub: "user-legit",
      app_metadata: { org_id: "org-legitimate" },
    });
    const result = await validateJwtAuth(createRequest(createFakeJwt(claims)), {
      expectedOrgId: "org-legitimate",
      verifier: exactClaims(claims),
    });
    assert(result.ok);
    if (result.ok) {
      assertEquals(result.userId, "user-legit");
      assertEquals(result.orgId, "org-legitimate");
    }
  });
});

securityTest("tenant mismatch → identical anti-oracle 404 (INV-26)", async () => {
  await withSupabaseUrl(async () => {
    const claims = validClaims({
      app_metadata: { org_id: "org-attacker" },
    });
    const results = await Promise.all([
      validateJwtAuth(createRequest(null), { verifier: rejectAll }),
      validateJwtAuth(createRequest("garbage"), { verifier: rejectAll }),
      validateJwtAuth(createRequest(createFakeJwt(claims)), {
        expectedOrgId: "org-victim",
        verifier: exactClaims(claims),
      }),
    ]);
    const bodies: string[] = [];
    for (const r of results) {
      assert(!r.ok);
      assertEquals(r.response.status, 404);
      bodies.push(await r.response.text());
    }
    for (const body of bodies) {
      assertEquals(body, bodies[0]);
    }
    assertEquals(bodies[0], '{"error":"Not Found"}');
  });
});

securityTest("verifier throw → fail-closed 404", async () => {
  await withSupabaseUrl(async () => {
    const result = await validateJwtAuth(
      createRequest(createFakeJwt(validClaims())),
      { verifier: throwingVerifier },
    );
    assert(!result.ok);
    assertEquals(result.response.status, 404);
  });
});

securityTest("auth failure → handler never runs", async () => {
  await withSupabaseUrl(async () => {
    const { response, handlerCalled } = await callHandle(
      createFakeJwt(validClaims()),
      { verifier: rejectAll },
    );
    assertEquals(response.status, 404);
    assertEquals(handlerCalled, false);
  });
});

// ── Principals 1–9 ───────────────────────────────────────────────────────────

securityTest("P1. SA + org null + rota SA → handler executa", async () => {
  await withSupabaseUrl(async () => {
    await withEnv({ ENVIRONMENT: "dev" }, async () => {
      const claims = saClaims();
      const { response, handlerCalled } = await callHandle(
        createFakeJwt(claims),
        {
          requireSuperAdmin: true,
          verifier: exactClaims(claims),
        },
      );
      assertEquals(response.status, 200);
      assertEquals(handlerCalled, true);
    });
  });
});

securityTest("P2. SA + org null + rota tenant → 404", async () => {
  await withSupabaseUrl(async () => {
    const claims = saClaims();
    const { response, handlerCalled } = await callHandle(
      createFakeJwt(claims),
      {
        requireSuperAdmin: false,
        verifier: exactClaims(claims),
      },
    );
    assertEquals(response.status, 404);
    assertEquals(handlerCalled, false);
  });
});

securityTest("P3. não-SA + org null → 404", async () => {
  await withSupabaseUrl(async () => {
    const claims = validClaims({
      app_metadata: { org_id: null },
    });
    const result = await validateJwtAuth(createRequest(createFakeJwt(claims)), {
      verifier: exactClaims(claims),
    });
    assert(!result.ok);
    assertEquals(result.response.status, 404);
  });
});

securityTest("P4. SA + expectedOrgId → 404", async () => {
  await withSupabaseUrl(async () => {
    const claims = saClaims();
    const result = await validateJwtAuth(createRequest(createFakeJwt(claims)), {
      expectedOrgId: "org-any",
      allowOrglessSuperAdmin: true,
      verifier: exactClaims(claims),
    });
    assert(!result.ok);
    assertEquals(result.response.status, 404);
  });
});

securityTest("P5. SA sem AAL2 + rota SA (prod) → 404", async () => {
  await withSupabaseUrl(async () => {
    await withEnv({ ENVIRONMENT: "production" }, async () => {
      const claims = saClaims({ aal: "aal1" });
      const { response, handlerCalled } = await callHandle(
        createFakeJwt(claims),
        {
          requireSuperAdmin: true,
          verifier: exactClaims(claims),
        },
      );
      assertEquals(response.status, 404);
      assertEquals(handlerCalled, false);
    });
  });
});

securityTest("P6. híbrido SA+org string + rota tenant → 404", async () => {
  await withSupabaseUrl(async () => {
    const claims = validClaims({
      app_metadata: { super_admin: true, org_id: "org-hybrid" },
    });
    const { response, handlerCalled } = await callHandle(
      createFakeJwt(claims),
      { verifier: exactClaims(claims) },
    );
    assertEquals(response.status, 404);
    assertEquals(handlerCalled, false);
  });
});

securityTest("P7. híbrido SA+org string + rota SA → 404", async () => {
  await withSupabaseUrl(async () => {
    await withEnv({ ENVIRONMENT: "dev" }, async () => {
      const claims = validClaims({
        aal: "aal2",
        app_metadata: { super_admin: true, org_id: "org-hybrid" },
      });
      const { response, handlerCalled } = await callHandle(
        createFakeJwt(claims),
        {
          requireSuperAdmin: true,
          verifier: exactClaims(claims),
        },
      );
      assertEquals(response.status, 404);
      assertEquals(handlerCalled, false);
    });
  });
});

securityTest("P8. tenant + org string + rota tenant → sucesso", async () => {
  await withSupabaseUrl(async () => {
    const claims = validClaims({
      app_metadata: { org_id: "org-tenant" },
    });
    const { response, handlerCalled } = await callHandle(
      createFakeJwt(claims),
      { verifier: exactClaims(claims) },
    );
    assertEquals(response.status, 200);
    assertEquals(handlerCalled, true);
  });
});

securityTest("P9. tenant + org string + rota SA → 404", async () => {
  await withSupabaseUrl(async () => {
    await withEnv({ ENVIRONMENT: "dev" }, async () => {
      const claims = validClaims({
        aal: "aal2",
        app_metadata: { org_id: "org-tenant", super_admin: false },
      });
      const { response, handlerCalled } = await callHandle(
        createFakeJwt(claims),
        {
          requireSuperAdmin: true,
          verifier: exactClaims(claims),
        },
      );
      assertEquals(response.status, 404);
      assertEquals(handlerCalled, false);
    });
  });
});

// ── Deadline ─────────────────────────────────────────────────────────────────

securityTest("hanging verifier expires via validateJwtAuth deadline → 404", async () => {
  await withSupabaseUrl(async () => {
    const started = Date.now();
    const result = await validateJwtAuth(
      createRequest(createFakeJwt(validClaims())),
      { verifier: hangingVerifier },
    );
    const elapsed = Date.now() - started;
    assert(!result.ok);
    assertEquals(result.response.status, 404);
    assert(elapsed >= JWT_VERIFIER_TIMEOUT_MS - 100);
    assert(elapsed < JWT_VERIFIER_TIMEOUT_MS + 1500);
  });
});

securityTest(
  "default verifier: AbortSignal reaches fetch and aborts on deadline",
  async () => {
    await withSupabaseUrl(async () => {
      const origAnon = Deno.env.get("SUPABASE_ANON_KEY");
      Deno.env.set("SUPABASE_ANON_KEY", "fake-anon-key");
      try {
        let observed: AbortSignal | undefined;
        const fetchImpl: typeof fetch = (_input, init) => {
          const sig = init?.signal;
          observed = sig ?? undefined;
          return new Promise<Response>(() => {
            // hang until AbortSignal aborts the race in validateJwtAuth
          });
        };
        const result = await validateJwtAuth(
          createRequest(createFakeJwt(validClaims())),
          { fetchImpl },
        );
        assert(!result.ok);
        assertEquals(result.response.status, 404);
        assert(observed !== undefined, "fetchImpl must receive a signal");
        assertEquals(observed!.aborted, true, "signal must be aborted after deadline");
      } finally {
        if (origAnon === undefined) Deno.env.delete("SUPABASE_ANON_KEY");
        else Deno.env.set("SUPABASE_ANON_KEY", origAnon);
      }
    });
  },
);

// ── Wrapper auth config guard ────────────────────────────────────────────────

securityTest("guard: requireAuth=false + requireSuperAdmin → 404, no handler", async () => {
  await withSupabaseUrl(async () => {
    const { response, handlerCalled } = await callHandle(null, {
      requireAuth: false,
      requireSuperAdmin: true,
    });
    assertEquals(response.status, 404);
    assertEquals(handlerCalled, false);
  });
});

securityTest("guard: requireAuth=false + requireAAL2 → 404, no handler", async () => {
  await withSupabaseUrl(async () => {
    const { response, handlerCalled } = await callHandle(null, {
      requireAuth: false,
      requireAAL2: true,
    });
    assertEquals(response.status, 404);
    assertEquals(handlerCalled, false);
  });
});

securityTest("guard: requireAuth=false without SA/AAL2 → handler runs", async () => {
  await withSupabaseUrl(async () => {
    const { response, handlerCalled } = await callHandle(null, {
      requireAuth: false,
    });
    assertEquals(response.status, 200);
    assertEquals(handlerCalled, true);
  });
});

Deno.test({
  name: "super-admin-proxy still verifies via getUser (structural)",
  permissions: { read: true },
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const src = await Deno.readTextFile(
      new URL("../super-admin-proxy/index.ts", import.meta.url),
    );
    assert(src.includes("auth.getUser(bearerToken)"));
    assert(!src.includes("validateJwtAuth"));
    assert(!src.includes("getClaims"));
  },
});

securityTest("claimsOf helper produces verifier accepted by validateJwtAuth", async () => {
  await withSupabaseUrl(async () => {
    const partial = {
      sub: "u-helper",
      app_metadata: { org_id: "org-helper" },
    };
    const result = await validateJwtAuth(createRequest(createFakeJwt(partial)), {
      verifier: claimsOf(partial),
    });
    assert(result.ok);
    if (result.ok) {
      assertEquals(result.userId, "u-helper");
      assertEquals(result.orgId, "org-helper");
    }
  });
});
