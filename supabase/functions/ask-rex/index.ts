// Sept 29 — "Talk to Rex": the conversational half of Explore.
//
// Takes a question in plain English ("a funny film, not too long", "3 days in
// Lisbon with 2 kids"), answers it out of your friends' Rex first, and says
// plainly where every suggestion came from.
//
// Three rules shape the whole thing:
//
//   1. The model picks; it never invents. It is handed a shortlist of real
//      rows and must answer with their ids. The app draws the card from the
//      database, so a restaurant that doesn't exist cannot reach the screen,
//      and a web find cannot accidentally acquire a friend's face.
//
//   2. It reads as you. This function calls PostgREST with the caller's own
//      JWT, so existing row-level security decides whose Rex it can see. If
//      it isn't in your feed it isn't in your answer, and there's no new way
//      to read a stranger's recommendations.
//
//   3. Retrieval, not stuffing. The model sees perhaps forty candidates, never
//      the database. That's what keeps the cost flat whether REX holds 200 Rex
//      or 200,000 — and what makes the answers good.
//
// Where the web comes in: when there aren't enough friend Rex to answer
// properly, the model may name things it knows of, but it never gets to
// describe them as facts. It returns a *search hint* per suggestion and the
// app resolves each one through REX's existing catalogue search (Google
// Places, OpenLibrary, TMDB). Anything that doesn't resolve is dropped. So a
// web card is always a real, findable thing rather than a sentence the model
// wrote — which is the only version of "pull ideas from the internet" that
// can't quietly make things up.
//
// Provider: whichever key is set. Set exactly one of
//   OPENAI_API_KEY   — uses OPENAI_MODEL, default gpt-5-mini
//   GEMINI_API_KEY   — uses GEMINI_MODEL, default gemini-3.5-flash-lite
//
// Both speak near-identical shapes, so switching provider is a secret, not a
// rewrite. Anthropic is deliberately not wired up by default: Sonnet writes
// the best copy of the three but costs six times GPT-5 mini for a job that is
// mostly "pick four of these twenty and say why". Adding it later is one more
// branch in callModel.
//
// On the default model. The plan costed gemini-2.5-flash, which Google has
// since closed to new accounts; its own error names 3.8-flash as the
// replacement, but 3.8 shed every request with "high demand" through three
// retries, so it isn't something to put in front of users yet. Of what does
// answer, 3.5-flash-lite is both the cheapest and the better behaved: asked
// where to eat in Liverpool it used two of the friends' actual Rex, where
// 3.7-flash ignored them and went to the web. At $0.30/$2.50 per million it
// also lands on the same ~$30/month for 8,000 questions the plan assumed.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const OPENAI_MODEL = Deno.env.get("OPENAI_MODEL") ?? "gpt-5-mini";
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.5-flash-lite";
/** Set the ASK_REX_DEBUG secret to have upstream failures come back in the
 *  response instead of only the friendly line. Off by default: an end user
 *  should never be shown a provider's error, and those errors sometimes quote
 *  the request back. Deno.env only reads secrets we set, never the key. */
const DEBUG = Deno.env.get("ASK_REX_DEBUG") === "1";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

/** How many of a friend's Rex the model is allowed to see. Forty is enough to
 *  choose well from and small enough to keep the bill flat. */
const CANDIDATE_LIMIT = 40;
/** Below this many friend matches, the web tier is offered. */
const THIN_ANSWER = 5;
/** Questions per person per rolling 24 hours. See the check in the handler. */
const DAILY_ASK_LIMIT = 40;

type Candidate = {
  id: string;          // recommendation id
  item_id: string;
  title: string;
  subtitle: string | null;
  type: string;
  genre: string | null;
  address: string | null;
  rating: number;
  note: string | null;
  who: string;
  /// Sept 29 — "make sure it's also searching your own Rex, as well as your
  /// friends". It always was: the row-level security on recommendations is
  /// `auth.uid() = user_id OR are_friends(...)`, so your own rows were in the
  /// shortlist from the first day. What was wrong is that the prompt called
  /// every one of them "their friends' recommendations", so the model either
  /// skipped your own or attributed them to somebody else — a Rex of your own
  /// coming back as though a friend had made it.
  mine: boolean;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization) return json({ error: "Not signed in." }, 401);

  // verify_jwt accepts ANY valid project JWT — including the public anon key,
  // which every copy of the app carries. That is not a user. Resolving the
  // token to an actual account is what makes this endpoint safe; the same
  // hole was found in send-push on 21 Sept.
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: auth, error: authError } = await asUser.auth.getUser();
  if (authError || !auth?.user) return json({ error: "Not signed in." }, 401);
  const userId = auth.user.id;

  if (!OPENAI_KEY && !GEMINI_KEY) {
    // Said plainly rather than as a 500, because this is the expected state
    // until someone sets a key, and the app shows it to the user.
    return json({ error: "Talk to Rex isn't switched on yet." }, 503);
  }

  let body: { question?: string; history?: { role: string; text: string }[] };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Bad request." }, 400);
  }

  const question = (body.question ?? "").trim();
  if (!question || question.length > 500) {
    return json({ error: "Ask me something." }, 400);
  }

  // A ceiling, per person, per rolling day. The cost model assumes about eight
  // questions a *month* each; nothing enforced that, so one person in a loop —
  // or one retry bug in the app — could run up a Gemini bill overnight with
  // nothing between them and Google. Forty is far above honest use and far
  // below anything that costs real money (about 24p), so this is a runaway
  // guard nobody using REX normally will ever meet.
  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count: asksToday } = await asUser
    .from("rex_asks")
    .select("id", { count: "exact", head: true })
    .gte("asked_at", dayAgo);
  if ((asksToday ?? 0) >= DAILY_ASK_LIMIT) {
    return json({
      error: "That's a lot of questions for one day — Rex is having a lie down. Try again tomorrow.",
    }, 429);
  }

  // ---------------------------------------------------------------- retrieve
  const [candidates, facts, alreadySuggested] = await Promise.all([
    fetchCandidates(asUser, question, userId),
    fetchFacts(asUser),
    fetchSuggested(asUser),
  ]);

  // ---------------------------------------------------------------- ask
  const prompt = buildPrompt({
    question,
    history: (body.history ?? []).slice(-6),
    candidates,
    facts,
    alreadySuggested,
  });

  let answer: ModelAnswer;
  try {
    answer = await callModel(prompt);
  } catch (error) {
    console.error("ask-rex model call failed", error);
    return json({ error: "Rex couldn't answer that just now.", detail: DEBUG ? String(error).slice(0, 500) : undefined }, 502);
  }

  // The model returns ids; only ids that were actually on the shortlist are
  // allowed through. This is the line that makes rule 1 true rather than
  // merely requested.
  const byId = new Map(candidates.map((c) => [c.id, c]));
  const picks = (answer.picks ?? [])
    .filter((p) => byId.has(p.id))
    .slice(0, 8)
    .map((p) => ({ recommendation_id: p.id, item_id: byId.get(p.id)!.item_id, why: p.why ?? null }));

  // Web suggestions stay unresolved here — the app runs each hint through the
  // catalogue search it already has, and drops anything that doesn't resolve.
  const web = (answer.web ?? []).slice(0, 4).map((w) => ({
    title: w.title,
    search_hint: w.search_hint ?? w.title,
    type: w.type ?? "place",
    why: w.why ?? null,
  }));

  // Remember what was put in front of them, so the next answer differs.
  if (picks.length > 0) {
    await asUser.from("rex_suggestions").upsert(
      picks.map((p) => ({ user_id: userId, item_id: p.item_id })),
      { onConflict: "user_id,item_id" },
    );
  }

  // New facts are written only when the model says the user stated one — an
  // inference from a single question is usually just the question restated.
  //
  // Deduped here rather than by the database. The unique index is on
  // lower(btrim(fact)), an *expression*, and PostgREST's on_conflict only
  // understands a column list — so `onConflict: "user_id,fact"` matched
  // nothing, every insert failed with 42P10, and because the result went
  // unchecked the whole thing silently wrote nothing at all. The facts we
  // already fetched for the prompt are exactly what's needed to compare
  // against, so no extra round trip.
  const seen = new Set(facts.map((f) => f.trim().toLowerCase()));
  const newFacts = (answer.facts ?? [])
    .map((f) => f.trim())
    .filter((f) => f.length >= 3 && f.length <= 300)
    .filter((f) => !seen.has(f.toLowerCase()))
    .slice(0, 3);

  if (newFacts.length > 0) {
    const { error: factError } = await asUser.from("rex_facts").insert(
      // "stated", not "inferred": the prompt only asks for things the person
      // said outright, so labelling these as Rex's own deductions would tell
      // someone "Rex worked this out" about a sentence they typed themselves.
      newFacts.map((fact) => ({ user_id: userId, fact, source: "stated" })),
    );
    // Never fails the answer — someone asking where to eat should not see an
    // error because a note about them couldn't be filed — but no longer
    // silent either, which is how the above went unnoticed.
    if (factError) console.error("ask-rex fact write failed", factError);
  }

  // Logged only now, after a real answer: nobody should lose quota to our
  // own outage. Doubles as the usage figure for the KPI dashboard.
  await asUser.from("rex_asks").insert({ user_id: userId });

  return json({
    answer: answer.answer ?? "",
    picks,
    web,
    // So the app can say "nobody's Rex'd this yet" honestly rather than
    // guessing from an empty list.
    friends_were_thin: candidates.length < THIN_ANSWER,
  });
});

// ============================================================ retrieval

/** Friends' Rex, narrowed by whatever the question is plausibly about.
 *
 *  Deliberately crude for now: Postgres full-text-ish matching on title,
 *  subtitle and note, plus the category words in the question. With a few
 *  hundred Rex in the database this is more than good enough, and it costs
 *  nothing. When the catalogue is big enough that this starts missing things,
 *  the replacement is pgvector over the same columns — the shape of this
 *  function doesn't change, only the ORDER BY. */
async function fetchCandidates(
  db: ReturnType<typeof createClient>,
  question: string,
  meId: string,
): Promise<Candidate[]> {
  const types = typesFor(question);

  let query = db
    .from("recommendations")
    .select(
      "id,rating,note,item_id,user_id," +
        "items!inner(id,type,title,subtitle,genre,address)," +
        "profiles!recommendations_user_id_fkey(username,display_name)",
    )
    .is("trip_id", null)
    .is("list_id", null)
    .gt("rating", 0)
    .order("rating", { ascending: false })
    .limit(CANDIDATE_LIMIT);

  if (types.length > 0) query = query.in("items.type", types);

  const { data, error } = await query;
  if (error) {
    console.error("ask-rex candidate fetch failed", error);
    return [];
  }

  return (data ?? []).map((row: Record<string, unknown>) => {
    const item = row.items as Record<string, unknown>;
    const who = row.profiles as Record<string, unknown> | null;
    return {
      id: String(row.id),
      item_id: String(row.item_id),
      title: String(item.title ?? ""),
      subtitle: (item.subtitle as string) ?? null,
      type: String(item.type ?? ""),
      genre: (item.genre as string) ?? null,
      address: (item.address as string) ?? null,
      rating: Number(row.rating ?? 0),
      note: (row.note as string) ?? null,
      who: String(who?.display_name ?? who?.username ?? "A friend"),
      mine: String(row.user_id) === meId,
    };
  });
}

/** Which categories the question is about, so a request for a film isn't
 *  answered with restaurants. An empty list means "no idea — show everything",
 *  which is the safe way to be wrong. */
function typesFor(question: string): string[] {
  const q = question.toLowerCase();
  const types: string[] = [];
  if (/\b(film|movie|watch|cinema)\b/.test(q)) types.push("movie");
  if (/\b(tv|series|show|box set)\b/.test(q)) types.push("tv");
  if (/\b(book|read|novel|author)\b/.test(q)) types.push("book");
  if (/\b(podcast|listen)\b/.test(q)) types.push("podcast");
  if (/\b(recipe|cook|make for dinner)\b/.test(q)) types.push("recipe");
  if (/\b(eat|restaurant|bar|pub|caf|coffee|lunch|dinner|drink|stay|hotel|place|visit|go)\b/.test(q)) {
    types.push("place", "event");
  }
  if (/\b(trip|itinerary|days? in|weekend|holiday)\b/.test(q)) types.push("place", "event", "trip");
  return [...new Set(types)];
}

async function fetchFacts(db: ReturnType<typeof createClient>): Promise<string[]> {
  const { data } = await db
    .from("rex_facts")
    .select("fact")
    .order("updated_at", { ascending: false })
    .limit(30);
  return (data ?? []).map((row: Record<string, unknown>) => String(row.fact));
}

async function fetchSuggested(db: ReturnType<typeof createClient>): Promise<string[]> {
  const { data } = await db
    .from("rex_suggestions")
    .select("item_id")
    .order("suggested_at", { ascending: false })
    .limit(40);
  return (data ?? []).map((row: Record<string, unknown>) => String(row.item_id));
}

// ============================================================ the prompt

type ModelAnswer = {
  answer?: string;
  picks?: { id: string; why?: string }[];
  web?: { title: string; search_hint?: string; type?: string; why?: string }[];
  facts?: string[];
};

function buildPrompt(input: {
  question: string;
  history: { role: string; text: string }[];
  candidates: Candidate[];
  facts: string[];
  alreadySuggested: string[];
}): { system: string; user: string } {
  const system = [
    "You are Rex, helping someone choose from recommendations their friends have actually made.",
    "",
    "You will be given a numbered list of your friends' recommendations. Choose from that list.",
    "Never invent an entry and never change what a friend wrote — their note is quoted verbatim",
    "in the app, so paraphrasing it would put words in their mouth.",
    "",
    "Some entries are the person's own Rex, marked as such. Use them — being reminded of somewhere",
    "you loved two years ago is one of the best things REX can do — but say so: \"you rated this\",",
    "not a friend's name. Lead with a friend's where both fit, since the point of REX is other",
    "people; their own are the better answer when nothing else comes close, or when the question",
    "is plainly about their own history (\"where did I go in Lisbon?\").",
    "",
    "If the list genuinely doesn't answer the question, say so plainly and use `web` to name up to",
    "three things you know of that would. Do not state facts about them — no ratings, no addresses,",
    "no opening times. Give a `search_hint` precise enough to find the thing, and the app will look",
    "it up. A web suggestion is a starting point, not a recommendation.",
    "",
    "Write like a friend who knows them, not a listings site: two or three sentences, no preamble,",
    "no bullet points, no restating the question. British English.",
    "",
    "Address them as \"you\", and the people whose Rex you are quoting as \"your friends\" — they are",
    "the user's friends, never yours. Saying \"my friends haven't Rex'd anything in Edinburgh\" claims",
    "a social circle you don't have, and makes the one thing REX is for sound like it belongs to a",
    "chatbot. Better still, use the person's name: \"Danny's been to…\".",
    "",
    "Reply with JSON only, in this shape:",
    '{"answer": "...", "picks": [{"id": "<id from the list>", "why": "one short line"}],',
    "",
    "The app shows each friend's own note on the card, underneath your `why`. So `why` must",
    "say something the note doesn't — why this one answers *their question*, given what you",
    "know about them. Never summarise or reword the note; if you have nothing to add beyond",
    "it, leave `why` out entirely.",
    ' "web": [{"title": "...", "search_hint": "...", "type": "place|movie|tv|book|podcast", "why": "..."}],',
    ' "facts": ["a durable preference they stated, in their words"]}',
    "",
    "`facts` is for things worth remembering next time and only when they said it outright —",
    '"I have two kids", "I trust Rotten Tomatoes". Never guess from a single question, and never',
    "record anything about health, politics, religion, sexuality or money. Usually [].",
  ].join("\n");

  const lines: string[] = [];

  if (input.facts.length > 0) {
    lines.push("What you know about them:");
    for (const fact of input.facts) lines.push(`- ${fact}`);
    lines.push("");
  }

  if (input.history.length > 0) {
    lines.push("Earlier in this conversation:");
    for (const turn of input.history) lines.push(`${turn.role}: ${turn.text}`);
    lines.push("");
  }

  if (input.candidates.length > 0) {
    lines.push("Recommendations from them and their friends:");
    for (const c of input.candidates) {
      const bits = [
        `id=${c.id}`,
        `"${c.title}"`,
        c.subtitle ? `(${c.subtitle})` : "",
        `${c.type}${c.genre ? `/${c.genre}` : ""}`,
        c.address ? `at ${c.address}` : "",
        c.mine ? `they Rex'd this themselves, ${c.rating}/10` : `${c.who} rated it ${c.rating}/10`,
        c.note ? `and said: "${c.note}"` : "",
        input.alreadySuggested.includes(c.item_id) ? "[already suggested before]" : "",
      ].filter(Boolean);
      lines.push(`- ${bits.join(" ")}`);
    }
    lines.push("");
  } else {
    lines.push("Neither they nor their friends have Rex'd anything that fits. Lean on `web`.");
    lines.push("");
  }

  lines.push(`They asked: ${input.question}`);

  return { system, user: lines.join("\n") };
}

// ============================================================ the model

async function callModel(prompt: { system: string; user: string }): Promise<ModelAnswer> {
  const raw = await withRetry(() => (GEMINI_KEY ? callGemini(prompt) : callOpenAI(prompt)));
  return parseAnswer(raw);
}

/** Hosted models are busy sometimes — Gemini answered the very first real
 *  question with a 503 "high demand". That isn't a failure worth showing
 *  someone who just asked where to eat, so a couple of quick retries sit
 *  between them and it.
 *
 *  Only for the statuses that mean "try again". A 400 or a 401 will fail the
 *  same way however many times it is sent, and retrying those would just make
 *  the person wait longer for the same answer. */
async function withRetry(call: () => Promise<string>): Promise<string> {
  const backoffMs = [600, 1800];
  for (let attempt = 0; ; attempt++) {
    try {
      return await call();
    } catch (error) {
      const retryable = /\b(429|500|502|503|504)\b/.test(String(error));
      if (!retryable || attempt >= backoffMs.length) throw error;
      await new Promise((resolve) => setTimeout(resolve, backoffMs[attempt]));
    }
  }
}

async function callOpenAI(prompt: { system: string; user: string }): Promise<string> {
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_KEY}`,
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      messages: [
        { role: "system", content: prompt.system },
        { role: "user", content: prompt.user },
      ],
      response_format: { type: "json_object" },
    }),
  });
  if (!response.ok) throw new Error(`OpenAI ${response.status}: ${await response.text()}`);
  const data = await response.json();
  return data.choices?.[0]?.message?.content ?? "";
}

async function callGemini(prompt: { system: string; user: string }): Promise<string> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_KEY}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: prompt.system }] },
      contents: [{ role: "user", parts: [{ text: prompt.user }] }],
      generationConfig: { responseMimeType: "application/json" },
    }),
  });
  if (!response.ok) throw new Error(`Gemini ${response.status}: ${await response.text()}`);
  const data = await response.json();
  return data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
}

/** Both providers are asked for JSON and both usually comply, but a model that
 *  wraps it in a code fence shouldn't take the whole feature down. */
function parseAnswer(raw: string): ModelAnswer {
  const text = raw.trim().replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
  try {
    return JSON.parse(text) as ModelAnswer;
  } catch {
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(text.slice(start, end + 1)) as ModelAnswer;
      } catch { /* fall through */ }
    }
    // Rather than failing outright: the prose is the valuable half, and an
    // answer with no cards still beats an error.
    return { answer: text, picks: [], web: [], facts: [] };
  }
}
