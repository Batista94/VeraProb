/**
 * Integration Test for super-admin-proxy (TDD Cycle)
 * 
 * Verifies the download_original_evidence action and audit logging.
 * Run with: deno test --allow-env --allow-net --allow-read supabase/functions/tests/super_admin_proxy_integration_test.ts
 */

import { assertEquals, assert } from "jsr:@std/assert@1";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "http://127.0.0.1:54321";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

// Test setup
const supabase = createClient(SUPABASE_URL, ANON_KEY);
const adminClient = createClient(SUPABASE_URL, SERVICE_KEY);

Deno.test({
  name: "SuperAdmin Proxy - download_original_evidence fails when action is missing or invalid",
  async fn() {
    // 1. Get SuperAdmin token
    const { data: authData } = await supabase.auth.signInWithPassword({
      email: "master@veraprob.dev",
      password: "veraprob123!",
    });
    const token = authData.session?.access_token;
    assert(token, "Failed to get SuperAdmin token");

    // 2. Call proxy with invalid action
    const res = await fetch(`${SUPABASE_URL}/functions/v1/super-admin-proxy`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`
      },
      body: JSON.stringify({ action: "invalid_action" })
    });

    assertEquals(res.status, 400);
    const json = await res.json();
    assertEquals(json.error, "Unknown action");
  }
});

Deno.test({
  name: "SuperAdmin Proxy - download_original_evidence returns file and logs audit (INV-7, INV-9)",
  async fn() {
    // 1. Get SuperAdmin token
    const { data: authData } = await supabase.auth.signInWithPassword({
      email: "master@veraprob.dev",
      password: "veraprob123!",
    });
    const token = authData.session?.access_token;
    assert(token, "Failed to get SuperAdmin token");

    // 2. Get the latest evidence ID
    const { data: evidenceList } = await adminClient
      .from("telegram_evidence_uploads")
      .select("id")
      .order("uploaded_at_utc", { ascending: false })
      .limit(1);
    
    assert(evidenceList && evidenceList.length > 0, "No evidence found to test with");
    const evidenceId = evidenceList[0].id;

    // 3. Call proxy to download
    const ticketId = `TICKET-${Date.now()}`;
    const justification = "Auditoria forense automatizada - TDD";
    
    const res = await fetch(`${SUPABASE_URL}/functions/v1/super-admin-proxy`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`
      },
      body: JSON.stringify({
        action: "download_original_evidence",
        params: { evidence_id: evidenceId },
        ticket_id: ticketId,
        justification: justification
      })
    });

    // Currently this will fail (400 Unknown Action) because it's not implemented yet.
    assertEquals(res.status, 200, `Expected 200 OK, got ${res.status}`);
    
    // Check if it's a binary file
    const contentType = res.headers.get("content-type");
    assert(contentType?.includes("image/") || contentType?.includes("application/"), "Response is not a file");
    
    // Read the binary data to consume the stream
    const buffer = await res.arrayBuffer();
    assert(buffer.byteLength > 0, "Downloaded file is empty");

    // 4. Verify the Audit Log (INV-7)
    // Wait a brief moment for the fire-and-forget log to complete
    await new Promise(resolve => setTimeout(resolve, 500));
    
    const { data: logs } = await adminClient
      .from("super_admin_access_log")
      .select("*")
      .eq("ticket_id", ticketId)
      .eq("action", "download_original_evidence");

    assert(logs && logs.length === 1, "Audit log was not created");
    assertEquals(logs[0].justification, justification);
  }
});
