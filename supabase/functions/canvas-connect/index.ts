/**
 * Atlas — canvas-connect Edge Function (Deno)
 *
 * Stores / rotates / removes a user's Canvas Calendar Feed URL so the server-side
 * canvas-sync cron (0012) can pull assignments + events while every Atlas client is
 * closed. The feed URL is a CAPABILITY URL (its token IS the auth) — treated like a
 * secret: it lives in Supabase Vault (service-role only); the user's
 * canvas_connections row points at it by vault_secret_id — the URL value never
 * returns to any client. Mirrors google-connect exactly (real JWT verification,
 * Vault create/delete via 0012's wrapper fns, active row on POST / revoked on DELETE).
 *
 * POST   /functions/v1/canvas-connect   { "feedUrl": "<Canvas .ics feed url>", "spaceName": "School" }
 *        → verifies the caller's Supabase JWT (auth.getUser — REAL verification,
 *          not presence-only), stashes the feed URL in Vault, and upserts
 *          canvas_connections(status='active', space_name).  →  200 { ok: true, status: "active" }
 *
 * PATCH  /functions/v1/canvas-connect   { "spaceName": "Personal" }
 *        → verifies the JWT, updates ONLY canvas_connections.space_name (where
 *          unmatched feed items land). The Vault secret, etag/last_modified
 *          conditional-GET cache and status are untouched — a space change never
 *          resets sync.  →  200 { ok: true, status: <unchanged> }  (404 if no row)
 *
 * DELETE /functions/v1/canvas-connect
 *        → verifies the JWT, deletes the Vault secret, sets status='revoked'
 *          (the row survives so the client can show the paste form again).
 *          →  200 { ok: true, status: "revoked" }
 *
 * Auth:  Authorization: Bearer <Supabase user JWT>  (verified — this handles a live
 *        Canvas capability URL, so presence-only like `capture` is not enough).
 *
 * Env (auto-injected by the platform):
 *   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
 *
 * Deploy: supabase functions deploy canvas-connect --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { normalizeSpaceName } from "../_shared/canvas_space.ts";
import { checkRateLimit, tooManyRequests } from "../_shared/rate_limit.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, PATCH, DELETE, OPTIONS",
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
  if (req.method !== "POST" && req.method !== "PATCH" && req.method !== "DELETE") {
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

  // Service-role client: Vault RPCs + canvas_connections writes (bypasses RLS).
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Connect/rotate/disconnect are occasional credential operations. 20/hour is
  // generous for a human yet blocks a feed-URL-storing loop.
  const rl = await checkRateLimit(admin, userId, "canvas-connect", 20, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, CORS_HEADERS);

  // ── DISCONNECT ──────────────────────────────────────────────
  if (req.method === "DELETE") {
    const { data: existing } = await admin
      .from("canvas_connections")
      .select("vault_secret_id")
      .eq("user_id", userId)
      .maybeSingle();

    // Mark revoked (row survives so the client can offer the paste form again).
    const { error: updErr } = await admin
      .from("canvas_connections")
      .update({ status: "revoked", vault_secret_id: null, last_error: null })
      .eq("user_id", userId);
    if (updErr) {
      return json({ error: "Failed to update connection" }, 500);
    }

    // Best-effort secret removal; the row is already revoked regardless.
    if (existing?.vault_secret_id) {
      await admin.rpc("delete_canvas_secret", { secret_id: existing.vault_secret_id });
    }
    return json({ ok: true, status: "revoked" });
  }

  // ── CHANGE DESTINATION SPACE (PATCH) ────────────────────────
  if (req.method === "PATCH") {
    let spaceName: string | null;
    try {
      const body = await req.json();
      spaceName = normalizeSpaceName(body?.spaceName);
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }
    if (!spaceName) {
      return json({ error: "Body must contain a non-empty `spaceName` string" }, 400);
    }

    // Update ONLY the routing space. vault_secret_id, etag/last_modified (the
    // conditional-GET cache) and status are deliberately left alone so changing
    // where items land never resets sync or forces a re-fetch. `.select` lets us
    // 404 when the caller has no connection row to update.
    const { data: updated, error: updErr } = await admin
      .from("canvas_connections")
      .update({ space_name: spaceName })
      .eq("user_id", userId)
      .select("status");
    if (updErr) {
      return json({ error: "Failed to update connection" }, 500);
    }
    if (!updated || updated.length === 0) {
      return json({ error: "No Canvas connection to update" }, 404);
    }
    return json({ ok: true, status: updated[0].status });
  }

  // ── CONNECT (POST) ──────────────────────────────────────────
  let feedUrl: string;
  let spaceName: string;
  try {
    const body = await req.json();
    if (typeof body?.feedUrl !== "string" || !body.feedUrl.trim()) {
      return json({ error: "Body must contain a non-empty `feedUrl` string" }, 400);
    }
    feedUrl = body.feedUrl.trim();
    if (!/^https:\/\//i.test(feedUrl)) {
      return json({ error: "`feedUrl` must be an https Canvas feed link" }, 400);
    }
    // space_name is optional; default matches canvas_connections' 'School' default.
    spaceName = normalizeSpaceName(body?.spaceName) ?? "School";
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // Prior secret (if reconnecting) so we can clean it up after a successful swap.
  const { data: prior } = await admin
    .from("canvas_connections")
    .select("vault_secret_id")
    .eq("user_id", userId)
    .maybeSingle();
  const priorSecretId: string | null = prior?.vault_secret_id ?? null;

  // Stash the feed URL in Vault. A unique name avoids a collision when a user
  // reconnects before the old secret is removed.
  const secretName = `canvas_feed_url:${userId}:${Date.now()}`;
  const { data: newSecretId, error: secretErr } = await admin.rpc(
    "create_canvas_secret",
    { secret: feedUrl, name: secretName },
  );
  if (secretErr || !newSecretId) {
    return json({ error: "Failed to store credential" }, 500);
  }

  // Point the connection at the new secret and (re)activate it. space_name routes
  // unmatched Canvas items; last_error/etag/last_modified are cleared so a
  // re-pasted feed starts a fresh conditional-GET cycle.
  const { error: upsertErr } = await admin
    .from("canvas_connections")
    .upsert(
      {
        user_id: userId,
        vault_secret_id: newSecretId,
        space_name: spaceName,
        status: "active",
        last_error: null,
        etag: null,
        last_modified: null,
      },
      { onConflict: "user_id" },
    );
  if (upsertErr) {
    // Roll back the just-created secret so we never orphan it.
    await admin.rpc("delete_canvas_secret", { secret_id: newSecretId });
    return json({ error: "Failed to save connection" }, 500);
  }

  // Remove the previous secret now that the row points at the new one.
  if (priorSecretId && priorSecretId !== newSecretId) {
    await admin.rpc("delete_canvas_secret", { secret_id: priorSecretId });
  }

  return json({ ok: true, status: "active" });
});
