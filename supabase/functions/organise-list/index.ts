// Oct 3 — "Let Rex suggest structure for a free-text list. Headings and
// bullets already survive a paste. The next step is offering to organise an
// unstructured one — with a way back to the original, since it's the author's
// text."
//
// The hard part is not finding the structure, it's not damaging the text while
// doing it. A model asked to "tidy this up" will rewrite it: smooth a phrase,
// merge two items, drop the aside that made the note worth reading. For
// somebody's own baby-essentials list that is a much worse outcome than no
// structure at all.
//
// So the model never returns prose. The caller splits the text into numbered
// lines and sends those; the model returns only *line numbers* — which lines
// are headings, which are bullets. The app applies that to its own copy of the
// lines, so every word on screen afterwards is a word the author typed, and
// "back to the original" is just dropping the answer.
//
// RexNotesParser (the client-side reader) then renders the result exactly as
// it renders a paste that arrived with structure already in it, so there is
// one set of rules for how a list looks, not two.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

/** Long enough for a real list, short enough that one call stays cheap. */
const MAX_LINES = 400;

const TOOL = {
  name: "mark_structure",
  description: "Return which of the author's own lines are headings and which are list items.",
  input_schema: {
    type: "object",
    properties: {
      headings: {
        type: "array",
        items: { type: "integer" },
        description: "Line numbers that introduce a group — a label, a category, a place name.",
      },
      bullets: {
        type: "array",
        items: { type: "integer" },
        description: "Line numbers that are one item in a list.",
      },
    },
    required: ["headings", "bullets"],
  },
};

const PROMPT = `You are given someone's notes, one numbered line per line.

Say which lines are HEADINGS (a short label introducing the lines under it —
"Sleepsuits", "Day 2", "Books", "South of the river") and which are BULLETS
(one item in a list).

Rules:
- Return line numbers only. Never return text. You are not editing anything.
- A line is only a heading if the lines after it belong under it. A heading
  with nothing under it is not a heading.
- Leave anything that reads as a sentence or a paragraph out of both lists.
  Prose is not a bullet, and a wrongly bulleted paragraph is worse than an
  unstructured note.
- A line that is already a bullet (starts with -, *, •) is already marked;
  don't include it.
- If the notes genuinely have no structure, return two empty arrays. That is a
  perfectly good answer and much better than inventing groupings.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization) {
    return new Response(JSON.stringify({ error: "Not signed in." }), { status: 401, headers: CORS });
  }
  // Same reasoning as ask-rex: verify_jwt accepts the public anon key, which
  // is not a user. Resolve the token to an account before spending anything.
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: auth, error: authError } = await asUser.auth.getUser();
  if (authError || !auth?.user) {
    return new Response(JSON.stringify({ error: "Not signed in." }), { status: 401, headers: CORS });
  }

  let body: { lines?: string[] };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Bad request." }), { status: 400, headers: CORS });
  }

  const lines = (body.lines ?? []).slice(0, MAX_LINES);
  if (lines.length < 3) {
    // Nothing to organise, and no reason to bill a call to find that out.
    return new Response(JSON.stringify({ headings: [], bullets: [] }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) {
    return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY not configured" }), { status: 500, headers: CORS });
  }

  const numbered = lines.map((line, index) => `${index}: ${line}`).join("\n");

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": key,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-5",
      max_tokens: 4096,
      system: PROMPT,
      messages: [{ role: "user", content: numbered }],
      tools: [TOOL],
      tool_choice: { type: "tool", name: "mark_structure" },
    }),
  });

  if (!res.ok) {
    const errBody = await res.text();
    return new Response(
      JSON.stringify({ error: `Couldn't organise that [${res.status}]: ${errBody.slice(0, 200)}` }),
      { status: 502, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }

  const data = await res.json();
  const use = (data.content ?? []).find((c: { type?: string }) => c.type === "tool_use");
  const input = (use?.input ?? {}) as { headings?: unknown; bullets?: unknown };

  // Every number is checked against the lines actually sent. A model that
  // returns line 900 of a 40-line note gets that index dropped rather than
  // the app trying to mark a line that isn't there.
  const clean = (value: unknown): number[] =>
    Array.isArray(value)
      ? [...new Set(value.filter((n): n is number => Number.isInteger(n) && n >= 0 && n < lines.length))]
      : [];

  const headings = clean(input.headings);
  const bullets = clean(input.bullets).filter((n) => !headings.includes(n));

  return new Response(JSON.stringify({ headings, bullets }), {
    headers: { ...CORS, "Content-Type": "application/json" },
  });
});
