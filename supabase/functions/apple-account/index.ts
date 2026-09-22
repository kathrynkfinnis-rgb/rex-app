// Sept 22 — Sign in with Apple, the half that runs on a server.
//
// Apple requires that deleting your account also revokes the Sign in with
// Apple connection. You can't do that from the phone: revoking needs a client
// secret signed with a private key, and a private key on a phone isn't
// private. So this function holds both ends.
//
// Two actions:
//
//   link   — the app has just signed in and passes Apple's one-time
//            authorization code. We exchange it with Apple for a refresh
//            token and store it against the user. Called once per sign-in;
//            harmless to repeat.
//   revoke — the user is deleting their account. We hand the stored refresh
//            token back to Apple, which severs the connection, then forget it.
//            Always called BEFORE the account itself is deleted, because it
//            needs the signed-in user to know whose token to use.
//
// Deploying this needs four secrets, alongside the ones send-push already has:
//   APPLE_SIWA_KEY      — the full contents of a .p8 created in the Apple
//                         Developer portal with "Sign in with Apple" enabled
//                         (a different key from the APNs one)
//   APPLE_SIWA_KEY_ID   — that key's Key ID
//   APPLE_TEAM_ID       — X54V2C674U
//   APPLE_CLIENT_ID     — com.kathrynfinnis.rexapp
//
// With the secrets missing, link and revoke both no-op rather than throwing:
// a user should never be unable to delete their account because our Apple
// credentials are wrong. The deletion still happens; the revocation is what
// we'd lose, and that's the lesser failure.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APPLE_AUTH = "https://appleid.apple.com";

function configured(): boolean {
  return Boolean(
    Deno.env.get("APPLE_SIWA_KEY") &&
      Deno.env.get("APPLE_SIWA_KEY_ID") &&
      Deno.env.get("APPLE_TEAM_ID") &&
      Deno.env.get("APPLE_CLIENT_ID"),
  );
}

/// Apple's "client secret" is a short-lived ES256 JWT we sign ourselves.
async function clientSecret(): Promise<string> {
  const pem = Deno.env.get("APPLE_SIWA_KEY")!
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const b64url = (input: string) =>
    btoa(input).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: Deno.env.get("APPLE_SIWA_KEY_ID") }));
  const payload = b64url(JSON.stringify({
    iss: Deno.env.get("APPLE_TEAM_ID"),
    iat: now,
    // Apple allows up to six months; minutes is all we need.
    exp: now + 300,
    aud: APPLE_AUTH,
    sub: Deno.env.get("APPLE_CLIENT_ID"),
  }));

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  const sig = b64url(String.fromCharCode(...new Uint8Array(signature)));
  return `${header}.${payload}.${sig}`;
}

async function appleForm(path: string, fields: Record<string, string>) {
  const body = new URLSearchParams({
    client_id: Deno.env.get("APPLE_CLIENT_ID")!,
    client_secret: await clientSecret(),
    ...fields,
  });
  const response = await fetch(`${APPLE_AUTH}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const text = await response.text();
  return { ok: response.ok, status: response.status, body: text };
}

/// Whose request is this? The role claim isn't enough here — we need the
/// actual user, and only Supabase can tell us that from their access token.
async function callerId(req: Request): Promise<string | null> {
  const authorization = req.headers.get("authorization") ?? "";
  const token = authorization.replace(/^[Bb]earer\s+/, "");
  if (!token) return null;
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user) return null;
  return data.user.id;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), { status: 405 });
  }

  const userId = await callerId(req);
  if (!userId) {
    return new Response(JSON.stringify({ error: "Not signed in" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  let body: { action?: string; code?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const ok = (extra: Record<string, unknown> = {}) =>
    new Response(JSON.stringify({ ok: true, ...extra }), {
      headers: { "Content-Type": "application/json" },
    });

  if (!configured()) {
    // Say so plainly in the response rather than failing: the caller treats
    // this as "nothing to do", which is the truth until the secrets are set.
    return ok({ skipped: "apple credentials not configured" });
  }

  if (body.action === "link") {
    if (!body.code) {
      return new Response(JSON.stringify({ error: "No authorization code" }), { status: 400 });
    }
    const result = await appleForm("/auth/token", {
      grant_type: "authorization_code",
      code: body.code,
    });
    if (!result.ok) {
      // A stale or already-used code is ordinary — Apple issues them once,
      // and a sign-in that reuses one isn't a problem worth surfacing.
      return ok({ skipped: "apple declined the code", status: result.status });
    }
    const refreshToken = JSON.parse(result.body).refresh_token;
    if (!refreshToken) return ok({ skipped: "no refresh token returned" });

    await supabase.from("apple_credentials").upsert({
      user_id: userId,
      refresh_token: refreshToken,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });
    return ok({ linked: true });
  }

  if (body.action === "revoke") {
    const { data } = await supabase
      .from("apple_credentials")
      .select("refresh_token")
      .eq("user_id", userId)
      .maybeSingle();
    // Someone who signed up with email and password has nothing to revoke.
    if (!data?.refresh_token) return ok({ skipped: "no apple credential" });

    const result = await appleForm("/auth/revoke", {
      token: data.refresh_token,
      token_type_hint: "refresh_token",
    });
    // Either way the row goes: the account is about to be deleted, and a
    // token we can't revoke is not a token worth keeping.
    await supabase.from("apple_credentials").delete().eq("user_id", userId);
    return ok({ revoked: result.ok, status: result.status });
  }

  return new Response(JSON.stringify({ error: "Unknown action" }), { status: 400 });
});
