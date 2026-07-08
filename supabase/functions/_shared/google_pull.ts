/**
 * Atlas — shared Google pull machinery (Deno), reused by google-sync (cron),
 * drive-import (inline first pull) and reference-pull ("Sync now").
 *
 * Two entry points:
 *   • mintAccessToken(admin, userId, …) — google_connections vault_secret_id
 *     lookup → read_google_secret RPC → refresh-token exchange. Throws
 *     InvalidGrantError on a revoked/expired refresh token so the caller can
 *     mark the connection 'revoked'; any other failure is a plain Error.
 *   • pullDocNoteReference(admin, userId, accessToken, ref, runISO, dryRun) —
 *     the COMPLETE doc_note pull for one reference: Drive meta check (fetched
 *     here), storm guard, single-tab (Drive-Markdown → notes.body) vs multi-tab
 *     (doc_note_tabs upsert + prune + preview) fork, and the re-baseline.
 *
 * v2 changes vs the google-sync original this was extracted from:
 *   (a) doc_note_tabs are keyed by NOTE — upsert onConflict (note_id, tab_id),
 *       prune by note_id, and skipped entirely for a note-less ref (a doc_note
 *       without a note can't hold tabs). reference_id is still written (column
 *       kept, now nullable) for provenance.
 *   (b) the changed-branch re-baseline updates EVERY sibling reference to the
 *       same Doc (user_id + drive_file_id, not id) so duplicate references stay
 *       in lockstep.
 *
 * Meta handling shape (chosen): pullDocNoteReference FETCHES its own Drive meta
 * (driveFileMeta) and signals gone/trashed by THROWING — the same outcome the
 * google-sync loop's catch already produces (mark 'error', record, continue).
 * This makes the function self-contained for the single-reference callers
 * (drive-import, reference-pull), which have no surrounding meta-fetch loop.
 */

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { readTabs, tabsPreviewMarkdown } from "./doc_tabs.ts";

const GOOGLE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const DRIVE_BASE = "https://www.googleapis.com/drive/v3";
const DOCS_BASE = "https://docs.googleapis.com/v1";

// ── Google token refresh ────────────────────────────────────────
export class InvalidGrantError extends Error {}

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
  if (!res.ok) {
    // Google returns 400 { "error": "invalid_grant" } for a revoked/expired token.
    if (text.includes("invalid_grant")) throw new InvalidGrantError("invalid_grant");
    throw new Error(`token refresh ${res.status}: ${text.slice(0, 200)}`);
  }
  const parsed = JSON.parse(text);
  if (!parsed.access_token) throw new Error("token refresh: no access_token");
  return parsed.access_token as string;
}

/**
 * Mint a Google access token for `userId`: look up the connection's
 * vault_secret_id, decrypt the refresh token via the service-role Vault read
 * (read_google_secret), and exchange it. Throws InvalidGrantError on a revoked
 * token, a plain Error otherwise.
 */
export async function mintAccessToken(
  admin: SupabaseClient,
  userId: string,
  clientId: string,
  clientSecret: string,
): Promise<string> {
  const { data: conn, error: connErr } = await admin
    .from("google_connections")
    .select("vault_secret_id")
    .eq("user_id", userId)
    .maybeSingle();
  if (connErr) throw new Error(`connection lookup failed: ${connErr.message}`);
  if (!conn?.vault_secret_id) throw new Error("connection has no vault_secret_id");
  const { data: refreshToken, error: secretErr } = await admin.rpc("read_google_secret", { secret_id: conn.vault_secret_id });
  if (secretErr || !refreshToken) throw new Error("vault read failed");
  return await refreshAccessToken(refreshToken as string, clientId, clientSecret);
}

// ── Drive / Docs reads ──────────────────────────────────────────
interface DriveMeta {
  name?: string;
  mimeType?: string;
  modifiedTime?: string;   // RFC3339
  trashed?: boolean;
}

/** Drive files.get for the staleness baseline + type. ok:false carries the status so
 *  the caller can mark the one reference 'error' without failing the whole run. */
export async function driveFileMeta(
  accessToken: string,
  fileId: string,
): Promise<{ ok: true; meta: DriveMeta } | { ok: false; status: number; message: string }> {
  const res = await fetch(
    `${DRIVE_BASE}/files/${encodeURIComponent(fileId)}?fields=name,mimeType,modifiedTime,trashed&supportsAllDrives=true`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return { ok: false, status: res.status, message: (await res.text()).slice(0, 200) };
  return { ok: true, meta: (await res.json()) as DriveMeta };
}

/** Export a Google Doc as Markdown (the wire form stored in notes.body; the Mac
 *  renders it via RichDoc ⇄ Markdown — the server only moves the bytes). */
async function driveExportMarkdown(accessToken: string, fileId: string): Promise<string> {
  const res = await fetch(
    `${DRIVE_BASE}/files/${encodeURIComponent(fileId)}/export?mimeType=${encodeURIComponent("text/markdown")}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) throw new Error(`files.export ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return await res.text();
}

// Docs API read with the full tab tree. Requires the `documents` scope
// (granted at connect alongside drive.file — GoogleAuthService.scopes).
async function docsGetWithTabs(accessToken: string, fileId: string): Promise<unknown> {
  const res = await fetch(
    `${DOCS_BASE}/documents/${encodeURIComponent(fileId)}?includeTabsContent=true`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) throw new Error(`documents.get ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return await res.json();
}

// ── Image re-host helpers ────────────────────────────────────────
/** Map a Content-Type to the storage extension Docs' insertInlineImage accepts
 *  (PNG/JPEG/GIF only). Anything else ⇒ null (caller locks the tab). */
function extForContentType(contentType: string): "png" | "jpg" | "gif" | null {
  const ct = contentType.split(";")[0].trim().toLowerCase();
  if (ct === "image/png") return "png";
  if (ct === "image/jpeg") return "jpg";
  if (ct === "image/gif") return "gif";
  return null;
}

/** Download a Docs image from its short-lived, possession-based contentUri. It is
 *  fetched with NO auth header first (the URI itself is the credential); on
 *  401/403 we retry once WITH the Bearer token. Throws on any other failure. */
async function fetchDocImage(
  contentUri: string | null,
  accessToken: string,
): Promise<{ bytes: Uint8Array; contentType: string }> {
  if (!contentUri) throw new Error("image has no contentUri");
  let res = await fetch(contentUri);
  if (res.status === 401 || res.status === 403) {
    await res.body?.cancel();
    res = await fetch(contentUri, { headers: { Authorization: `Bearer ${accessToken}` } });
  }
  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`image fetch ${res.status}`);
  }
  const contentType = res.headers.get("content-type") ?? "";
  const bytes = new Uint8Array(await res.arrayBuffer());
  return { bytes, contentType };
}

// ── doc_note pull ───────────────────────────────────────────────
// A minimal projection of a project_references row for the doc_note pull.
export interface DocNoteRef {
  id: string;
  drive_file_id: string;
  note_id: string | null;
  mime_type: string | null;
  modified_time: string | null;
}

/**
 * Storm guard (pure): pull content only when never-baselined OR Drive is
 * strictly newer than the stored baseline. The notes analogue of the calendar
 * C2 storm guard — after a write-back re-baselines to Drive's new time, the next
 * pull sees equal and re-pulls nothing. `storedMs` is -Infinity when unbaselined
 * (⇒ always pull); `driveMs` is NaN when the Doc has no modifiedTime.
 */
export function isChanged(driveMs: number, storedMs: number): boolean {
  return !Number.isFinite(storedMs) || (Number.isFinite(driveMs) && driveMs > storedMs);
}

/**
 * Pull ONE doc_note reference (design doc §Server-flow 3). Fetches Drive meta
 * itself; throws on gone/trashed (caller isolates). Returns { changed } — true
 * when a pull ran (caller counts it as synced), false on a no-op recency check.
 *
 * TITLE is intentionally never overwritten — set at import, left alone so a
 * local rename isn't clobbered every tick.
 */
export async function pullDocNoteReference(
  admin: SupabaseClient,
  userId: string,
  accessToken: string,
  ref: DocNoteRef,
  runISO: string,
  dryRun: boolean,
): Promise<{ changed: boolean }> {
  const metaRes = await driveFileMeta(accessToken, ref.drive_file_id);
  if (!metaRes.ok) throw new Error(`drive ${metaRes.status}: ${metaRes.message}`);
  const meta = metaRes.meta;
  if (meta.trashed) throw new Error("drive file trashed");

  const driveMs = meta.modifiedTime ? new Date(meta.modifiedTime).getTime() : NaN;
  const storedMs = ref.modified_time ? new Date(ref.modified_time).getTime() : -Infinity;
  if (!isChanged(driveMs, storedMs)) {
    // Unchanged since last pull — record a successful check (this ref only).
    if (!dryRun) {
      await admin.from("project_references")
        .update({ last_synced_at: runISO, sync_state: "synced" })
        .eq("id", ref.id).eq("user_id", userId);
    }
    return { changed: false };
  }

  const docJson = await docsGetWithTabs(accessToken, ref.drive_file_id);
  const tabs = readTabs(docJson);
  if (tabs.length <= 1) {
    // Single-tab Doc: legacy Drive-Markdown pull, unchanged. The export is a read,
    // so it runs even in dryRun (matches the original behavior).
    const markdown = await driveExportMarkdown(accessToken, ref.drive_file_id);
    if (!dryRun && ref.note_id) {
      const { error: nErr } = await admin.from("notes")
        .update({ body: markdown, updated_at: runISO })
        .eq("id", ref.note_id).eq("user_id", userId);
      if (nErr) throw new Error(`note update failed: ${nErr.message}`);
      // Doc went from multi-tab to single-tab: clear any stale (note-keyed) tab rows.
      const { error: dErr } = await admin.from("doc_note_tabs")
        .delete().eq("note_id", ref.note_id).eq("user_id", userId);
      if (dErr) throw new Error(`tab cleanup failed: ${dErr.message}`);
    }
  } else {
    // Multi-tab Doc: per-tab storage + concatenated preview in notes.body. Tabs are
    // keyed by NOTE (v2) — skip entirely for a note-less doc_note ref.
    if (!dryRun && ref.note_id) {
      const noteId = ref.note_id;
      // ── Re-host inline images to Storage while contentUri is still fresh ──
      // Only WRITABLE tabs are ever rewritten, so only their images need re-hosting
      // (read-only tabs are display-only). A per-image failure or an unsupported
      // format downgrades just THAT tab to read-only for this pull (its flags are
      // written by the upsert below); other tabs continue. `harvestedIds` is every
      // image that still exists in the Doc — the prune set.
      const harvestedIds = new Set<string>();
      for (const t of tabs) for (const img of t.images) harvestedIds.add(img.objectId);
      let allImagesOk = true;
      // Re-host EVERY tab's images — read-only tabs need them for display too.
      // Only writable tabs get the strict treatment (a failed/unsupported image
      // downgrades the tab so we never rewrite a tab whose image we can't
      // re-insert); on read-only tabs a failure just skips that image's display.
      for (const t of tabs) {
        for (const img of t.images) {
          try {
            const { bytes, contentType } = await fetchDocImage(img.contentUri, accessToken);
            const ext = extForContentType(contentType);
            if (!ext) {
              if (t.writable) {
                t.writable = false;
                t.readonlyReason = "unsupported image format";
                allImagesOk = false;
                break;
              }
              continue;
            }
            const path = `${userId}/${noteId}/${img.objectId}.${ext}`;
            const { error: sErr } = await admin.storage.from("doc-images")
              .upload(path, bytes, { contentType, upsert: true });
            if (sErr) throw new Error(sErr.message);
            const { error: iErr } = await admin.from("doc_note_images").upsert({
              user_id: userId,
              note_id: noteId,
              tab_id: t.tabId,
              object_id: img.objectId,
              storage_path: path,
              width_pt: img.widthPt,
              height_pt: img.heightPt,
              crop_locked: img.cropLocked,
            }, { onConflict: "note_id,object_id" });
            if (iErr) throw new Error(iErr.message);
          } catch (_e) {
            if (t.writable) {
              t.writable = false;
              t.readonlyReason = "image fetch failed";
              allImagesOk = false;
              break;
            }
            // read-only tab: display-only image, skip on failure
          }
        }
      }
      const { error: uErr } = await admin.from("doc_note_tabs").upsert(
        tabs.map((t) => ({
          user_id: userId,
          note_id: ref.note_id,
          reference_id: ref.id, // column kept (now nullable) for provenance
          tab_id: t.tabId,
          parent_tab_id: t.parentTabId,
          title: t.title,
          ord: t.ord,
          body_md: t.markdown,
          writable: t.writable,
          readonly_reason: t.readonlyReason,
          updated_at: runISO,
        })),
        { onConflict: "note_id,tab_id" },
      );
      if (uErr) throw new Error(`tab upsert failed: ${uErr.message}`);
      // Tabs deleted in Google disappear from the tree — drop their rows (by note).
      const liveIds = tabs.map((t) => t.tabId);
      const { error: gErr } = await admin.from("doc_note_tabs")
        .delete().eq("note_id", ref.note_id).eq("user_id", userId)
        .not("tab_id", "in", `(${liveIds.map((id) => `"${id}"`).join(",")})`);
      if (gErr) throw new Error(`tab prune failed: ${gErr.message}`);
      // Drop image rows for objects no longer in the Doc — but ONLY on a fully
      // successful pull. A partial pull (an image fetch failed) must keep every old
      // mapping, because the editor's still-old body_md placeholders point at them
      // and a later write may re-insert from those Storage copies.
      if (allImagesOk) {
        let pruneQ = admin.from("doc_note_images")
          .delete().eq("note_id", noteId).eq("user_id", userId);
        if (harvestedIds.size) {
          pruneQ = pruneQ.not("object_id", "in", `(${[...harvestedIds].map((id) => `"${id}"`).join(",")})`);
        }
        const { error: ipErr } = await pruneQ;
        if (ipErr) throw new Error(`image prune failed: ${ipErr.message}`);
      }
      const { error: nErr } = await admin.from("notes")
        .update({ body: tabsPreviewMarkdown(tabs), updated_at: runISO })
        .eq("id", ref.note_id).eq("user_id", userId);
      if (nErr) throw new Error(`note update failed: ${nErr.message}`);
    }
  }
  if (!dryRun) {
    // Re-baseline EVERY sibling reference to this Doc (v2) so duplicates stay in
    // lockstep — keyed by (user_id, drive_file_id), not the single ref id.
    const { error: rErr } = await admin.from("project_references")
      .update({
        modified_time: meta.modifiedTime ?? null,
        mime_type: meta.mimeType ?? ref.mime_type,
        last_synced_at: runISO,
        sync_state: "synced",
      })
      .eq("user_id", userId).eq("drive_file_id", ref.drive_file_id);
    if (rErr) throw new Error(`reference update failed: ${rErr.message}`);
  }
  return { changed: true };
}
