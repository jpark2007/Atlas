/**
 * Atlas — drive-writeback Edge Function (Deno)  ·  Notes → Google Doc write-back
 *
 * Pushes an Atlas note's Markdown back into its linked Google Doc, with a hard
 * staleness guard so a Google-side edit is NEVER blind-overwritten. Called by the
 * Mac when a linked Doc-note is saved (design doc §Server-flow 4).
 *
 * The note's body IS Markdown (the Mac renders it via RichDoc ⇄ Markdown; the
 * server only moves Markdown bytes). This function does the Drive side only — it
 * does NOT touch `notes.body` (the client already persisted that through its normal
 * note-save/upsert). It uploads Markdown to Drive with conversion back to a Doc and
 * re-baselines the reference's `modified_time` so the pull cron doesn't re-pull the
 * echo (the notes analogue of the calendar C2 storm guard).
 *
 * POST /functions/v1/drive-writeback
 *   { "noteId": "<uuid>", "markdown": "<note body as markdown>",
 *     "expectedModifiedTime": "<RFC3339 the client edited against>",
 *     "overwrite": false }
 *
 *   `overwrite: true` skips the staleness guard — the client sends it only after the
 *   user explicitly chose "Overwrite Google Doc" on a stale conflict. Absent/false is
 *   the safe default: a diverged Drive copy is refused, never blind-overwritten.
 *
 *   200 { ok: true,  modifiedTime }          — Doc updated; new baseline stored.
 *   409 { ok: false, error: "stale",         — Drive moved past the client's baseline.
 *         driveModifiedTime, expectedModifiedTime }  Never overwrites — client must
 *                                                     refresh (pull) then retry.
 *   4xx/5xx { error }                          — bad input / no link / token / drive error.
 *
 * Auth: Authorization: Bearer <Supabase user JWT> (verified — this drives a live
 *       Google credential, so presence-only is not enough). The Google access token
 *       is minted server-side from the user's stored google_connections refresh
 *       token (Vault) — the same token the pull cron uses, so it must carry the
 *       `drive.file` scope (re-consent after the scope add).
 *
 * Env (SUPABASE_* auto-injected; GOOGLE_* set via `supabase secrets set`):
 *   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
 *   GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
 *
 * Deploy: supabase functions deploy drive-writeback --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  findDocumentTab,
  IslandMismatchError,
  readTabs,
  renderTabRequests,
  UnmappedImageError,
} from "../_shared/doc_tabs.ts";

const GOOGLE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const DRIVE_BASE = "https://www.googleapis.com/drive/v3";
const DRIVE_UPLOAD = "https://www.googleapis.com/upload/drive/v3";
const DOCS_BASE = "https://docs.googleapis.com/v1";
const GOOGLE_DOC_MIME = "application/vnd.google-apps.document";

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

// Refresh a stored refresh token into an access token (mirrors google-sync).
async function refreshAccessToken(refreshToken: string, clientId: string, clientSecret: string): Promise<string> {
  const body = new URLSearchParams({
    refresh_token: refreshToken,
    client_id: clientId,
    client_secret: clientSecret,
    grant_type: "refresh_token",
  });
  const res = await fetch(GOOGLE_TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`token refresh ${res.status}: ${text.slice(0, 200)}`);
  const parsed = JSON.parse(text);
  if (!parsed.access_token) throw new Error("token refresh: no access_token");
  return parsed.access_token as string;
}

// Two RFC3339 instants are "the same" iff they land on the same millisecond. Drive
// echoes the exact string we baseline-stored, but compare by epoch to be robust to
// formatting (trailing zeros, Z vs +00:00).
function sameInstant(a: string | null | undefined, b: string | null | undefined): boolean {
  if (!a || !b) return false;
  const ta = new Date(a).getTime();
  const tb = new Date(b).getTime();
  return Number.isFinite(ta) && Number.isFinite(tb) && ta === tb;
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
  let noteId: string;
  let markdown: string;
  let expectedModifiedTime: string | null;
  let overwrite: boolean;
  let tabId: string | null;
  try {
    const b = await req.json();
    if (typeof b?.noteId !== "string" || !b.noteId.trim()) {
      return json({ error: "Body must contain a `noteId` string" }, 400);
    }
    if (typeof b?.markdown !== "string") {
      return json({ error: "Body must contain a `markdown` string" }, 400);
    }
    noteId = b.noteId.trim();
    markdown = b.markdown;
    expectedModifiedTime =
      typeof b?.expectedModifiedTime === "string" && b.expectedModifiedTime.trim()
        ? b.expectedModifiedTime.trim()
        : null;
    overwrite = b?.overwrite === true;
    tabId =
      typeof b?.tabId === "string" && b.tabId.trim() ? b.tabId.trim() : null;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // Service-role client: Vault RPC + owner-scoped reads/writes (bypasses RLS, so
  // every query is explicitly filtered by the verified user_id).
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ── Resolve the linked Doc: a project_references row that backs this note ──
  // A note may back SEVERAL references (same Doc imported into multiple projects,
  // v2) — they all point at the same drive_file_id, so take the oldest as canonical
  // rather than erroring on the multi-row case.
  const { data: refRows, error: refErr } = await admin
    .from("project_references")
    .select("id, drive_file_id, modified_time, kind, sync_state")
    .eq("user_id", userId)
    .eq("note_id", noteId)
    .eq("kind", "doc_note")
    .order("created_at", { ascending: true })
    .limit(1);
  if (refErr) return json({ error: "Failed to load reference" }, 500);
  const refRow = refRows?.[0];
  if (!refRow || !refRow.drive_file_id) {
    return json({ error: "Note is not linked to a Google Doc" }, 404);
  }
  // Pending belt: the first pull hasn't landed, so there's no content/baseline to write
  // against yet. Refuse (unless the user chose to overwrite) — the client locks the
  // editor while pending, this guards the race + any other caller.
  if (refRow.sync_state === "pending" && !overwrite) {
    return json({ ok: false, error: "not_synced" }, 409);
  }
  const fileId = refRow.drive_file_id as string;
  // Prefer the client's baseline; fall back to the server's stored baseline.
  const baseline: string | null = expectedModifiedTime ?? (refRow.modified_time as string | null);

  // ── Mint a Google access token from the user's stored refresh token ──
  const { data: conn, error: connErr } = await admin
    .from("google_connections")
    .select("vault_secret_id")
    .eq("user_id", userId)
    .maybeSingle();
  if (connErr || !conn?.vault_secret_id) {
    return json({ error: "Google not connected" }, 409);
  }
  const { data: refreshToken, error: secretErr } = await admin.rpc("read_google_secret", {
    secret_id: conn.vault_secret_id,
  });
  if (secretErr || !refreshToken) return json({ error: "Failed to read credential" }, 500);

  let accessToken: string;
  try {
    accessToken = await refreshAccessToken(refreshToken as string, clientId, clientSecret);
  } catch (e) {
    return json({ error: `Token refresh failed: ${String((e as Error)?.message ?? e).slice(0, 200)}` }, 502);
  }

  // ── Staleness guard: compare Drive's CURRENT modifiedTime to the baseline ──
  const metaRes = await fetch(
    `${DRIVE_BASE}/files/${encodeURIComponent(fileId)}?fields=modifiedTime,trashed&supportsAllDrives=true`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!metaRes.ok) {
    const text = (await metaRes.text()).slice(0, 200);
    return json({ error: `Drive files.get ${metaRes.status}: ${text}` }, 502);
  }
  const meta = await metaRes.json();
  if (meta.trashed) return json({ error: "Doc is in the Drive trash" }, 409);
  const driveModifiedTime = meta.modifiedTime as string;

  // A baseline that doesn't match Drive means someone edited the Doc since the client
  // last synced — refuse to overwrite, tell the client to refresh then retry. Skipped
  // when `overwrite` is set (the user explicitly chose to clobber Google's version) or
  // when we have NO baseline at all (first write of a never-pulled Doc, nothing to lose).
  if (!overwrite && baseline && !sameInstant(baseline, driveModifiedTime)) {
    return json({ ok: false, error: "stale", driveModifiedTime, expectedModifiedTime: baseline }, 409);
  }

  // ── Tab awareness: read the live tab tree ONCE (Docs API, `documents` scope) ──
  // The raw JSON feeds BOTH the writability check (readTabs) and the clearing-delete
  // bound (tabEndIndex), so this is the only Docs fetch either path needs.
  const docRes = await fetch(
    `${DOCS_BASE}/documents/${encodeURIComponent(fileId)}?includeTabsContent=true`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!docRes.ok) {
    const text = (await docRes.text()).slice(0, 200);
    return json({ error: `documents.get ${docRes.status}: ${text}` }, 502);
  }
  const docJson = await docRes.json();
  const tabs = readTabs(docJson);

  if (tabId !== null) {
    // ── Per-tab write: batchUpdate scoped by tabId. Blast radius = this tab. ──
    const tab = tabs.find((t) => t.tabId === tabId);
    if (!tab) return json({ error: "Tab not found in Doc" }, 404);
    // Re-verify writability against the LIVE structure (defense in depth — the tab
    // may have gained unsupported content in Google since the last pull; tables/
    // frozen-image islands do NOT lock — the splice below writes around them).
    // Never trust a client-cached flag; the server re-decides from the actual Doc.
    if (!tab.writable) {
      return json({ ok: false, error: "tab_readonly", reason: tab.readonlyReason }, 409);
    }
    // Raw tab node (element indices) for the island splice — from the SAME raw
    // JSON already fetched above (no second Docs round-trip).
    const tabNode = findDocumentTab(docJson, tabId);
    if (tabNode === null) return json({ error: "Tab not found in Doc" }, 404);

    // ── Image re-insert: mint a short-lived signed URL per re-hosted image so
    // insertInlineImage can fetch it (Docs COPIES the bytes at insert, so 10 min
    // is ample). Keyed by the object ids the pull harvested — the same ids the
    // markdown's `![image:id]` placeholders carry. After the write the Doc assigns
    // NEW object ids to the re-inserted images; we deliberately do NOT reconcile
    // them here. The next pull re-harvests ids/URIs, re-upserts doc_note_images,
    // AND regenerates body_md from the Doc — refreshing placeholders and rows
    // TOGETHER. Until then the editor's old body_md still maps old ids → the
    // still-present doc_note_images rows, so we must never delete those rows on
    // write (the pull prunes stale ones once it re-baselines).
    const { data: imageRows } = await admin.from("doc_note_images")
      .select("object_id, storage_path, width_pt, height_pt")
      .eq("user_id", userId).eq("note_id", noteId).eq("tab_id", tabId);
    const images: Record<string, { uri: string; widthPt?: number | null; heightPt?: number | null }> = {};
    for (const row of imageRows ?? []) {
      const { data: signed } = await admin.storage.from("doc-images")
        .createSignedUrl(row.storage_path as string, 600);
      if (signed?.signedUrl) {
        images[row.object_id as string] = {
          uri: signed.signedUrl,
          widthPt: row.width_pt as number | null,
          heightPt: row.height_pt as number | null,
        };
      }
    }

    let requests: unknown[];
    try {
      requests = renderTabRequests(tabId, tabNode, markdown, images);
    } catch (e) {
      if (e instanceof UnmappedImageError) {
        return json({ ok: false, error: "tab_readonly", reason: "unmapped image" }, 409);
      }
      if (e instanceof IslandMismatchError) {
        // The Doc's table/image layout moved since this markdown was pulled (or
        // user text fabricated a marker) — splice ranges would land wrong.
        // Refuse; the next pull re-aligns the tab.
        return json({ ok: false, error: "tab_readonly", reason: "table/image layout changed — sync again" }, 409);
      }
      throw e;
    }
    // An islands-only tab (nothing editable changed-able) can render to zero
    // requests — batchUpdate rejects an empty list, and there is nothing to write.
    if (requests.length > 0) {
      const buRes = await fetch(
        `${DOCS_BASE}/documents/${encodeURIComponent(fileId)}:batchUpdate`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          body: JSON.stringify({ requests }),
        },
      );
      if (!buRes.ok) {
        const text = (await buRes.text()).slice(0, 200);
        return json({ error: `documents.batchUpdate ${buRes.status}: ${text}` }, 502);
      }
    }
    // Fresh modifiedTime for the new baseline (batchUpdate bumped it).
    const mRes = await fetch(
      `${DRIVE_BASE}/files/${encodeURIComponent(fileId)}?fields=modifiedTime&supportsAllDrives=true`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );
    const newModifiedTime = mRes.ok ? (await mRes.json()).modifiedTime as string : null;

    // Persist: tab body + reference baseline (storm guard vs the pull cron).
    // Tabs are keyed by NOTE (0023) — a save may arrive via any sibling reference,
    // so filter by note_id, and re-baseline EVERY sibling ref of this Doc (matching
    // the pull's sibling re-baseline) so no project's ref goes spuriously stale.
    const nowISO = new Date().toISOString();
    await admin.from("doc_note_tabs")
      .update({ body_md: markdown, updated_at: nowISO })
      .eq("note_id", noteId).eq("tab_id", tabId).eq("user_id", userId);
    const { error: bErr } = await admin.from("project_references")
      .update({ modified_time: newModifiedTime, last_synced_at: nowISO, sync_state: "synced" })
      .eq("drive_file_id", fileId).eq("user_id", userId);
    if (bErr) return json({ ok: true, modifiedTime: newModifiedTime, warning: "baseline not stored" });
    return json({ ok: true, modifiedTime: newModifiedTime });
  }

  // ── Multi-tab guard on the legacy path ──
  // The whole-file Markdown rewrite below is SAFE only on single-tab Docs. On a
  // multi-tab Doc the Markdown reconversion destroys the tab tree (undefined
  // behavior, observed corrupting tab nesting) — refuse; the client must use the
  // per-tab path. This guard protects all clients and is NOT feature-flagged.
  if (tabs.length > 1) {
    return json({ ok: false, error: "multitab_unsupported", tabCount: tabs.length }, 409);
  }

  // ── Write-back: upload Markdown, converting back to a Google Doc ──
  // Multipart update: metadata part pins the target mimeType to a Google Doc (forces
  // Drive's Markdown→Doc conversion), media part carries the Markdown bytes. Per the
  // fidelity contract this REWRITES the Doc from Markdown — anything richer than
  // RichDoc's vocabulary (comments, suggestions, exotic formatting) doesn't survive;
  // Docs revision history is the safety net.
  const boundary = `atlas-${crypto.randomUUID()}`;
  const body =
    `--${boundary}\r\n` +
    `Content-Type: application/json; charset=UTF-8\r\n\r\n` +
    `${JSON.stringify({ mimeType: GOOGLE_DOC_MIME })}\r\n` +
    `--${boundary}\r\n` +
    `Content-Type: text/markdown\r\n\r\n` +
    `${markdown}\r\n` +
    `--${boundary}--`;

  const upRes = await fetch(
    `${DRIVE_UPLOAD}/files/${encodeURIComponent(fileId)}?uploadType=multipart&fields=modifiedTime&supportsAllDrives=true`,
    {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": `multipart/related; boundary=${boundary}`,
      },
      body,
    },
  );
  if (!upRes.ok) {
    const text = (await upRes.text()).slice(0, 200);
    return json({ error: `Drive files.update ${upRes.status}: ${text}` }, 502);
  }
  const updated = await upRes.json();
  const newModifiedTime = (updated.modifiedTime as string | undefined) ?? null;

  // Re-baseline the reference so the pull cron sees Drive == stored and does NOT
  // re-pull our own write (storm guard). last_synced_at/now, state back to synced.
  const nowISO = new Date().toISOString();
  const { error: updErr } = await admin
    .from("project_references")
    .update({ modified_time: newModifiedTime, last_synced_at: nowISO, sync_state: "synced" })
    .eq("id", refRow.id)
    .eq("user_id", userId);
  if (updErr) {
    // Drive succeeded; only the baseline write failed. Report success with a warning
    // so the client doesn't retry the overwrite — the next pull will re-baseline.
    return json({ ok: true, modifiedTime: newModifiedTime, warning: "baseline not stored" });
  }

  return json({ ok: true, modifiedTime: newModifiedTime });
});
