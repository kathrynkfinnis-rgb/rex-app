// #175 — sends an actual APNs push for a notification row, once one's
// created.
//
// Deployed and wired up as of Sept 1 2026: APNs Auth Key created (Key ID
// 7982WMVM9R), Push Notifications capability enabled on the App ID, this
// function deployed with its four APNS_* secrets set, and a database
// trigger (tg_send_push_on_notification, via pg_net — the dashboard's own
// "Webhooks" UI wasn't available on this project, so the trigger was
// written directly in SQL instead; see supabase/migrations for anything
// checked in) calling this function on every insert into
// public.notifications. Verified live: a direct invoke read
// notification_preferences correctly and returned 200.
//
// Reference, if this ever needs rebuilding from scratch (a new Apple
// Developer team, a revoked key, a fresh Supabase project):
//   1. Apple Developer Portal (developer.apple.com) -> Certificates,
//      Identifiers & Profiles -> Keys -> create a new key with "Apple Push
//      Notifications service (APNs)" checked. Download the .p8 (only
//      downloadable once) and note its Key ID.
//   2. Make sure the App ID (com.kathrynfinnis.rexapp) has the "Push
//      Notifications" capability enabled (Identifiers -> that App ID ->
//      Capabilities).
//   3. Supabase dashboard -> Edge Functions -> Deploy a new function named
//      "send-push", paste this file's contents.
//   4. Supabase dashboard -> Edge Functions -> send-push -> Secrets, set:
//        APNS_KEY           - the full contents of the downloaded .p8 file
//        APNS_KEY_ID        - the Key ID shown when the key was created
//        APNS_TEAM_ID       - X54V2C674U (already used for App Store Connect)
//        APNS_BUNDLE_ID     - com.kathrynfinnis.rexapp
//        APNS_USE_SANDBOX   - "true" only for a locally-run Xcode debug
//                              build; leave unset for TestFlight/App Store
//                              (those use the production APNs endpoint)
//   5. A trigger on INSERT to public.notifications that calls this
//      function's URL — via the dashboard's Webhooks/Triggers UI if it
//      offers a "Supabase Edge Functions" trigger type, otherwise a plain
//      SQL trigger using pg_net.http_post with an Authorization: Bearer
//      <service role key> header (see git history around Sept 1 2026 for
//      the exact statement used here).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Maps a notification's `type` column to the same preference column
// notification_preferences already uses to gate the in-app bell — push
// respects the exact same per-category choice, not a separate toggle set.
const PREF_COLUMN: Record<string, string> = {
  rec_like: "rec_like",
  rec_comment: "rec_comment",
  // Oct 5 — a reply in a thread you're part of. Shares the rec_comment
  // preference: to whoever receives it, it is the same kind of event.
  rec_comment_thread: "rec_comment",
  rec_tagged: "rec_tagged",
  friend_request: "friend_request",
  friend_accepted: "friend_accepted",
  blast_new: "blast_new",
  blast_comment: "blast_comment",
  friend_new_rec: "friend_new_rec",
  // Oct 19 — these five had no entry, which did two things. They fell
  // through notifCopy to "New activity on Rex" ("this gave me the
  // notification 'new activity on Rex' but it should say 'someone has also
  // replied to a blast'", and before that Rachel's reply) — and, worse, an
  // unmapped type skipped the preference block entirely, so it never checked
  // push_enabled either. A type nobody had taught this map about pushed to
  // people who had push switched off.
  blast_comment_thread: "blast_comment",
  want_tagged: "rec_tagged",
  mention: "mention",
  rec_saved: "rec_saved",
  // Nov 9 — the waiting-requests nudge rides the friend_request toggle
  // rather than adding one of its own. Someone who turned friend requests
  // off does not want a weekly count of them either, and a second switch
  // for the same subject is a switch nobody finds.
  friend_requests_waiting: "friend_request",
};

function notifCopy(type: string, actorName: string, data: Record<string, unknown>): string {
  switch (type) {
    case "rec_like": return `${actorName} liked your Rex`;
    case "rec_comment": return `${actorName} commented on your Rex`;
    case "rec_comment_thread": return `${actorName} also commented on a Rex you commented on`;
    case "rec_tagged": return `${actorName} tagged you on a Rex`;
    case "friend_request": return `${actorName} sent you a friend request`;
    case "friend_accepted": return `${actorName} accepted your friend request`;
    case "blast_new": return `${actorName} put out a blast${data?.title ? `: "${data.title}"` : ""}`;
    case "blast_comment":
      return data?.has_suggestion
        ? `${actorName} suggested something on your blast`
        : `${actorName} replied to your blast`;
    // Oct 14 in the app, and only now here: "if I reply on a blast, and then
    // someone else replies, I should also get a notification." "Also",
    // because you are in this one already.
    case "blast_comment_thread":
      return data?.title
        ? `${actorName} also replied on "${data.title}"`
        : `${actorName} also replied to a blast`;
    case "want_tagged":
      return data?.title
        ? `${actorName} wants to try ${data.title} with you`
        : `${actorName} wants to try something with you`;
    case "mention": return `${actorName} tagged you in a comment`;
    case "rec_saved": return `${actorName} saved your Rex`;
    case "friend_new_rec": return `${actorName} Rex'd ${data?.title || "something new"}`;
    // Nov 9 — ticket_reminder has been inserting rows since 12 October with
    // no case here, so every ticket alert that reached a phone said "New
    // activity on Rex". The one notification whose entire value is naming a
    // time was the one that didn't name it.
    case "ticket_reminder": {
      const what = data?.title ? `Tickets for ${data.title}` : "Tickets";
      const lead = Number(data?.lead_minutes ?? 0);
      if (lead >= 1440) return `${what} go on sale tomorrow`;
      if (lead >= 60) return `${what} go on sale in ${Math.round(lead / 60)} hours`;
      if (lead > 0) return `${what} go on sale in ${lead} minutes`;
      return `${what} are on sale now`;
    }
    // Nov 9 — "we are noticing lots of people have friend requests waiting."
    // One nudge for the pile, never one per request: see the migration
    // 20261109_friend_requests_waiting.sql for why it is batched and capped.
    case "friend_requests_waiting": {
      const n = Number(data?.count ?? 0);
      return n === 1
        ? "You have a friend request waiting"
        : `You have ${n} friend requests waiting`;
    }
    default: return "New activity on Rex";
  }
}

// ES256 JWT for APNs, using Web Crypto directly rather than shelling out —
// Deno's crypto.subtle supports P-256/ECDSA natively, no external binary
// needed the way the App Store Connect helper script (asc.py, Python/
// openssl, run from a dev machine, not an edge function) needed one.
async function makeApnsJwt(): Promise<string> {
  const keyId = Deno.env.get("APNS_KEY_ID")!;
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const pem = Deno.env.get("APNS_KEY")!;

  const pkcs8 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const keyBytes = Uint8Array.from(atob(pkcs8), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", keyBytes, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );

  const header = { alg: "ES256", kid: keyId };
  const payload = { iss: teamId, iat: Math.floor(Date.now() / 1000) };
  const b64url = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const signingInput = `${b64url(header)}.${b64url(payload)}`;

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput),
  );
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `${signingInput}.${sigB64}`;
}


// Sept 21, security review — the comment this replaces said that reaching the
// handler meant the caller held a valid session. It didn't. Supabase's
// verify_jwt accepts ANY valid JWT for this project, and that includes the
// public anon key, which ships inside the app binary and sits in the website's
// source. So this function was callable by anyone who looked.
//
// The role claim is what actually distinguishes them. It is signed by Supabase
// and can't be edited without the JWT secret, so reading it without verifying
// the signature is safe HERE — the runtime has already checked the signature;
// all that's left is to look at who it says this is.
function callerRole(req: Request): string | null {
  const header = req.headers.get("authorization") ?? "";
  const token = header.replace(/^[Bb]earer\s+/, "");
  const payload = token.split(".")[1];
  if (!payload) return null;
  try {
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return (JSON.parse(json) as { role?: string }).role ?? null;
  } catch {
    return null;
  }
}

// Sept 23 — the role claim only exists on a JWT. Supabase's newer keys
// (sb_secret_…) are opaque strings with no claims at all, so a project using
// one would have every push silently refused by this guard. Compare the raw
// token against our own service key as well: same secret, same authority,
// whichever format the project happens to be issuing.
function isServiceRole(req: Request): boolean {
  const token = (req.headers.get("authorization") ?? "").replace(/^[Bb]earer\s+/, "");
  if (!token) return false;
  const ours = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (ours && token === ours) return true;
  return callerRole(req) === "service_role";
}

function rejectUnlessServiceRole(req: Request): Response | null {
  if (isServiceRole(req)) return null;
  return new Response(JSON.stringify({ error: "Not allowed" }), {
    status: 403,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), { status: 405 });
  }

  // Only the notifications trigger sends pushes. Anyone else asking to push
  // "Phoebe commented on your Rex" to an arbitrary user id is an attacker.
  const denied = rejectUnlessServiceRole(req);
  if (denied) return denied;

  // Database Webhooks POST { type, table, record, old_record, schema }.
  const body = await req.json();
  const notification = body.record;
  if (!notification) {
    return new Response(JSON.stringify({ error: "No record in payload" }), { status: 400 });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const prefColumn = PREF_COLUMN[notification.type];
  {
    // Oct 19 — this used to be `if (prefColumn)`, so a type missing from the
    // map above skipped the whole block: no category check, and no
    // push_enabled check either. Push defaults off until someone opts in, and
    // an unrecognised type was quietly ignoring that. Unknown types are
    // gated on push_enabled alone now — the category cannot be judged, but
    // "I turned push off" always can.
    const columns = prefColumn ? `push_enabled, ${prefColumn}` : "push_enabled";
    const { data: prefs } = await supabase
      .from("notification_preferences")
      .select(columns)
      .eq("user_id", notification.user_id)
      .maybeSingle();
    // Defaults mirror notif_pref_enabled() in SQL: missing row means every
    // category is on except friend_new_rec, but push itself defaults off
    // until the user has explicitly opted in on the preferences screen.
    const pushEnabled = prefs?.push_enabled ?? false;
    const categoryEnabled = !prefColumn
      ? true
      : (prefs ? Boolean(prefs[prefColumn as keyof typeof prefs]) : prefColumn !== "friend_new_rec");
    if (!pushEnabled || !categoryEnabled) {
      return new Response(JSON.stringify({ skipped: "preference off" }), { status: 200 });
    }
  }

  const { data: tokenRows } = await supabase
    .from("push_tokens")
    .select("device_token")
    .eq("user_id", notification.user_id);
  // Oct 5 — "we are currently getting double push notifications."
  //
  // One push goes out per device token, so the same token stored twice is two
  // identical notifications on one phone. There is a unique index on
  // (user_id, device_token), but a token can still arrive twice across
  // reinstalls, and this costs nothing to be certain about.
  const tokens = [...new Set((tokenRows ?? []).map((t) => t.device_token).filter(Boolean))]
    .map((device_token) => ({ device_token }));
  if (tokens.length === 0) {
    return new Response(JSON.stringify({ skipped: "no device token" }), { status: 200 });
  }

  let actorName = "Someone";
  if (notification.actor_id) {
    const { data: actor } = await supabase
      .from("profiles")
      .select("username, display_name")
      .eq("id", notification.actor_id)
      .maybeSingle();
    actorName = actor?.display_name || actor?.username || actorName;
  }

  const jwt = await makeApnsJwt();
  const bundleId = Deno.env.get("APNS_BUNDLE_ID")!;
  const host = Deno.env.get("APNS_USE_SANDBOX") === "true"
    ? "api.sandbox.push.apple.com"
    : "api.push.apple.com";

  const results = await Promise.all(tokens.map(async ({ device_token }) => {
    const res = await fetch(`https://${host}/3/device/${device_token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
        // Oct 5 — the other half of "we are getting double push
        // notifications", and the half that holds whatever the cause.
        //
        // Deduplicating tokens fixes one source; a Database Webhook
        // registered twice, or retried, would still deliver the same
        // notification twice and no amount of care inside this function would
        // know. A collapse id is APNs' own answer: two pushes carrying the
        // same one replace each other on the device rather than stacking, so
        // one event is one notification however many times we are asked to
        // send it. The notification's own id is exactly that key.
        ...(notification.id ? { "apns-collapse-id": String(notification.id).slice(0, 64) } : {}),
      },
      body: JSON.stringify({
        aps: {
          alert: { body: notifCopy(notification.type, actorName, notification.data ?? {}) },
          sound: "default",
        },
        // `type` and `actor_id` are here so the app can route a tap without
        // having to infer the destination from entity_type alone — a friendship
        // notification's entity_id is the friendship row, not the person.
        type: notification.type,
        actor_id: notification.actor_id ?? null,
        entity_type: notification.entity_type,
        entity_id: notification.entity_id,
      }),
    });
    return { device_token, status: res.status };
  }));

  return new Response(JSON.stringify({ sent: results }), {
    headers: { "Content-Type": "application/json" },
  });
});
