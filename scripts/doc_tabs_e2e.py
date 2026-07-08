#!/usr/bin/env python3
"""Atlas — live end-to-end proof of per-tab Google Docs sync (Option C).

Exercises the DEPLOYED edge functions against a throwaway Drive copy of Drew's
real 6-tab test Doc, proving the four things that matter for correctness:

  1. PULL TREE     documents.get?includeTabsContent=true → 6 tabs, 4 top-level,
                   2 nested under the right parents (google-sync reads this).
  2. WRITE + ROUND-TRIP  a per-tab write through drive-writeback, then a re-read,
                   is byte-identical to what was sent — i.e. reader∘renderer is
                   the identity on REAL escaped content (\\*, <u>…</u>, bullets…).
  3. GUARDS        legacy whole-file write on a multi-tab Doc ⇒ 409
                   multitab_unsupported; per-tab write on a rich (table/image)
                   tab ⇒ 409 tab_readonly. The server re-decides writability from
                   the LIVE Doc — never a client-cached flag (CLAUDE.md §5).
  4. ISOLATION     a per-tab write touches ONLY that tab; every other tab's
                   content is byte-identical before/after.

Secrets are read at RUNTIME, never embedded and never printed:
  * Supabase service_role + anon keys via `supabase projects api-keys` (JWT role).
  * Google OAuth client id/secret from Config/Secrets.xcconfig.
  * The user's Google refresh token via the read_google_secret RPC (service key),
    minted into an access token exactly as the edge functions do.
  * A real Supabase USER JWT (drive-writeback authenticates via auth.getUser) via
    the GoTrue admin magic-link → verify flow.

The real test Doc is READ-ONLY here; every mutation happens on a fresh copy that
is trashed in the finally block. Run:  python3 scripts/doc_tabs_e2e.py
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
SIMPLE_TAB_TITLE = "Tap1"  # the plain-text tab (t.0-equivalent) we write to
MARKER = "E2E marker line"

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

    drive-writeback authenticates the app user with auth.getUser, so the service
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


def read_tabs_via_shim(doc_json):
    """Derive each tab's markdown/writability with the SAME TS code the edge
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


def flatten_document_tabs(doc_json):
    """{tabId: documentTab-subtree-as-canonical-json} over the whole tab tree."""
    acc = {}

    def walk(tabs):
        for t in tabs:
            tid = t.get("tabProperties", {}).get("tabId")
            acc[tid] = json.dumps(t.get("documentTab", {}), sort_keys=True, ensure_ascii=False)
            walk(t.get("childTabs", []))
    walk(doc_json.get("tabs", []))
    return acc


# ── PostgREST fixtures (service key) ─────────────────────────────────────────
def pg_insert(service_key, table, row):
    h = {"apikey": service_key, "Authorization": "Bearer " + service_key,
         "Prefer": "return=representation"}
    s, b = http("POST", REST + table, h, [row])
    if s not in (200, 201):
        raise SystemExit(f"insert into {table} failed {s}: {b[:200]}")
    return json.loads(b)[0]


def pg_delete(service_key, table, query):
    h = {"apikey": service_key, "Authorization": "Bearer " + service_key}
    http("DELETE", REST + f"{table}?{query}", h)


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
    copy_id = note_id = ref_id = None
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
        copy_id = json.loads(b)["id"]
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
        table_tab = next((t for t in tabs if not t["writable"]), None)
        if simple is None or not simple["writable"]:
            raise SystemExit("Simple-text tab 'Tap1' not found or not writable — cannot run write proof.")
        if table_tab is None:
            raise SystemExit("No read-only tab found — cannot run readonly guard.")

        # ── Fixture rows (a note + a doc_note reference to the copy) ─────────
        now = datetime.now(timezone.utc).isoformat()
        proj = json.loads(http("GET", REST + f"projects?select=id&user_id=eq.{EXPECTED_SUB}&limit=1",
                               {"apikey": service_key, "Authorization": "Bearer " + service_key})[1])
        if not proj:
            raise SystemExit("No project for the user to attach the reference to.")
        project_id = proj[0]["id"]
        note_id = str(uuid.uuid4())  # id/PK has no DB default — generate client-side
        pg_insert(service_key, "notes", {
            "id": note_id, "user_id": EXPECTED_SUB, "title": "E2E doc-tabs", "body": "",
            "body_format": "md", "updated_at": now,
        })
        ref_id = str(uuid.uuid4())
        pg_insert(service_key, "project_references", {
            "id": ref_id, "user_id": EXPECTED_SUB, "project_id": project_id, "kind": "doc_note",
            "drive_file_id": copy_id, "note_id": note_id,
        })

        # ── (2) WRITE + ROUND-TRIP on the simple tab ────────────────────────
        # Send the tab's OWN markdown (as the reader produced it) plus a marker
        # LINE. readTabs canonicalises every tab's markdown to end in "\n", so a
        # faithful identity input must also end in "\n"; we append the marker as a
        # trailing newline-terminated line rather than the non-terminated literal
        # "\nE2E marker line" (which the reader could never byte-reproduce). This
        # keeps the equality assert fully STRICT over all of Tap1's real escaped
        # content (\\*, <u>…</u>, bullets, headings) — nothing is weakened.
        m = simple["markdown"]
        assert m.endswith("\n"), "reader markdown is expected to be newline-terminated"
        sent = m + MARKER + "\n"
        s, b = http("POST", FUNCTIONS + "drive-writeback",
                    {"Authorization": "Bearer " + ujwt, "apikey": anon_key},
                    {"noteId": note_id, "tabId": simple["tabId"], "markdown": sent, "overwrite": True})
        payload = json.loads(b) if b.strip().startswith("{") else {"raw": b[:200]}
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
        s, b = http("POST", FUNCTIONS + "drive-writeback",
                    {"Authorization": "Bearer " + ujwt, "apikey": anon_key},
                    {"noteId": note_id, "markdown": "legacy whole-file body\n", "overwrite": True})
        p = json.loads(b) if b.strip().startswith("{") else {"raw": b[:200]}
        g1_ok = s == 409 and p.get("error") == "multitab_unsupported" and p.get("tabCount") == 6
        results["guard-multitab"] = (g1_ok, f"http={s} payload={p}")

        s, b = http("POST", FUNCTIONS + "drive-writeback",
                    {"Authorization": "Bearer " + ujwt, "apikey": anon_key},
                    {"noteId": note_id, "tabId": table_tab["tabId"],
                     "markdown": "attempted edit\n", "overwrite": True})
        p = json.loads(b) if b.strip().startswith("{") else {"raw": b[:200]}
        g2_ok = s == 409 and p.get("error") == "tab_readonly"
        results["guard-readonly"] = (g2_ok, f"http={s} payload={p} (reason={p.get('reason')!r})")

        # ── (4) ISOLATION — every OTHER tab byte-identical before/after ─────
        before_bodies = flatten_document_tabs(before_json)
        after_bodies = flatten_document_tabs(after_json)
        drifted = [tid for tid in before_bodies
                   if tid != simple["tabId"] and before_bodies.get(tid) != after_bodies.get(tid)]
        iso_ok = not drifted
        results["isolation"] = (
            iso_ok, "5 other tabs untouched" if iso_ok
            else f"DRIFTED tabs: {[by_id.get(t, {}).get('title', t) for t in drifted]}")

    finally:
        # ── Cleanup — runs even on assertion failure ───────────────────────
        if ref_id:
            try:
                pg_delete(service_key, "doc_note_tabs", f"reference_id=eq.{ref_id}")
                pg_delete(service_key, "project_references", f"id=eq.{ref_id}")
            except Exception as e:
                print(f"cleanup: reference/tabs delete: {e}")
        if note_id:
            try:
                pg_delete(service_key, "notes", f"id=eq.{note_id}")
            except Exception as e:
                print(f"cleanup: note delete: {e}")
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
             "guard-multitab", "guard-readonly", "isolation"]
    print("\n" + "=" * 60)
    print("  RESULT   CHECK                 DETAIL")
    print("-" * 60)
    all_ok = True
    for name in order:
        ok, detail = results.get(name, (False, "not run"))
        all_ok = all_ok and ok
        print(f"  {'PASS' if ok else 'FAIL'}   {name:<20}  {detail}")
    print("=" * 60)
    print("ALL PASS" if all_ok else "FAILURES PRESENT — see detail above")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
