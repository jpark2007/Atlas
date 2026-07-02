/**
 * Atlas — google-connect Edge Function (Deno)
 *
 * Stores / rotates / removes a user's Google Calendar refresh token so the
 * server-side google-sync cron can run while every Atlas client is closed.
 * The refresh token lives in Supabase Vault (service-role only); the user's
 * google_connections row points at it by vault_secret_id — the token value
 * never returns to any client.
 *
 * POST   /functions/v1/google-connect   { "refreshToken": "<google refresh token>" }
 *        → verifies the caller's Supabase JWT (auth.getUser — REAL verification,
 *          not presence-only), stashes the token in Vault, and upserts
 *          google_connections(status='active').  →  200 { ok: true, status: "active" }
 *
 * DELETE /functions/v1/google-connect
 *        → verifies the JWT, deletes the Vault secret, sets status='revoked'
 *          (the row survives so the client can show "Reconnect").
 *          →  200 { ok: true, status: "revoked" }
 *
 * Auth:  Authorization: Bearer <Supabase user JWT>  (verified — this handles a
 *        live Google credential, so presence-only like `capture` is not enough).
 *
 * Env (auto-injected by the platform):
 *   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
 *
 * Deploy: supabase functions deploy google-connect --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, DELETE, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST" && req.method !== "DELETE") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: "Server not configured" }, 500);
  }

  // ── Real JWT verification: resolve the caller from their Supabase token ──
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) {
    return json({ error: "Missing or invalid Authorization header" }, 401);
  }
  const authClient = createClient(supabaseUrl, anonKey);
  const { data: userData, error: userErr } = await authClient.auth.getUser(token);
  if (userErr || !userData?.user) {
    return json({ error: "Invalid or expired token" }, 401);
  }
  const userId = userData.user.id;

  // Service-role client: Vault RPCs + google_connections writes (bypasses RLS).
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ── DISCONNECT ──────────────────────────────────────────────
  if (req.method === "DELETE") {
    const { data: existing } = await admin
      .from("google_connections")
      .select("vault_secret_id")
      .eq("user_id", userId)
      .maybeSingle();

    // Mark revoked (row survives so the client can offer Reconnect).
    const { error: updErr } = await admin
      .from("google_connections")
      .update({ status: "revoked", vault_secret_id: null, last_error: null })
      .eq("user_id", userId);
    if (updErr) {
      return json({ error: "Failed to update connection" }, 500);
    }

    // Best-effort secret removal; the row is already revoked regardless.
    if (existing?.vault_secret_id) {
      await admin.rpc("delete_google_secret", { secret_id: existing.vault_secret_id });
    }
    return json({ ok: true, status: "revoked" });
  }

  // ── CONNECT (POST) ──────────────────────────────────────────
  let refreshToken: string;
  try {
    const body = await req.json();
    if (typeof body?.refreshToken !== "string" || !body.refreshToken.trim()) {
      return json({ error: "Body must contain a non-empty `refreshToken` string" }, 400);
    }
    refreshToken = body.refreshToken.trim();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // Prior secret (if reconnecting) so we can clean it up after a successful swap.
  const { data: prior } = await admin
    .from("google_connections")
    .select("vault_secret_id")
    .eq("user_id", userId)
    .maybeSingle();
  const priorSecretId: string | null = prior?.vault_secret_id ?? null;

  // Stash the refresh token in Vault. A unique name avoids a collision when a
  // user reconnects before the old secret is removed.
  const secretName = `google_refresh_token:${userId}:${Date.now()}`;
  const { data: newSecretId, error: secretErr } = await admin.rpc(
    "create_google_secret",
    { secret: refreshToken, name: secretName },
  );
  if (secretErr || !newSecretId) {
    return json({ error: "Failed to store credential" }, 500);
  }

  // Point the connection at the new secret and (re)activate it.
  const { error: upsertErr } = await admin
    .from("google_connections")
    .upsert(
      { user_id: userId, vault_secret_id: newSecretId, status: "active", last_error: null },
      { onConflict: "user_id" },
    );
  if (upsertErr) {
    // Roll back the just-created secret so we never orphan it.
    await admin.rpc("delete_google_secret", { secret_id: newSecretId });
    return json({ error: "Failed to save connection" }, 500);
  }

  // Remove the previous secret now that the row points at the new one.
  if (priorSecretId && priorSecretId !== newSecretId) {
    await admin.rpc("delete_google_secret", { secret_id: priorSecretId });
  }

  return json({ ok: true, status: "active" });
});
