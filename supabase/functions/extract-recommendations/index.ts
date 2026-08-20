// Thin, single-purpose proxy for the native app's "Lists" importer (#109)
// and native trip import (#15/#38). The web app already does this same
// extraction inline in a TanStack server function (src/lib/import.functions.ts,
// extractFromText) where ANTHROPIC_API_KEY lives in ordinary server env vars.
// The native app has no server of its own to hide that key in — an Anthropic
// key embedded in the shipped binary is extractable and billable, unlike the
// Google Maps key elsewhere in this app, which is safely bundle-ID-restricted
// by Google itself. This function is the whole reason it's an edge function
// rather than a straight PostgREST call: it's the only piece of the import
// pipeline that actually needs a secret. Everything else (reading/writing
// import_staging, resolving matches, creating the trip/collection) happens
// directly from the app via ordinary authenticated REST calls, same as the
// rest of the native app.
//
// Deliberately does NOT touch the database — it takes text, returns the
// extracted array, and the caller (already holding a valid Supabase session)
// inserts into import_staging itself with its own token. Keeps this function
// to one job.

const EXTRACTION_TOOL = {
  name: "extract_recommendations",
  description: "Return the recommendations extracted from the user's text.",
  input_schema: {
    type: "object",
    required: ["items"],
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          required: ["title", "creator", "note", "rating", "type"],
          properties: {
            title: { type: "string" },
            creator: { type: ["string", "null"] },
            note: { type: ["string", "null"] },
            rating: { type: ["number", "null"] },
            type: {
              type: ["string", "null"],
              enum: ["book", "movie", "tv", "place", "recipe", "event", "podcast", null],
            },
            section: {
              type: ["string", "null"],
              description:
                "The heading this item sat under in the source document, e.g. 'Brunch', 'Museums', 'Day 1'. Null if the document has no headings.",
            },
            url: {
              type: ["string", "null"],
              description: "A URL linked to or written next to this item, if any.",
            },
          },
        },
      },
    },
  },
} as const;

// Same prompt as the web importer — the two pipelines should produce the
// same shape of result regardless of which client asked for it.
const PROMPT = `You extract book/film/TV/restaurant recommendations from user notes, CSV rows, or podcast/blog text.

For each distinct recommendation, output:
- title: the work or place name only (no rating, no commentary)
- creator: author for books, director/showrunner for film/TV, cuisine or city for places (null if unknown)
- note: the person's comment about it, cleaned up (null if none)
- rating: if a numeric rating is present, normalize to a 1-10 scale (e.g. 4/5 -> 8, 9/10 -> 9). null if none.
- type: one of "book", "movie", "tv", "place", "recipe", "event", "podcast" — your best guess
- section: the heading this item appeared under, copied verbatim (e.g. "Brunch", "Museums", "Day 2"). Use the nearest heading above the item. null if the document has no headings.
- url: a link written next to or attached to the item. null if none.

Preserve the document's own structure: if it is organised under headings, every
item must carry the heading it belongs to, so an itinerary keeps its shape.

Skip lines that aren't specific works or places. Skip duplicates. Never invent items.

Extract EVERY item in the document, however many there are — 5 or 50. Do not
stop early, do not summarize, do not sample a subset and call it done. Work
through the whole document from top to bottom before answering. A long
document with many items is normal, not a signal to abbreviate.`;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), { status: 405 });
  }

  // Supabase's edge runtime verifies the JWT in the Authorization header
  // before this handler even runs (verify_jwt defaults to true on deploy) —
  // reaching this line already means the caller has a valid session. No
  // separate auth check needed here, same trust boundary the rest of this
  // app's RLS policies rely on.

  let body: { text?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 });
  }

  const text = (body.text ?? "").slice(0, 200000);
  if (!text.trim()) {
    return new Response(JSON.stringify({ error: "text is required" }), { status: 400 });
  }

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) {
    return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY not configured" }), { status: 500 });
  }

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": key,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      // Sonnet, not Haiku — this is a one-shot paste action, not a chat
      // turn, so the cost/latency tradeoff favors accuracy. Haiku was the
      // likely cause of "only picks up a few items": weaker models are
      // more prone to truncating an enumeration task early on long or
      // messy input regardless of the token budget available to them.
      model: "claude-sonnet-5",
      // Was 4096 - a document with 50+ items, each ~60-100 tokens of JSON
      // output (title/creator/note/rating/type/section/url), could hit
      // that ceiling and silently cut off mid-list.
      max_tokens: 8192,
      system: PROMPT,
      // Was text.slice(0, 60000) despite the 200000-char cap two lines up
      // being the actual intended limit - trimming the input itself to a
      // third of what's allowed was its own source of dropped items on
      // longer documents.
      messages: [{ role: "user", content: text }],
      tools: [EXTRACTION_TOOL],
      tool_choice: { type: "tool", name: "extract_recommendations" },
    }),
  });

  if (!res.ok) {
    const errBody = await res.text();
    return new Response(
      JSON.stringify({ error: `AI extraction failed [${res.status}]: ${errBody.slice(0, 300)}` }),
      { status: 502 },
    );
  }

  const json = await res.json();
  const toolUse = json.content?.find(
    (b: { type: string; name?: string }) => b.type === "tool_use" && b.name === "extract_recommendations",
  );
  const items = Array.isArray(toolUse?.input?.items) ? toolUse.input.items : [];
  const filtered = items.filter(
    (i: { title?: string }) => typeof i.title === "string" && i.title.trim().length > 0,
  );

  return new Response(JSON.stringify({ items: filtered }), {
    headers: { "Content-Type": "application/json" },
  });
});
