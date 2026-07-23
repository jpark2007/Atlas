/**
 * Atlas — feeds-connect Edge Function (Deno)
 *
 * The multi-feed generalization of canvas-connect (0012 → 0040). Stores / edits /
 * removes a user's calendar feeds — Canvas OR any generic ICS feed (Schoology,
 * a personal .ics, …). Each feed URL is a CAPABILITY URL (its token IS the auth),
 * treated like a secret: it lives in Supabase Vault (service-role only, via the
 * shared create/read/delete_canvas_secret wrappers from 0012); the user's
 * calendar_feeds row (0040) points at it by vault_secret_id — the URL value never
 * returns to any client.
 *
 * Unlike canvas-connect (ONE row per user, upsert), a user may have MANY feeds, so
 * POST INSERTS a new row each time. The 0040 partial unique index enforces a single
 * ACTIVE Canvas feed per user; generic ICS feeds are unlimited.
 *
 * POST   /functions/v1/feeds-connect
 *        { "feedUrl": "<https .ics url>", "feedType": "canvas"|"ics",
 *          "displayName": "Canvas", "spaceName": "School" }
 *        → verify the caller's Supabase JWT, stash the feed URL in Vault, INSERT a
 *          calendar_feeds(status='active') row.  →  200 { ok, id, status:"active" }
 *
 * PATCH  /functions/v1/feeds-connect
 *        { "id": "<feed id>", "spaceName"?: "Personal", "displayName"?: "Schoology" }
 *        → verify the JWT, update ONLY display_name / space_name on the caller's own
 *          row. Vault secret, etag/last_modified cache and status are untouched — an
 *          edit never resets sync.  →  200 { ok, status } (404 if the row isn't theirs)
 *
 * DELETE /functions/v1/feeds-connect   { "id": "<feed id>" }
 *        → verify the JWT, set status='revoked' + null vault_secret_id on the caller's
 *          own row (the row survives), best-effort delete the Vault secret.
 *          →  200 { ok, status:"revoked" }
 *
 * Auth:  Authorization: Bearer <Supabase user JWT>  (really verified — a live feed
 *        capability URL is handled here, so presence-only is not enough).
 *
 * Env (auto-injected):  SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
 *
 * Deploy: supabase functions deploy feeds-connect --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { normalizeSpaceName } from "../_shared/canvas_space.ts";
import { assertPublicUrl, BlockedUrlError } from "../_shared/url_guard.ts";
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

  // Service-role client: Vault RPCs + calendar_feeds writes (bypasses RLS).
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Connect/edit/disconnect are occasional credential operations. 20/hour is
  // generous for a human yet blocks a feed-URL-storing loop (same limiter as
  // canvas-connect, separate budget key).
  const rl = await checkRateLimit(admin, userId, "feeds-connect", 20, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, CORS_HEADERS);

  // ── DISCONNECT (DELETE) ─────────────────────────────────────
  if (req.method === "DELETE") {
    let feedId: string;
    try {
      const body = await req.json();
      if (typeof body?.id !== "string" || !body.id.trim()) {
        return json({ error: "Body must contain a non-empty `id` string" }, 400);
      }
      feedId = body.id.trim();
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }

    // Only the caller's own row (RLS is bypassed by service_role, so scope explicitly).
    const { data: existing } = await admin
      .from("calendar_feeds")
      .select("vault_secret_id")
      .eq("id", feedId)
      .eq("user_id", userId)
      .maybeSingle();

    // Mark revoked (row survives so the client keeps the card / can re-paste).
    const { data: updated, error: updErr } = await admin
      .from("calendar_feeds")
      .update({ status: "revoked", vault_secret_id: null, last_error: null })
      .eq("id", feedId)
      .eq("user_id", userId)
      .select("id");
    if (updErr) {
      return json({ error: "Failed to update feed" }, 500);
    }
    if (!updated || updated.length === 0) {
      return json({ error: "No such feed to disconnect" }, 404);
    }

    // Best-effort secret removal; the row is already revoked regardless.
    if (existing?.vault_secret_id) {
      await admin.rpc("delete_canvas_secret", { secret_id: existing.vault_secret_id });
    }
    return json({ ok: true, status: "revoked" });
  }

  // ── EDIT (PATCH) — display name / destination space ─────────
  if (req.method === "PATCH") {
    let feedId: string;
    let spaceName: string | null;
    let displayName: string | null;
    try {
      const body = await req.json();
      if (typeof body?.id !== "string" || !body.id.trim()) {
        return json({ error: "Body must contain a non-empty `id` string" }, 400);
      }
      feedId = body.id.trim();
      spaceName = normalizeSpaceName(body?.spaceName);
      displayName = typeof body?.displayName === "string" && body.displayName.trim()
        ? body.displayName.trim()
        : null;
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }
    if (!spaceName && !displayName) {
      return json({ error: "Body must contain a `spaceName` and/or `displayName` to change" }, 400);
    }

    // Update ONLY the editable fields. vault_secret_id, etag/last_modified (the
    // conditional-GET cache) and status are left alone so an edit never resets sync.
    const patch: Record<string, string> = {};
    if (spaceName) patch.space_name = spaceName;
    if (displayName) patch.display_name = displayName;
    const { data: updated, error: updErr } = await admin
      .from("calendar_feeds")
      .update(patch)
      .eq("id", feedId)
      .eq("user_id", userId)
      .select("status");
    if (updErr) {
      return json({ error: "Failed to update feed" }, 500);
    }
    if (!updated || updated.length === 0) {
      return json({ error: "No such feed to update" }, 404);
    }
    return json({ ok: true, status: updated[0].status });
  }

  // ── CONNECT (POST) — add a new feed ─────────────────────────
  let feedUrl: string;
  let feedType: string;
  let displayName: string;
  let spaceName: string;
  try {
    const body = await req.json();
    if (typeof body?.feedUrl !== "string" || !body.feedUrl.trim()) {
      return json({ error: "Body must contain a non-empty `feedUrl` string" }, 400);
    }
    feedUrl = body.feedUrl.trim();
    if (!/^https:\/\//i.test(feedUrl)) {
      return json({ error: "`feedUrl` must be an https feed link" }, 400);
    }
    feedType = body?.feedType === "canvas" ? "canvas" : "ics";
    // Soft shape hint for Canvas only (never a hard reject): a Canvas Calendar Feed
    // URL is a .ics capability link. Generic ICS feeds are accepted permissively —
    // any https URL (schools name .ics feeds all sorts of ways).
    displayName = typeof body?.displayName === "string" && body.displayName.trim()
      ? body.displayName.trim()
      : (feedType === "canvas" ? "Canvas" : "Calendar");
    spaceName = normalizeSpaceName(body?.spaceName) ?? "School";
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // SSRF defense-in-depth: reject at connect time any feed URL whose host resolves
  // to a private/loopback/link-local address (feeds-sync guards again at fetch
  // time). A real school feed host resolves to a public address and passes.
  try {
    await assertPublicUrl(feedUrl);
  } catch (err) {
    if (err instanceof BlockedUrlError) {
      return json({ error: "`feedUrl` is not a reachable public feed link" }, 400);
    }
    throw err;
  }

  // Stash the feed URL in Vault. A unique name avoids a collision across feeds.
  const secretName = `calendar_feed_url:${userId}:${Date.now()}`;
  const { data: newSecretId, error: secretErr } = await admin.rpc(
    "create_canvas_secret",
    { secret: feedUrl, name: secretName },
  );
  if (secretErr || !newSecretId) {
    return json({ error: "Failed to store credential" }, 500);
  }

  // INSERT a new feed row. The 0040 partial unique index rejects a SECOND active
  // Canvas feed (one Canvas card per user); a generic ICS insert is unlimited.
  const { data: inserted, error: insErr } = await admin
    .from("calendar_feeds")
    .insert({
      user_id: userId,
      feed_type: feedType,
      display_name: displayName,
      space_name: spaceName,
      vault_secret_id: newSecretId,
      status: "active",
    })
    .select("id")
    .single();
  if (insErr || !inserted) {
    // Roll back the just-created secret so we never orphan it.
    await admin.rpc("delete_canvas_secret", { secret_id: newSecretId });
    // 23505 = unique_violation → a second active Canvas feed.
    if ((insErr as { code?: string } | null)?.code === "23505") {
      return json({ error: "You already have an active Canvas feed. Remove it first to add another." }, 409);
    }
    return json({ error: "Failed to save feed" }, 500);
  }

  return json({ ok: true, id: inserted.id, status: "active" });
});
