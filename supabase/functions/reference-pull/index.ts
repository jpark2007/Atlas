/**
 * Atlas — reference-pull Edge Function (Deno)  ·  On-demand "Sync now" pull
 *
 * Pulls the latest Google-Doc content for ONE project_reference on demand — the
 * teeth behind the Mac's "Sync now" button (design doc §Server-flow 3). Where the
 * 5-min cron (google-sync) sweeps everyone, this pulls exactly the caller's one
 * reference right now, reusing the shared pull machinery (`_shared/google_pull.ts`)
 * so the behavior is identical to a cron tick for that reference.
 *
 * POST /functions/v1/reference-pull
 *   { "referenceId": "<uuid>" }
 *
 *   200 { ok: true, changed }   — pull ran (changed=true) or a no-op recency check (false).
 *   400/401/404 { error }        — bad input / bad token / no such doc_note reference.
 *   409 { error: "revoked" }     — the stored Google refresh token is dead (re-consent).
 *   409 { error: "trashed" }     — the backing Doc is in the Drive trash.
 *   502 { error }                — token mint / Drive / Docs failure.
 *
 * Auth: Authorization: Bearer <Supabase user JWT> (verified — this drives a live
 *       Google credential, so presence-only is not enough). The Google access token
 *       is minted server-side from the user's stored refresh token (Vault), the same
 *       token the pull cron uses.
 *
 * Env (SUPABASE_* auto-injected; GOOGLE_* are project-level function secrets):
 *   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
 *   GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
 *
 * Deploy: supabase functions deploy reference-pull --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type DocNoteRef, InvalidGrantError, mintAccessToken, pullDocNoteReference } from "../_shared/google_pull.ts";

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
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const clientId = Deno.env.get("GOOGLE_CLIENT_ID");
  const clientSecret = Deno.env.get("GOOGLE_CLIENT_SECRET");
  if (!supabaseUrl || !anonKey || !serviceKey || !clientId || !clientSecret) {
    return json({ error: "Server not configured" }, 500);
  }

  // ── Real JWT verification: resolve the caller from their Supabase token ──
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) return json({ error: "Missing or invalid Authorization header" }, 401);
  const authClient = createClient(supabaseUrl, anonKey);
  const { data: userData, error: userErr } = await authClient.auth.getUser(token);
  if (userErr || !userData?.user) return json({ error: "Invalid or expired token" }, 401);
  const userId = userData.user.id;

  // ── Input ──
  let referenceId: string;
  try {
    const b = await req.json();
    if (typeof b?.referenceId !== "string" || !b.referenceId.trim()) {
      return json({ error: "Body must contain a `referenceId` string" }, 400);
    }
    referenceId = b.referenceId.trim();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // Service-role client: Vault RPC + owner-scoped reads/writes (bypasses RLS, so
  // every query is explicitly filtered by the verified user_id).
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ── Load the caller's doc_note reference ──
  const { data: refRow, error: refErr } = await admin
    .from("project_references")
    .select("id, drive_file_id, note_id, mime_type, modified_time")
    .eq("id", referenceId)
    .eq("user_id", userId)
    .eq("kind", "doc_note")
    .maybeSingle();
  if (refErr) return json({ error: "Failed to load reference" }, 500);
  if (!refRow || !refRow.drive_file_id) {
    return json({ error: "Reference is not linked to a Google Doc" }, 404);
  }
  const ref: DocNoteRef = {
    id: refRow.id as string,
    drive_file_id: refRow.drive_file_id as string,
    note_id: (refRow.note_id as string | null) ?? null,
    mime_type: (refRow.mime_type as string | null) ?? null,
    modified_time: (refRow.modified_time as string | null) ?? null,
  };

  // ── Mint a Google access token from the user's stored refresh token ──
  let accessToken: string;
  try {
    accessToken = await mintAccessToken(admin, userId, clientId, clientSecret);
  } catch (e) {
    if (e instanceof InvalidGrantError) return json({ error: "revoked" }, 409);
    return json({ error: `Token mint failed: ${String((e as Error)?.message ?? e).slice(0, 200)}` }, 502);
  }

  // ── Pull this one reference (shared machinery — identical to a cron tick) ──
  try {
    const { changed } = await pullDocNoteReference(admin, userId, accessToken, ref, new Date().toISOString(), false);
    return json({ ok: true, changed });
  } catch (e) {
    const message = String((e as Error)?.message ?? e);
    if (message.includes("trashed")) return json({ error: "trashed" }, 409);
    return json({ error: message.slice(0, 200) }, 502);
  }
});
