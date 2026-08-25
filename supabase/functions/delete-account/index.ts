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
 *        not presence-only), revokes the Sign in with Apple token (best-effort),
 *        purges Vault secrets, deletes the auth user.
 *        →  200 { ok: true }
 *      Body (optional, JSON): { apple_authorization_code, apple_client_id }
 *        — a FRESH ASAuthorization code the client re-obtained at delete time.
 *        Supabase never stores an Apple refresh token for the native id_token
 *        sign-in, so the token to revoke can only come from the client.
 *
 * Auth:  Authorization: Bearer <Supabase user JWT>  (verified — this destroys the
 *        account, so presence-only like `capture` is not enough).
 *
 * Env (auto-injected by the platform):
 *   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
 * Env (set by hand, for Apple token revocation — guideline 5.1.1(v)):
 *   APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (the .p8 PKCS#8 PEM),
 *   APPLE_CLIENT_IDS (comma-separated bundle ids: Mac app, iOS app)
 *
 * Deploy: supabase functions deploy delete-account --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, tooManyRequests } from "../_shared/rate_limit.ts";

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

// ── Sign in with Apple revocation (App Store guideline 5.1.1(v)) ────────────
//
// Apple's /auth/revoke needs (a) a client secret — an ES256 JWT signed with the
// team's .p8 key — and (b) a refresh or access token. We hold neither: the apps
// sign in with `signInWithIdToken`, so Supabase stores no Apple refresh token and
// the id_token itself isn't revocable. The client therefore re-runs the Apple
// authorization at delete time and passes the one-shot `authorization_code`,
// which we exchange for a refresh token here and immediately revoke.

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** ES256 client secret for appleid.apple.com, signed with the .p8 private key. */
async function appleClientSecret(clientId: string, teamId: string, keyId: string,
                                 privateKeyPem: string): Promise<string> {
  const pkcs8 = privateKeyPem
    .replace(/\\n/g, "\n")                          // survives single-line env vars
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pkcs8), (ch) => ch.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId };
  const claims = {
    iss: teamId, iat: now, exp: now + 300,
    aud: "https://appleid.apple.com", sub: clientId,
  };
  const encode = (o: unknown) => base64url(new TextEncoder().encode(JSON.stringify(o)));
  const signingInput = `${encode(header)}.${encode(claims)}`;
  // ECDSA signatures from WebCrypto are already raw r||s — exactly JWS form.
  const sig = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput)));
  return `${signingInput}.${base64url(sig)}`;
}

/**
 * Best-effort: exchange the client's fresh authorization code for an Apple refresh
 * token and revoke it. Never throws — a failed revocation must not block deletion.
 */
async function revokeAppleToken(authCode: string, clientId: string): Promise<void> {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
  const allowedIds = (Deno.env.get("APPLE_CLIENT_IDS") ?? "")
    .split(",").map((s) => s.trim()).filter(Boolean);
  if (!teamId || !keyId || !privateKey || allowedIds.length === 0) {
    console.error("delete-account: Apple revocation not configured — skipping");
    return;
  }
  if (!allowedIds.includes(clientId)) {
    console.error("delete-account: unknown apple_client_id — skipping revocation");
    return;
  }

  try {
    const clientSecret = await appleClientSecret(clientId, teamId, keyId, privateKey);

    const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        grant_type: "authorization_code",
        code: authCode,
      }),
    });
    if (!tokenRes.ok) {
      console.error("delete-account: Apple code exchange failed", tokenRes.status,
        await tokenRes.text());
      return;
    }
    const { refresh_token } = await tokenRes.json() as { refresh_token?: string };
    if (!refresh_token) {
      console.error("delete-account: Apple code exchange returned no refresh_token");
      return;
    }

    const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        token: refresh_token,
        token_type_hint: "refresh_token",
      }),
    });
    if (!revokeRes.ok) {
      console.error("delete-account: Apple revoke failed", revokeRes.status,
        await revokeRes.text());
    }
  } catch (e) {
    console.error("delete-account: Apple revocation error", e);
  }
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

  // Destructive + irreversible: a real user deletes once. 3/day tolerates a
  // retry after a transient failure while blocking scripted abuse.
  const rl = await checkRateLimit(admin, userId, "delete-account", 3, 86400);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, CORS_HEADERS);

  // Revoke the Apple token BEFORE the delete — afterwards the client has no way
  // to retry, and Apple keeps the app authorized. Best-effort throughout: a
  // missing code (email/password user, or the user dismissed the Apple sheet)
  // and any Apple-side failure both fall through to the deletion below.
  const body = await req.json().catch(() => ({})) as {
    apple_authorization_code?: string;
    apple_client_id?: string;
  };
  if (body.apple_authorization_code && body.apple_client_id) {
    await revokeAppleToken(body.apple_authorization_code, body.apple_client_id);
  }

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
  // The dedicated Notes/Docs connection (google_docs_connections, 0029) is a
  // per-user singleton; its vault secret is likewise not FK'd to auth.users.
  const { data: dRow } = await admin
    .from("google_docs_connections")
    .select("vault_secret_id")
    .eq("user_id", userId)
    .maybeSingle();
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
  if (dRow?.vault_secret_id) {
    await admin.rpc("delete_google_secret", { secret_id: dRow.vault_secret_id });
  }
  if (c?.vault_secret_id) {
    await admin.rpc("delete_canvas_secret", { secret_id: c.vault_secret_id });
  }

  return json({ ok: true });
});
