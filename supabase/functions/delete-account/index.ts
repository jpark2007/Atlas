/**
 * Atlas — delete-account Edge Function (Deno)
 *
 * Permanently deletes the signed-in user and everything they own. A client can't
 * delete its own auth user, so this runs with the service role: it verifies the
 * caller's JWT, removes their Google/Canvas Vault secrets (the only rows NOT
 * covered by `on delete cascade`), then calls auth.admin.deleteUser(uid). Every
 * user-scoped table (spaces, projects, tasks, events, notes, connections,
 * profiles, …) cascades off auth.users, so the delete wipes them automatically.
 *
 * POST /functions/v1/delete-account
 *      → verifies the caller's Supabase JWT (auth.getUser — REAL verification,
 *        not presence-only), purges Vault secrets, deletes the auth user.
 *        →  200 { ok: true }
 *
 * Auth:  Authorization: Bearer <Supabase user JWT>  (verified — this destroys the
 *        account, so presence-only like `capture` is not enough).
 *
 * Env (auto-injected by the platform):
 *   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
 *
 * Deploy: supabase functions deploy delete-account --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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
  if (req.method !== "POST") {
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

  // Service-role client: Vault RPCs + auth admin (bypasses RLS).
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Vault secrets are pointed at by *_connections.vault_secret_id but are NOT
  // FKs to auth.users, so the cascade won't remove them. Capture the ids now,
  // but purge only AFTER the user delete succeeds — purging first destroyed a
  // live account's Google sync when deleteUser failed (2026-07-15).
  // google_connections is multi-row now (multi-account, 0028): collect EVERY
  // connection's secret id, not a single row.
  const { data: gRows } = await admin
    .from("google_connections")
    .select("vault_secret_id")
    .eq("user_id", userId);
  const googleSecretIds = (gRows ?? [])
    .map((r) => r.vault_secret_id as string | null)
    .filter((id): id is string => !!id);
  const { data: c } = await admin
    .from("canvas_connections")
    .select("vault_secret_id")
    .eq("user_id", userId)
    .maybeSingle();

  // Delete the auth user (hard delete). Every user-scoped table cascades off
  // auth.users, so this wipes spaces/projects/tasks/events/notes/connections
  // in one shot.
  const { error: delErr } = await admin.auth.admin.deleteUser(userId);
  if (delErr) {
    console.error("delete-account: deleteUser failed", userId, delErr);
    return json({ error: "Failed to delete account" }, 500);
  }

  // Account is gone — now purge the orphaned Vault secrets (best-effort; a
  // leftover secret points at nothing and must never fail the response).
  for (const secretId of googleSecretIds) {
    await admin.rpc("delete_google_secret", { secret_id: secretId });
  }
  if (c?.vault_secret_id) {
    await admin.rpc("delete_canvas_secret", { secret_id: c.vault_secret_id });
  }

  return json({ ok: true });
});
