// Oct 16, security review — F21.
//
// Ask Rex has had a per-person daily ceiling since 29 September. The three
// other functions that call a paid model had none, so one account in a loop —
// or one retry bug in the app — could run up an Anthropic bill overnight with
// nothing in the way.
//
// Two jobs in here, and they are different:
//
//   resolveCaller   turns a request into an account. extract-recommendations
//                   and extract-recipe-photo only read the `role` claim out of
//                   the JWT payload *without verifying the signature*, trusting
//                   the platform gate to have done it. That is probably true
//                   today, but it is a deploy-time flag recorded nowhere in the
//                   repo, and a single `--no-verify-jwt` deploy would turn the
//                   check into "attacker says they are authenticated". It also
//                   gives no user id, which is why those two could not be
//                   rate-limited at all. Resolving the token through GoTrue
//                   fixes both at once, and is what ask-rex and organise-list
//                   already do.
//
//   withinBudget    the rex_asks pattern against the shared `ai_usage` table:
//                   count this person's calls of this kind in the last rolling
//                   day, refuse past the ceiling, and record the call.
//
// The count is taken before the model call and the row written after it, which
// is the same ordering ask-rex chose: an outage on Anthropic's side shouldn't
// spend somebody's quota. It means the ceiling binds on sequential use and can
// be overshot by firing requests in parallel — a known limit, and the right
// trade for a runaway guard rather than a billing control.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

export interface Caller {
  userId: string;
  client: SupabaseClient;
}

/// The account behind this request, or null. Reads as the user throughout, so
/// RLS decides what the function can see — never the service role.
export async function resolveCaller(req: Request): Promise<Caller | null> {
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization) return null;

  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authorization } },
  });
  const { data, error } = await client.auth.getUser();
  if (error || !data?.user) return null;
  return { userId: data.user.id, client };
}

/// Whether this person may make another call of this kind today.
///
/// Best-effort on the read: if the count can't be taken we allow the call
/// rather than refusing a legitimate one over a transient database error. The
/// ceiling is a runaway guard, and failing it closed would turn a blip into an
/// outage of the feature.
export async function withinBudget(
  caller: Caller,
  kind: string,
  dailyLimit: number,
): Promise<boolean> {
  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count, error } = await caller.client
    .from("ai_usage")
    .select("id", { count: "exact", head: true })
    .eq("kind", kind)
    .gte("used_at", dayAgo);
  if (error) return true;
  return (count ?? 0) < dailyLimit;
}

/// Records a call that actually happened. Fire-and-forget: a failed write
/// should not fail the user's request, it just means one call went uncounted.
export async function recordUse(caller: Caller, kind: string): Promise<void> {
  await caller.client
    .from("ai_usage")
    .insert({ user_id: caller.userId, kind })
    .then(() => {}, () => {});
}

/// What a refusal looks like. Worded per feature rather than shared, because
/// "you have hit a limit" with no idea which one is a bad error message.
export function overBudget(message: string, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify({ error: message }), {
    status: 429,
    headers: { "Content-Type": "application/json", ...headers },
  });
}
