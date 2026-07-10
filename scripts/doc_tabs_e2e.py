#!/usr/bin/env python3
"""Atlas — live end-to-end proof of per-tab Google Docs sync (v1 + v2).

Exercises the DEPLOYED edge functions against a throwaway Drive copy of Drew's
real 6-tab test Doc. The single copy is the fixture for BOTH tiers: the import
creates the note (v2 proof), and that same note backs every v1 write/guard proof.

v1 proofs (unchanged assertions):
  1. PULL TREE     documents.get?includeTabsContent=true → 6 tabs, 4 top-level,
                   2 nested under the right parents.
  2. WRITE + ROUND-TRIP  a per-tab write through drive-writeback, then a re-read,
                   is byte-identical to what was sent (reader∘renderer == identity).
  3. GUARDS        legacy whole-file write on a multi-tab Doc ⇒ 409
                   multitab_unsupported; per-tab write on a read-only (table) tab
                   ⇒ 409 tab_readonly. Server re-decides from the LIVE Doc.
  4. ISOLATION     a per-tab write touches ONLY that tab.

v2 proofs (this file's additions):
  5. IMPORT-PULL         drive-import (user JWT) with a fresh Doc + real project →
                         pulled==1, and doc_note_tabs land populated with NO cron tick.
  6. DUP-IMPORT          re-import the SAME Doc into a different project → imported==1,
                         pulled==0, the new ref reuses the first note, no new notes row.
  7. IMAGE-GUARD         the image-bearing read-only tab ⇒ 409 tab_readonly.
  8. STORAGE-DISPLAY     doc_note_images has a re-hosted row; the authenticated
                         Storage object downloads (user JWT) as image/*.
  9. IMAGE-PRESERVATION  add a solo-image+text scenario to a writable tab, pull it
                         (tab stays writable, `![image:…]` placeholder + image row),
                         write it back with an extra line → the image survives
                         (exactly one inlineObjectElement) and the new text lands.
 10. PENDING-409         a `pending` doc_note write (no overwrite) ⇒ 409 not_synced.
 11. SYNC-NOW            reference-pull (user JWT) on the import's ref → ok:true.

Secrets are read at RUNTIME, never embedded and never printed:
  * Supabase service_role + anon keys via `supabase projects api-keys` (JWT role).
  * Google OAuth client id/secret from Config/Secrets.xcconfig.
  * The user's Google refresh token via read_google_secret RPC (service key),
    minted into an access token exactly as the edge functions do.
  * A real Supabase USER JWT via the GoTrue admin magic-link → verify flow.

Everything created is torn down in the finally block (references, notes — which
cascade doc_note_tabs/doc_note_images rows — Storage objects, the scratch project
if one was made, and the Drive copy is trashed). Run: python3 scripts/doc_tabs_e2e.py
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import uuid
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

# ── Constants ────────────────────────────────────────────────────────────────
REF = "jxrmozhgsebwtbdleyxp"
SUPA_URL = f"https://{REF}.supabase.co"
REST = f"{SUPA_URL}/rest/v1/"
FUNCTIONS = f"{SUPA_URL}/functions/v1/"
TEST_DOC_ID = "1mn4G22zFRY09eVXQtZFUoIg1twA8qzoSGoYwiVeAl4Y"
EXPECTED_SUB = "3da0c38a-1c80-489f-885c-dba2ecf532b6"
USER_EMAIL = "drewkhalil@gmail.com"
GOOGLE_DOC_MIME = "application/vnd.google-apps.document"
SIMPLE_TAB_TITLE = "Tap1"     # the plain-text tab (t.0-equivalent) we write to
IMAGE_TAB_TITLE = "notes"     # a writable, empty-ish tab we turn into an image tab
MARKER = "E2E marker line"
PRESERVE_LINE = "E2E preserved line"
# A stable, publicly-fetchable PNG for the write-path image test. Google COPIES
# the bytes at insertInlineImage time, so the source only needs to be reachable now.
PUBLIC_PNG = "https://www.google.com/images/branding/googlelogo/1x/googlelogo_color_272x92dp.png"

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SECRETS = os.path.join(REPO, "Config", "Secrets.xcconfig")
SHIM = os.path.join("scripts", "doc_tabs_read_shim.ts")  # relative to REPO


# ── Tiny HTTP helper (returns (status, text); never prints secrets) ──────────
def http(method, url, headers=None, data=None):
    req = urllib.request.Request(url, method=method, headers=headers or {})
    if data is not None:
        if isinstance(data, (dict, list)):
            data = json.dumps(data).encode()
            req.add_header("Content-Type", "application/json")
        elif isinstance(data, str):
            data = data.encode()
    try:
        with urllib.request.urlopen(req, data=data) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def as_json(text):
    """Parse JSON defensively — a proof records a FAIL row rather than crashing."""
    try:
        return json.loads(text)
    except Exception:
        return None


def jwt_payload(token):
    p = token.split(".")[1]
    p += "=" * (-len(p) % 4)
    return json.loads(base64.urlsafe_b64decode(p))


# ── Runtime secrets ──────────────────────────────────────────────────────────
def supabase_keys():
    """(service_role_key, anon_key) — legacy JWT keys picked by their `role`."""
    out = subprocess.run(
        ["supabase", "projects", "api-keys", "--project-ref", REF, "-o", "json"],
        capture_output=True, text=True, check=True,
    ).stdout
    service = anon = None
    for row in json.loads(out):
        key = row.get("api_key", "")
        try:
            role = jwt_payload(key).get("role")
        except Exception:
            continue  # non-JWT (new sb_* format) — skip
        if role == "service_role":
            service = key
        elif role == "anon":
            anon = key
    if not service or not anon:
        raise SystemExit("Could not resolve both service_role and anon keys.")
    return service, anon


def google_client():
    cid = csec = None
    with open(SECRETS) as f:
        for line in f:
            line = line.strip()
            if line.startswith("GOOGLE_OAUTH_CLIENT_ID"):
                cid = line.split("=", 1)[1].strip()
            elif line.startswith("GOOGLE_OAUTH_CLIENT_SECRET"):
                csec = line.split("=", 1)[1].strip()
    if not cid or not csec:
        raise SystemExit("GOOGLE_OAUTH_CLIENT_ID/SECRET missing from Secrets.xcconfig.")
    return cid, csec


def google_access_token(service_key, cid, csec):
    sh = {"apikey": service_key, "Authorization": "Bearer " + service_key}
    s, b = http("GET", REST + "google_connections?select=user_id,vault_secret_id,status", sh)
    rows = json.loads(b)
    if not rows:
        raise SystemExit("No google_connections row — connect Google in Atlas first.")
    conn = rows[0]
    if conn.get("status") != "active":
        raise SystemExit(
            f"Google connection status is {conn.get('status')!r}, not 'active'.\n"
            "Reconnect Google in Atlas (Settings → integrations) so a fresh Vault\n"
            "refresh token is stored, then re-run this script."
        )
    s, b = http("POST", REST + "rpc/read_google_secret", sh, {"secret_id": conn["vault_secret_id"]})
    if s != 200:
        raise SystemExit(f"read_google_secret failed {s}")
    refresh = json.loads(b) if b.strip().startswith('"') else b.strip()
    body = urllib.parse.urlencode({
        "refresh_token": refresh, "client_id": cid, "client_secret": csec,
        "grant_type": "refresh_token",
    })
    s, b = http("POST", "https://oauth2.googleapis.com/token",
                {"Content-Type": "application/x-www-form-urlencoded"}, body)
    if s != 200:
        raise SystemExit(f"Google token exchange failed {s}")
    return json.loads(b)["access_token"]


def user_jwt(service_key, anon_key):
    """A real Supabase user JWT for USER_EMAIL via GoTrue admin magic-link + verify.

    The edge functions authenticate the app user with auth.getUser, so the service
    key alone won't do — we need a token whose `sub` is the app user.
    """
    s, b = http("POST", SUPA_URL + "/auth/v1/admin/generate_link",
                {"apikey": service_key, "Authorization": "Bearer " + service_key},
                {"type": "magiclink", "email": USER_EMAIL})
    if s != 200:
        raise SystemExit(f"generate_link failed {s}: {b[:200]}")
    hashed = json.loads(b).get("hashed_token")
    if not hashed:
        raise SystemExit("generate_link returned no hashed_token.")
    s, b = http("POST", SUPA_URL + "/auth/v1/verify",
                {"apikey": anon_key}, {"type": "magiclink", "token_hash": hashed})
    if s != 200:
        raise SystemExit(f"verify failed {s}: {b[:200]}")
    token = json.loads(b).get("access_token")
    if not token:
        raise SystemExit("verify returned no access_token.")
    sub = jwt_payload(token).get("sub")
    if sub != EXPECTED_SUB:
        raise SystemExit(f"User JWT sub {sub!r} != expected {EXPECTED_SUB!r}.")
    return token


# ── Google Docs / Drive ──────────────────────────────────────────────────────
def gapi(token, method, url, body=None):
    return http(method, url, {"Authorization": "Bearer " + token}, body)


def docs_get(token, file_id):
    s, b = gapi(token, "GET",
                f"https://docs.googleapis.com/v1/documents/{file_id}?includeTabsContent=true")
    if s != 200:
        raise SystemExit(f"documents.get {s}: {b[:200]}")
    return json.loads(b)


def docs_batch_update(token, file_id, requests):
    return gapi(token, "POST",
                f"https://docs.googleapis.com/v1/documents/{file_id}:batchUpdate",
                {"requests": requests})


def drive_modified_time(token, file_id):
    s, b = gapi(token, "GET",
                f"https://www.googleapis.com/drive/v3/files/{file_id}"
                "?fields=modifiedTime&supportsAllDrives=true")
    return json.loads(b).get("modifiedTime") if s == 200 else None


def read_tabs_via_shim(doc_json):
    """Derive each tab's markdown/writability/images with the SAME TS code the edge
    functions use (scripts/doc_tabs_read_shim.ts → readTabs), so nothing drifts."""
    fd, path = tempfile.mkstemp(suffix=".json", dir=SCRATCH)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(doc_json, f)
        out = subprocess.run(
            ["deno", "run", "--allow-read", SHIM, path],
            cwd=REPO, capture_output=True, text=True,
        )
        if out.returncode != 0:
            raise SystemExit(f"shim failed: {out.stderr[:300]}")
        return json.loads(out.stdout)
    finally:
        os.unlink(path)


def _strip_volatile(o):
    """Drop image `contentUri` values. A Docs image contentUri is a short-lived,
    possession-based SIGNED URL (see the v2 plan's image constraints) — Google
    re-mints it across fetches once the old one is consumed (the import-pull
    downloads it to re-host), so it is an ephemeral access token, NOT document
    content. Stripping it keeps the isolation compare strict on everything that IS
    content — text, table structure, image object ids, sizes, crop, positions —
    while ignoring the one field that legitimately changes without an edit."""
    if isinstance(o, dict):
        return {k: _strip_volatile(v) for k, v in o.items() if k != "contentUri"}
    if isinstance(o, list):
        return [_strip_volatile(x) for x in o]
    return o


def flatten_document_tabs(doc_json):
    """{tabId: documentTab-subtree-as-canonical-json} over the whole tab tree,
    with ephemeral image contentUris stripped (see _strip_volatile)."""
    acc = {}

    def walk(tabs):
        for t in tabs:
            tid = t.get("tabProperties", {}).get("tabId")
            acc[tid] = json.dumps(_strip_volatile(t.get("documentTab", {})),
                                  sort_keys=True, ensure_ascii=False)
            walk(t.get("childTabs", []))
    walk(doc_json.get("tabs", []))
    return acc


def find_document_tab(doc_json, tab_id):
    stack = list(doc_json.get("tabs", []))
    while stack:
        t = stack.pop()
        if t.get("tabProperties", {}).get("tabId") == tab_id:
            return t.get("documentTab", {})
        stack.extend(t.get("childTabs", []))
    return None


def tab_end_index(doc_json, tab_id):
    """Max endIndex of a tab's body content (the clearing-delete bound)."""
    dt = find_document_tab(doc_json, tab_id) or {}
    mx = 1
    for el in dt.get("body", {}).get("content", []):
        ei = el.get("endIndex")
        if isinstance(ei, (int, float)) and ei > mx:
            mx = int(ei)
    return mx


def tab_inline_and_text(doc_json, tab_id):
    """(# of inlineObjectElements, concatenated textRun content) for one tab."""
    dt = find_document_tab(doc_json, tab_id) or {}
    inline, text = 0, ""
    for el in dt.get("body", {}).get("content", []):
        for e in el.get("paragraph", {}).get("elements", []):
            if "inlineObjectElement" in e:
                inline += 1
            tr = e.get("textRun")
            if tr:
                text += tr.get("content", "")
    return inline, text


# ── PostgREST fixtures (service key) ─────────────────────────────────────────
def _svc_headers(service_key, extra=None):
    h = {"apikey": service_key, "Authorization": "Bearer " + service_key}
    if extra:
        h.update(extra)
    return h


def pg_get(service_key, path):
    s, b = http("GET", REST + path, _svc_headers(service_key))
    return as_json(b) if s == 200 else None


def pg_insert(service_key, table, row):
    h = _svc_headers(service_key, {"Prefer": "return=representation"})
    s, b = http("POST", REST + table, h, [row])
    if s not in (200, 201):
        raise SystemExit(f"insert into {table} failed {s}: {b[:200]}")
    return json.loads(b)[0]


def pg_patch(service_key, table, query, row):
    h = _svc_headers(service_key, {"Prefer": "return=minimal"})
    return http("PATCH", REST + f"{table}?{query}", h, row)


def pg_delete(service_key, table, query):
    http("DELETE", REST + f"{table}?{query}", _svc_headers(service_key))


# ── Storage REST (authenticated read as the user; delete as service role) ────
def storage_get_authenticated(bucket, path, ujwt, anon_key):
    """GET a private object as the OWNER (user JWT + anon apikey) — the exact call
    the Mac editor makes to display a re-hosted image. Returns (status, content_type)."""
    url = f"{SUPA_URL}/storage/v1/object/authenticated/{bucket}/{path}"
    req = urllib.request.Request(
        url, method="GET",
        headers={"apikey": anon_key, "Authorization": "Bearer " + ujwt},
    )
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.headers.get("Content-Type", "")
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Content-Type", "")


def storage_delete(service_key, bucket, paths):
    if not paths:
        return
    http("DELETE", f"{SUPA_URL}/storage/v1/object/{bucket}",
         _svc_headers(service_key), {"prefixes": paths})


# ── Edge-function callers (user JWT) ─────────────────────────────────────────
def call_function(name, ujwt, anon_key, body):
    s, b = http("POST", FUNCTIONS + name,
                {"Authorization": "Bearer " + ujwt, "apikey": anon_key}, body)
    return s, (as_json(b) or {"raw": b[:200]})


# ── First byte-divergence report (for a failed round-trip) ───────────────────
def hex_diff(a, b):
    n = min(len(a), len(b))
    i = 0
    while i < n and a[i] == b[i]:
        i += 1
    lo = max(0, i - 20)
    win_a = a[lo:i + 20].encode("utf-8")
    win_b = b[lo:i + 20].encode("utf-8")
    return (f"first divergence at char {i} (len sent={len(a)} read={len(b)})\n"
            f"  sent[{lo}:{i+20}] = {win_a.hex(' ')}\n"
            f"  read[{lo}:{i+20}] = {win_b.hex(' ')}\n"
            f"  sent…{a[lo:i+20]!r}\n"
            f"  read…{b[lo:i+20]!r}")


SCRATCH = tempfile.mkdtemp(prefix="atlas-e2e-")


def main():
    results = {}  # name -> (bool, detail)
    copy_id = note_a = ref_a = ref_b = None
    note_p = ref_p = scratch_project = None
    service_key, anon_key = supabase_keys()
    cid, csec = google_client()
    gtok = google_access_token(service_key, cid, csec)
    ujwt = user_jwt(service_key, anon_key)

    try:
        # ── Copy the test Doc (throwaway) ───────────────────────────────────
        s, b = gapi(gtok, "POST",
                    f"https://www.googleapis.com/drive/v3/files/{TEST_DOC_ID}/copy"
                    "?supportsAllDrives=true&fields=id,mimeType",
                    {"name": "Atlas per-tab E2E (safe to delete)"})
        if s != 200:
            raise SystemExit(f"files.copy failed {s}: {b[:200]}")
        copy_meta = json.loads(b)
        copy_id = copy_meta["id"]
        copy_mime = copy_meta.get("mimeType", GOOGLE_DOC_MIME)
        copy_url = f"https://docs.google.com/document/d/{copy_id}/edit"
        print(f"COPY DOC: {copy_url}\n")

        # ── (1) PULL TREE ───────────────────────────────────────────────────
        before_json = docs_get(gtok, copy_id)
        tabs = read_tabs_via_shim(before_json)
        by_id = {t["tabId"]: t for t in tabs}
        top = [t for t in tabs if t["parentTabId"] is None]
        nested = [t for t in tabs if t["parentTabId"] is not None]
        parent_title = lambda t: by_id.get(t["parentTabId"], {}).get("title")
        nested_map = {t["title"]: parent_title(t) for t in nested}
        pull_ok = (
            len(tabs) == 6 and len(top) == 4 and len(nested) == 2
            and nested_map.get("subtab of lvl 2") == "Second Level"
            and nested_map.get("Crazy Games Notes") == "Crazy games"
        )
        results["pull-tree"] = (pull_ok,
                                f"total={len(tabs)} top={len(top)} nested={len(nested)} {nested_map}")

        simple = next((t for t in tabs if t["title"] == SIMPLE_TAB_TITLE), None)
        image_tab = next((t for t in tabs if t["title"] == IMAGE_TAB_TITLE), None)
        table_tab = next((t for t in tabs if not t["writable"]), None)
        # The read-only tab that also carries an image (Crazy Games Notes: table + img).
        image_ro_tab = next((t for t in tabs if not t["writable"] and t["images"]), None)
        if simple is None or not simple["writable"]:
            raise SystemExit("Simple-text tab 'Tap1' not found or not writable — cannot run write proof.")
        if image_tab is None or not image_tab["writable"]:
            raise SystemExit("Writable tab 'notes' not found — cannot run image-preservation proof.")
        if table_tab is None:
            raise SystemExit("No read-only tab found — cannot run readonly guard.")

        # ── Projects: A = a real project (import target); B = a second one ──
        projs = pg_get(service_key, f"projects?select=id,space_name&user_id=eq.{EXPECTED_SUB}&limit=2")
        if not projs:
            raise SystemExit("No project for the user to import into.")
        project_a = projs[0]["id"]
        space_a = projs[0]["space_name"]
        if len(projs) >= 2:
            project_b = projs[1]["id"]
        else:
            scratch_project = str(uuid.uuid4())
            pg_insert(service_key, "projects", {
                "id": scratch_project, "user_id": EXPECTED_SUB,
                "space_name": space_a, "name": "E2E scratch (safe to delete)",
            })
            project_b = scratch_project

        file_payload = {"id": copy_id, "name": "Atlas E2E imported Doc",
                        "mimeType": copy_mime, "modifiedTime": drive_modified_time(gtok, copy_id)}

        # ── (5) IMPORT-PULL — drive-import creates the note AND pulls inline ──
        s, p = call_function("drive-import", ujwt, anon_key,
                             {"projectId": project_a, "files": [file_payload]})
        imp_ok = s == 200 and p.get("ok") is True and p.get("imported") == 1 and p.get("pulled") == 1
        rows = pg_get(service_key, "project_references?select=id,note_id"
                      f"&user_id=eq.{EXPECTED_SUB}&project_id=eq.{project_a}"
                      f"&drive_file_id=eq.{copy_id}&kind=eq.doc_note") or []
        if rows:
            ref_a = rows[0]["id"]
            note_a = rows[0]["note_id"]
        # Tabs must be populated by the inline pull WITHOUT any cron tick.
        tab_rows = pg_get(service_key, f"doc_note_tabs?select=tab_id&note_id=eq.{note_a}") if note_a else None
        n_tabs = len(tab_rows) if tab_rows else 0
        imp_ok = imp_ok and note_a is not None and n_tabs == 6
        results["import-pull"] = (imp_ok, f"http={s} payload={p} note={note_a} doc_note_tabs={n_tabs}")

        # ── (6) DUP-IMPORT — same Doc, different project → shared note, no pull ──
        s, p = call_function("drive-import", ujwt, anon_key,
                             {"projectId": project_b, "files": [file_payload]})
        rows_b = pg_get(service_key, "project_references?select=id,note_id"
                        f"&user_id=eq.{EXPECTED_SUB}&project_id=eq.{project_b}"
                        f"&drive_file_id=eq.{copy_id}&kind=eq.doc_note") or []
        if rows_b:
            ref_b = rows_b[0]["id"]
        dup_note = rows_b[0]["note_id"] if rows_b else None
        note_count = pg_get(service_key, f"notes?select=id&user_id=eq.{EXPECTED_SUB}&google_doc_id=eq.{copy_id}") or []
        dup_ok = (s == 200 and p.get("imported") == 1 and p.get("pulled") == 0
                  and dup_note == note_a and note_a is not None and len(note_count) == 1)
        results["dup-import-same-note"] = (
            dup_ok, f"http={s} payload={p} new_ref_note={dup_note} notes_for_doc={len(note_count)}")

        # Everything below needs the imported note as the fixture.
        if not (note_a and ref_a):
            raise _Abort("import did not yield a note/reference — dependent proofs skipped")

        # ── (2) WRITE + ROUND-TRIP on the simple tab ────────────────────────
        # Send the tab's OWN markdown (as the reader produced it) plus a marker LINE.
        # readTabs canonicalises every tab's markdown to end in "\n", so a faithful
        # identity input must also end in "\n". Keeps the equality assert STRICT over
        # all of Tap1's real escaped content (\\*, <u>…</u>, bullets, headings).
        m = simple["markdown"]
        assert m.endswith("\n"), "reader markdown is expected to be newline-terminated"
        sent = m + MARKER + "\n"
        s, payload = call_function("drive-writeback", ujwt, anon_key,
                                   {"noteId": note_a, "tabId": simple["tabId"],
                                    "markdown": sent, "overwrite": True})
        write_ok = s == 200 and payload.get("ok") is True and "modifiedTime" in payload
        results["write-ok"] = (write_ok, f"http={s} payload={payload}")

        # Re-read once; this "after" state serves BOTH round-trip and isolation.
        after_json = docs_get(gtok, copy_id)
        after_tabs = read_tabs_via_shim(after_json)
        read_back = next((t["markdown"] for t in after_tabs if t["tabId"] == simple["tabId"]), "")
        rt_ok = read_back == sent
        results["round-trip-identity"] = (
            rt_ok, "byte-identical" if rt_ok else hex_diff(sent, read_back))

        # ── (3) GUARDS ──────────────────────────────────────────────────────
        s, gp = call_function("drive-writeback", ujwt, anon_key,
                              {"noteId": note_a, "markdown": "legacy whole-file body\n", "overwrite": True})
        g1_ok = s == 409 and gp.get("error") == "multitab_unsupported" and gp.get("tabCount") == 6
        results["guard-multitab"] = (g1_ok, f"http={s} payload={gp}")

        s, gp = call_function("drive-writeback", ujwt, anon_key,
                              {"noteId": note_a, "tabId": table_tab["tabId"],
                               "markdown": "attempted edit\n", "overwrite": True})
        g2_ok = s == 409 and gp.get("error") == "tab_readonly"
        results["guard-readonly"] = (g2_ok, f"http={s} payload={gp} (reason={gp.get('reason')!r})")

        # ── (4) ISOLATION — every OTHER tab byte-identical before/after ─────
        before_bodies = flatten_document_tabs(before_json)
        after_bodies = flatten_document_tabs(after_json)
        drifted = [tid for tid in before_bodies
                   if tid != simple["tabId"] and before_bodies.get(tid) != after_bodies.get(tid)]
        iso_ok = not drifted
        results["isolation"] = (
            iso_ok, "5 other tabs untouched" if iso_ok
            else f"DRIFTED tabs: {[by_id.get(t, {}).get('title', t) for t in drifted]}")

        # ── (7) IMAGE-GUARD — image-bearing read-only tab still refuses writes ──
        if image_ro_tab is None:
            results["image-guard"] = (False, "no image-bearing read-only tab in the copy Doc")
        else:
            s, gp = call_function("drive-writeback", ujwt, anon_key,
                                  {"noteId": note_a, "tabId": image_ro_tab["tabId"],
                                   "markdown": "attempted edit\n", "overwrite": True})
            reason = gp.get("reason")
            accepted = reason in ("table", "cropped image", "inline image in text",
                                  "unsupported image format", "image fetch failed", "unmapped image")
            ig_ok = (s == 409 and gp.get("error") == "tab_readonly"
                     and len(image_ro_tab["images"]) >= 1 and accepted)
            results["image-guard"] = (
                ig_ok, f"http={s} images={len(image_ro_tab['images'])} reason={reason!r}")

        # ── (8) STORAGE-DISPLAY — a re-hosted image downloads as image/* ─────
        img_rows = pg_get(service_key, "doc_note_images?select=object_id,storage_path,tab_id"
                          f"&note_id=eq.{note_a}") or []
        if not img_rows:
            results["storage-display"] = (False, "no doc_note_images row for the imported note")
        else:
            path = img_rows[0]["storage_path"]
            st, ctype = storage_get_authenticated("doc-images", path, ujwt, anon_key)
            sd_ok = st == 200 and ctype.startswith("image/")
            results["storage-display"] = (sd_ok, f"rows={len(img_rows)} http={st} content-type={ctype!r}")

        # ── (9) IMAGE-PRESERVATION — writable image tab survives a text edit ─
        detail_parts = []
        pres_ok = False
        it = image_tab["tabId"]
        # (a) Turn the empty writable 'notes' tab into [solo image][text line].
        reqs = []
        end = tab_end_index(before_json, it)
        if end > 2:
            reqs.append({"deleteContentRange": {"range": {"tabId": it, "startIndex": 1, "endIndex": end - 1}}})
        reqs.append({"insertInlineImage": {"location": {"tabId": it, "index": 1}, "uri": PUBLIC_PNG}})
        reqs.append({"insertText": {"location": {"tabId": it, "index": 2}, "text": "\nEditable image tab line"}})
        bs, bb = docs_batch_update(gtok, copy_id, reqs)
        detail_parts.append(f"batchUpdate={bs}")
        if bs != 200:
            results["image-preservation"] = (False, f"insert image batchUpdate {bs}: {bb[:160]}")
        else:
            # (b) Null this ref's baseline, then pull it via the deployed reference-pull.
            pg_patch(service_key, "project_references", f"id=eq.{ref_a}", {"modified_time": None})
            ps, pp = call_function("reference-pull", ujwt, anon_key, {"referenceId": ref_a})
            detail_parts.append(f"pull={ps}/{pp}")
            # (c) After the pull the tab is writable, carries an image placeholder, and
            #     has a doc_note_images row — the editable-image contract.
            trow = pg_get(service_key, "doc_note_tabs?select=writable,body_md"
                          f"&note_id=eq.{note_a}&tab_id=eq.{it}") or []
            irow = pg_get(service_key, "doc_note_images?select=object_id"
                          f"&note_id=eq.{note_a}&tab_id=eq.{it}") or []
            body_md = trow[0]["body_md"] if trow else ""
            writable = bool(trow and trow[0]["writable"])
            has_ph = "![image:" in body_md
            has_row = len(irow) >= 1
            detail_parts.append(f"writable={writable} placeholder={has_ph} img_rows={len(irow)}")
            if writable and has_ph and has_row:
                # (d) Write the SAME markdown + one extra line back through writeback.
                sent2 = body_md + PRESERVE_LINE + "\n"
                ws, wp = call_function("drive-writeback", ujwt, anon_key,
                                       {"noteId": note_a, "tabId": it, "markdown": sent2, "overwrite": True})
                detail_parts.append(f"writeback={ws}")
                # (e) Re-read: the image survived (exactly one) and the new line landed.
                reread = docs_get(gtok, copy_id)
                inline_n, tab_text = tab_inline_and_text(reread, it)
                detail_parts.append(f"inlineObjects={inline_n} newline={'yes' if PRESERVE_LINE in tab_text else 'no'}")
                pres_ok = (ws == 200 and wp.get("ok") is True
                           and inline_n == 1 and PRESERVE_LINE in tab_text)
            results["image-preservation"] = (pres_ok, " ".join(detail_parts))

        # ── (10) PENDING-409 — a pending doc_note write is refused ──────────
        note_p = str(uuid.uuid4())
        ref_p = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()
        pg_insert(service_key, "notes", {
            "id": note_p, "user_id": EXPECTED_SUB, "space_name": space_a, "project_id": project_a,
            "title": "E2E pending", "body": "", "updated_at": now, "is_external": True,
        })
        pg_insert(service_key, "project_references", {
            "id": ref_p, "user_id": EXPECTED_SUB, "project_id": project_a, "kind": "doc_note",
            "title": "E2E pending", "drive_file_id": copy_id, "note_id": note_p,
            "sync_state": "pending",
        })
        s, pp = call_function("drive-writeback", ujwt, anon_key,
                              {"noteId": note_p, "markdown": "attempted pending edit\n"})
        pend_ok = s == 409 and pp.get("error") == "not_synced"
        results["pending-409"] = (pend_ok, f"http={s} payload={pp}")

        # ── (11) SYNC-NOW — reference-pull on the import's ref returns ok ───
        s, pp = call_function("reference-pull", ujwt, anon_key, {"referenceId": ref_a})
        sync_ok = s == 200 and pp.get("ok") is True
        results["sync-now"] = (sync_ok, f"http={s} payload={pp}")

    except _Abort as ab:
        print(f"\n[aborted after import gate] {ab}\n")
    finally:
        # ── Cleanup — runs even on assertion failure ───────────────────────
        # Storage objects are NOT cascaded by a note delete — collect their paths
        # from doc_note_images FIRST, then delete the objects explicitly.
        paths = []
        for nid in (note_a, note_p):
            if not nid:
                continue
            for r in (pg_get(service_key, f"doc_note_images?select=storage_path&note_id=eq.{nid}") or []):
                paths.append(r["storage_path"])
        try:
            storage_delete(service_key, "doc-images", paths)
        except Exception as e:
            print(f"cleanup: storage delete: {e}")
        # References first (all three point at the copy's drive_file_id).
        if copy_id:
            try:
                pg_delete(service_key, "project_references",
                          f"user_id=eq.{EXPECTED_SUB}&drive_file_id=eq.{copy_id}")
            except Exception as e:
                print(f"cleanup: references delete: {e}")
        # Notes — the delete cascades doc_note_tabs + doc_note_images ROWS (note_id FKs).
        note_ids = [n for n in (note_a, note_p) if n]
        if note_ids:
            try:
                pg_delete(service_key, "notes", f"id=in.({','.join(note_ids)})")
            except Exception as e:
                print(f"cleanup: notes delete: {e}")
        if scratch_project:
            try:
                pg_delete(service_key, "projects", f"id=eq.{scratch_project}")
            except Exception as e:
                print(f"cleanup: scratch project delete: {e}")
        if copy_id:
            try:
                gapi(gtok, "PATCH",
                     f"https://www.googleapis.com/drive/v3/files/{copy_id}?supportsAllDrives=true",
                     {"trashed": True})
            except Exception as e:
                print(f"cleanup: trash copy: {e}")
        try:
            os.rmdir(SCRATCH)
        except OSError:
            pass

    # ── Report ──────────────────────────────────────────────────────────────
    order = ["pull-tree", "write-ok", "round-trip-identity",
             "guard-multitab", "guard-readonly", "isolation",
             "import-pull", "dup-import-same-note", "image-guard",
             "storage-display", "image-preservation", "pending-409", "sync-now"]
    print("\n" + "=" * 60)
    print("  RESULT   CHECK                 DETAIL")
    print("-" * 60)
    all_ok = True
    for name in order:
        ok, detail = results.get(name, (False, "not run"))
        all_ok = all_ok and ok
        print(f"  {'PASS' if ok else 'FAIL'}   {name:<21} {detail}")
    print("=" * 60)
    print("ALL PASS" if all_ok else "FAILURES PRESENT — see detail above")
    sys.exit(0 if all_ok else 1)


class _Abort(Exception):
    """Import gate failed — skip dependent proofs, still run cleanup + report."""


if __name__ == "__main__":
    main()
