/**
 * Atlas — drive-import Edge Function (Deno)  ·  Google Picker + reference registrar
 *
 * Two roles behind one URL (design doc §Server-flow 2):
 *
 *   GET  /functions/v1/drive-import
 *        → serves the server-hosted Google Picker page (pattern proven in
 *          docs/experiments/picker-folder-cascade-test.html, flipped to `drive.file`).
 *          The Mac launches it in the system browser like the connect flows. The
 *          user's Supabase JWT + target projectId ride the URL **fragment**
 *          (#token=…&project=…) so they never reach the server on the GET and never
 *          land in an access log; the page reads them from `location.hash`. The page
 *          runs GIS to mint a `drive.file` token, opens the Picker, enriches each
 *          picked file with Drive metadata, then POSTs the list back here.
 *
 *   POST /functions/v1/drive-import
 *        { "projectId": "<uuid>",
 *          "files": [{ "id", "name", "mimeType", "modifiedTime" }, …] }
 *        → verifies the Supabase JWT, confirms the project belongs to the caller,
 *          and registers one project_references row per file (deduped by
 *          drive_file_id). A Google Doc also gets a backing `notes` row (empty body —
 *          the pull cron fills it on the next tick); everything else is a view-only
 *          `file` reference.  →  200 { ok, imported, skipped }
 *
 * drive.file grant note: the Picker grants file access to the Google **Cloud project**
 * (app), keyed by the appId/project-number + the OAuth client. For the pull cron to
 * later read these files with the DESKTOP client's refresh token, the Picker's WEB
 * OAuth client MUST live in the SAME Google Cloud project as the Desktop client —
 * verify end-to-end with a real Drive (reserved manual step).
 *
 * Auth: POST verifies the caller's Supabase JWT (auth.getUser). The GET is
 * unauthenticated (a browser opens it with no header) and serves only a public shell
 * (public web client id + API key), so this function MUST be deployed with
 * `--no-verify-jwt` — the POST does its own real verification.
 *
 * Env (SUPABASE_* auto-injected; DRIVE_PICKER_* set via `supabase secrets set`):
 *   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
 *   DRIVE_PICKER_CLIENT_ID   — WEB OAuth client id (same GCP project as the Desktop client)
 *   DRIVE_PICKER_API_KEY     — Browser API key (restricted to the Picker + Drive API)
 *   DRIVE_PICKER_APP_ID      — GCP project number (Picker setAppId)
 *
 * Deploy: supabase functions deploy drive-import --no-verify-jwt --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GOOGLE_DOC_MIME = "application/vnd.google-apps.document";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ── The hosted picker page. Public creds are injected from env; the JWT + projectId
//    arrive in the URL fragment (client-only, never sent to the server on GET). ──
function pickerPage(clientId: string, apiKey: string, appId: string): string {
  const scope = "https://www.googleapis.com/auth/drive.file";
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Atlas — Import from Drive</title>
  <script src="https://apis.google.com/js/api.js"></script>
  <script src="https://accounts.google.com/gsi/client"></script>
  <style>
    body { font-family: -apple-system, system-ui; max-width: 560px; margin: 48px auto; padding: 0 20px; color: #2b2622; background: #f4efe6; }
    h2 { font-weight: 600; }
    button { font-size: 15px; padding: 9px 16px; border: 1.5px solid #2b2622; background: transparent; border-radius: 8px; cursor: pointer; }
    button:disabled { opacity: 0.4; cursor: default; }
    .muted { color: #6b6258; font-size: 13px; margin: 10px 0; }
    pre { white-space: pre-wrap; color: #6b6258; font-size: 13px; }
    .accent { color: #b04f2f; }
  </style>
</head>
<body>
  <h2>Import from Google Drive</h2>
  <p class="muted">Pick the Docs and files to import into this Atlas project. Google Docs
     become editable, re-syncing notes; everything else becomes a view-only reference.</p>
  <button id="pick" disabled>Choose files…</button>
  <pre id="out"></pre>

<script>
const CLIENT_ID = ${JSON.stringify(clientId)};
const API_KEY   = ${JSON.stringify(apiKey)};
const APP_ID    = ${JSON.stringify(appId)};
const SCOPE     = ${JSON.stringify(scope)};

// JWT + projectId ride the fragment so the server never sees them on the GET.
const params  = new URLSearchParams((location.hash || "").replace(/^#/, ""));
const jwt     = params.get("token");
const project = params.get("project");

const out = document.getElementById("out");
const log = (x) => { out.textContent += x + "\\n"; };
let accessToken = null, tokenClient = null, pickerReady = false;

if (!jwt || !project) {
  log("Missing session — reopen this from Atlas.");
} else {
  gapi.load("client:picker", async () => {
    await gapi.client.init({
      apiKey: API_KEY,
      discoveryDocs: ["https://www.googleapis.com/discovery/v1/apis/drive/v3/rest"],
    });
    pickerReady = true;
  });
  tokenClient = google.accounts.oauth2.initTokenClient({
    client_id: CLIENT_ID,
    scope: SCOPE,
    callback: (resp) => {
      if (resp.error) { log("Authorization failed: " + resp.error); return; }
      accessToken = resp.access_token;
      gapi.client.setToken({ access_token: accessToken });
      openPicker();
    },
  });
  document.getElementById("pick").disabled = false;
  document.getElementById("pick").onclick = () => {
    if (!pickerReady) { log("Still loading — try again in a moment."); return; }
    // Fresh token each click (drive.file consent for the picked files).
    accessToken ? openPicker() : tokenClient.requestAccessToken();
  };
}

function openPicker() {
  const view = new google.picker.DocsView(google.picker.ViewId.DOCS)
    .setIncludeFolders(true)
    .setSelectFolderEnabled(false);
  const picker = new google.picker.PickerBuilder()
    .setAppId(APP_ID)
    .setOAuthToken(accessToken)
    .setDeveloperKey(API_KEY)
    .enableFeature(google.picker.Feature.MULTISELECT_ENABLED)
    .addView(view)
    .setCallback(onPicked)
    .build();
  picker.setVisible(true);
}

async function onPicked(data) {
  if (data.action !== google.picker.Action.PICKED) return;
  log("Importing " + data.docs.length + " file(s)…");
  // Enrich each pick with authoritative Drive metadata (name, mimeType, modifiedTime).
  const files = [];
  for (const d of data.docs) {
    try {
      const resp = await gapi.client.drive.files.get({
        fileId: d.id,
        fields: "id,name,mimeType,modifiedTime",
        supportsAllDrives: true,
      });
      files.push(resp.result);
    } catch (e) {
      // Fall back to the picker's own fields if the metadata read fails.
      files.push({ id: d.id, name: d.name, mimeType: d.mimeType, modifiedTime: null });
    }
  }
  try {
    const resp = await fetch(location.origin + location.pathname, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": "Bearer " + jwt },
      body: JSON.stringify({ projectId: project, files }),
    });
    const body = await resp.json();
    if (!resp.ok || !body.ok) { log("Import failed: " + (body.error || resp.status)); return; }
    log("Imported " + body.imported + ", skipped " + body.skipped + " (already in project).");
    log("Done — you can close this tab and return to Atlas.");
  } catch (e) {
    log("Import request failed: " + e);
  }
}
</script>
</body>
</html>`;
}

// ── POST: register the picked files as project references. ──
interface PickedFile {
  id: string;
  name: string;
  mimeType: string;
  modifiedTime: string | null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) return json({ error: "Server not configured" }, 500);

  // ── GET: serve the picker page (public shell; no auth, no secrets) ──
  if (req.method === "GET") {
    const clientId = Deno.env.get("DRIVE_PICKER_CLIENT_ID") ?? "";
    const apiKey = Deno.env.get("DRIVE_PICKER_API_KEY") ?? "";
    const appId = Deno.env.get("DRIVE_PICKER_APP_ID") ?? "";
    return new Response(pickerPage(clientId, apiKey, appId), {
      status: 200,
      headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
    });
  }

  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // ── Real JWT verification ──
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) return json({ error: "Missing or invalid Authorization header" }, 401);
  const authClient = createClient(supabaseUrl, anonKey);
  const { data: userData, error: userErr } = await authClient.auth.getUser(token);
  if (userErr || !userData?.user) return json({ error: "Invalid or expired token" }, 401);
  const userId = userData.user.id;

  // ── Input ──
  let projectId: string;
  let files: PickedFile[];
  try {
    const b = await req.json();
    if (typeof b?.projectId !== "string" || !b.projectId.trim()) {
      return json({ error: "Body must contain a `projectId` string" }, 400);
    }
    if (!Array.isArray(b?.files)) return json({ error: "Body must contain a `files` array" }, 400);
    projectId = b.projectId.trim();
    files = (b.files as unknown[])
      .map((f) => f as Record<string, unknown>)
      .filter((f) => typeof f?.id === "string" && typeof f?.mimeType === "string")
      .map((f) => ({
        id: (f.id as string),
        name: typeof f.name === "string" && f.name.trim() ? (f.name as string) : "Untitled",
        mimeType: (f.mimeType as string),
        modifiedTime: typeof f.modifiedTime === "string" ? (f.modifiedTime as string) : null,
      }));
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (files.length === 0) return json({ ok: true, imported: 0, skipped: 0 });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Confirm the project belongs to the caller and fetch its space (notes.space_name).
  const { data: project, error: projErr } = await admin
    .from("projects")
    .select("space_name")
    .eq("id", projectId)
    .eq("user_id", userId)
    .maybeSingle();
  if (projErr) return json({ error: "Failed to load project" }, 500);
  if (!project) return json({ error: "Project not found" }, 404);
  const spaceName = project.space_name as string;

  // Dedupe against the project's existing pool (same lesson as 0009/C1 — dedupe in
  // code, never rely on ON CONFLICT). A re-imported file is skipped, not duplicated.
  const driveIds = files.map((f) => f.id);
  const { data: existing, error: existErr } = await admin
    .from("project_references")
    .select("drive_file_id")
    .eq("user_id", userId)
    .eq("project_id", projectId)
    .in("drive_file_id", driveIds);
  if (existErr) return json({ error: "Failed to check existing references" }, 500);
  const already = new Set((existing ?? []).map((r) => r.drive_file_id as string));

  const noteRows: Record<string, unknown>[] = [];
  const refRows: Record<string, unknown>[] = [];
  let skipped = 0;
  const nowISO = new Date().toISOString();

  for (const f of files) {
    if (already.has(f.id)) { skipped++; continue; }
    already.add(f.id); // guard against the same id appearing twice in one payload

    if (f.mimeType === GOOGLE_DOC_MIME) {
      // Editable Doc-note: create the backing note (empty — the cron pulls content),
      // then a doc_note reference with a null baseline so the first tick pulls it.
      const noteId = crypto.randomUUID();
      noteRows.push({
        id: noteId,
        user_id: userId,
        space_name: spaceName,
        project_id: projectId,
        title: f.name,
        body: "",
        updated_at: nowISO,
        is_external: true,
        google_doc_id: f.id,
      });
      refRows.push({
        id: crypto.randomUUID(),
        user_id: userId,
        project_id: projectId,
        kind: "doc_note",
        title: f.name,
        drive_file_id: f.id,
        mime_type: f.mimeType,
        modified_time: null, // null ⇒ first pull fetches content
        sync_state: "pending",
        note_id: noteId,
      });
    } else {
      // View-only file reference: metadata captured now; cron refreshes it.
      refRows.push({
        id: crypto.randomUUID(),
        user_id: userId,
        project_id: projectId,
        kind: "file",
        title: f.name,
        drive_file_id: f.id,
        mime_type: f.mimeType,
        modified_time: f.modifiedTime,
        sync_state: "pending",
      });
    }
  }

  // Notes first (references' note_id FK points at them). ON DELETE SET NULL means a
  // note-insert failure wouldn't orphan-crash the ref insert, but insert order keeps
  // the link intact.
  if (noteRows.length > 0) {
    const { error } = await admin.from("notes").insert(noteRows);
    if (error) return json({ error: `Failed to create notes: ${error.message}` }, 500);
  }
  if (refRows.length > 0) {
    const { error } = await admin.from("project_references").insert(refRows);
    if (error) return json({ error: `Failed to register references: ${error.message}` }, 500);
  }

  return json({ ok: true, imported: refRows.length, skipped });
});
