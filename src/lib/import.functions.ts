import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { searchBooks, searchMovies, searchTv } from "@/lib/search.functions";

type ItemType = "book" | "movie" | "tv" | "place";

type ExtractedRec = {
  title: string;
  creator?: string | null;
  note?: string | null;
  rating?: number | null;
  type?: ItemType | null;
  /** Heading the item sat under in the source doc, e.g. "Brunch". */
  section?: string | null;
  /** A URL linked next to the item in the source doc. */
  url?: string | null;
};

// -------- Google Sheets: fetch as CSV via the public gviz endpoint --------
// Requires the sheet to be shared with "Anyone with the link".
function sheetIdFromUrl(url: string): { id: string; gid: string | null } | null {
  const m = url.match(/\/spreadsheets\/d\/([a-zA-Z0-9-_]+)/);
  if (!m) return null;
  const gidMatch = url.match(/[?#&]gid=(\d+)/);
  return { id: m[1], gid: gidMatch ? gidMatch[1] : null };
}

export const fetchSheetCsv = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { url: string }) => z.object({ url: z.string().url() }).parse(d))
  .handler(async ({ data }) => {
    const parsed = sheetIdFromUrl(data.url);
    if (!parsed) throw new Error("Not a Google Sheets URL");
    const gid = parsed.gid ?? "0";
    const exportUrl = `https://docs.google.com/spreadsheets/d/${parsed.id}/export?format=csv&gid=${gid}`;
    const res = await fetch(exportUrl);
    if (!res.ok) {
      throw new Error(
        `Couldn't read the sheet (${res.status}). Make sure it's shared with "Anyone with the link".`,
      );
    }
    const csv = await res.text();
    return { csv };
  });

// -------- LLM extraction --------
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
              enum: ["book", "movie", "tv", "place", null],
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

async function callAnthropic(prompt: string, userText: string): Promise<ExtractedRec[]> {
  const key = process.env.ANTHROPIC_API_KEY;
  if (!key) throw new Error("ANTHROPIC_API_KEY not configured");
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": key,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 4096,
      system: prompt,
      messages: [{ role: "user", content: userText.slice(0, 60000) }],
      tools: [EXTRACTION_TOOL],
      tool_choice: { type: "tool", name: "extract_recommendations" },
    }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`AI extraction failed [${res.status}]: ${body.slice(0, 300)}`);
  }
  const json: any = await res.json();
  const toolUse = json.content?.find(
    (b: any) => b.type === "tool_use" && b.name === "extract_recommendations",
  );
  const items: ExtractedRec[] = Array.isArray(toolUse?.input?.items) ? toolUse.input.items : [];
  return items.filter((i) => i.title && i.title.trim().length > 0);
}

const PROMPT = `You extract book/film/TV/restaurant recommendations from user notes, CSV rows, or podcast/blog text.

For each distinct recommendation, output:
- title: the work or place name only (no rating, no commentary)
- creator: author for books, director/showrunner for film/TV, cuisine or city for places (null if unknown)
- note: the person's comment about it, cleaned up (null if none)
- rating: if a numeric rating is present, normalize to a 1-10 scale (e.g. 4/5 -> 8, 9/10 -> 9). null if none.
- type: one of "book", "movie", "tv", "place" — your best guess
- section: the heading this item appeared under, copied verbatim (e.g. "Brunch", "Museums", "Day 2"). Use the nearest heading above the item. null if the document has no headings.
- url: a link written next to or attached to the item. null if none.

Preserve the document's own structure: if it is organised under headings, every
item must carry the heading it belongs to, so an itinerary keeps its shape.

Skip lines that aren't specific works or places. Skip duplicates. Never invent items.`;

export const extractFromText = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { text: string; source: string }) =>
    z.object({ text: z.string().min(1).max(200000), source: z.string().min(1).max(80) }).parse(d),
  )
  .handler(async ({ data, context }) => {
    const extracted = await callAnthropic(PROMPT, data.text);
    if (!extracted.length) return { inserted: 0 };
    const rows = extracted.slice(0, 200).map((e) => ({
      user_id: context.userId,
      source: data.source,
      raw_title: e.title.trim().slice(0, 300),
      raw_creator: e.creator?.slice(0, 200) ?? null,
      raw_note: e.note?.slice(0, 2000) ?? null,
      raw_rating: typeof e.rating === "number" ? Math.max(1, Math.min(10, e.rating)) : null,
      suggested_type: e.type ?? null,
      raw_section: e.section?.trim().slice(0, 120) || null,
      raw_url: e.url?.trim().slice(0, 2000) || null,
      status: "pending",
    }));
    const { error } = await context.supabase.from("import_staging").insert(rows as never);
    if (error) throw new Error(error.message);
    return { inserted: rows.length };
  });

// -------- Google Maps: batch insert pre-typed place rows --------
export const importGoogleMapsPlaces = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator(
    (d: { source: string; places: { title: string; address?: string | null; note?: string | null }[] }) =>
      z
        .object({
          source: z.string().min(1).max(80),
          places: z
            .array(
              z.object({
                title: z.string().min(1).max(300),
                address: z.string().max(500).nullable().optional(),
                note: z.string().max(2000).nullable().optional(),
              }),
            )
            .min(1)
            .max(500),
        })
        .parse(d),
  )
  .handler(async ({ data, context }) => {
    const rows = data.places.map((p) => ({
      user_id: context.userId,
      source: data.source,
      raw_title: p.title.trim().slice(0, 300),
      raw_creator: p.address?.slice(0, 200) ?? null,
      raw_note: p.note?.slice(0, 2000) ?? null,
      raw_rating: null,
      suggested_type: "place" as const,
      status: "pending",
    }));
    const { error } = await context.supabase.from("import_staging").insert(rows);
    if (error) throw new Error(error.message);
    return { inserted: rows.length };
  });

// -------- IMDb: import ratings/watchlist CSV export --------
export const importImdbTitles = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator(
    (d: {
      source: string;
      titles: {
        title: string;
        type: "movie" | "tv";
        year?: string | null;
        rating?: number | null;
        note?: string | null;
      }[];
    }) =>
      z
        .object({
          source: z.string().min(1).max(80),
          titles: z
            .array(
              z.object({
                title: z.string().min(1).max(300),
                type: z.enum(["movie", "tv"]),
                year: z.string().max(20).nullable().optional(),
                rating: z.number().min(0).max(10).nullable().optional(),
                note: z.string().max(2000).nullable().optional(),
              }),
            )
            .min(1)
            .max(1000),
        })
        .parse(d),
  )
  .handler(async ({ data, context }) => {
    const rows = data.titles.map((t) => ({
      user_id: context.userId,
      source: data.source,
      raw_title: t.title.trim().slice(0, 300),
      raw_creator: t.year ? String(t.year).slice(0, 20) : null,
      raw_note: t.note?.slice(0, 2000) ?? null,
      raw_rating: typeof t.rating === "number" ? t.rating : null,
      suggested_type: t.type,
      status: "pending",
    }));
    const { error } = await context.supabase.from("import_staging").insert(rows);
    if (error) throw new Error(error.message);
    return { inserted: rows.length };
  });


// -------- Google Maps: best-effort scrape of a shared list URL --------
export const fetchGoogleMapsList = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { url: string }) => z.object({ url: z.string().url() }).parse(d))
  .handler(async ({ data }) => {
    if (!/(google\.[a-z.]+\/maps|maps\.app\.goo\.gl|goo\.gl\/maps)/i.test(data.url)) {
      throw new Error("Not a Google Maps URL");
    }
    const res = await fetch(data.url, {
      redirect: "follow",
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
      },
    });
    if (!res.ok) throw new Error(`Google blocked the request (${res.status}). Try Takeout export instead.`);
    const html = await res.text();
    // Extract candidate place names from the embedded data blob. Google shipping-URL
    // pages embed lists as nested JSON; place names typically appear as short strings
    // followed by an address. This is best-effort and can break when Google changes markup.
    const names = new Set<string>();
    const regex = /"([A-Z][A-Za-z0-9&'’\-. ]{2,80})",\[null,null,[-\d.]+,[-\d.]+\]/g;
    let m: RegExpExecArray | null;
    while ((m = regex.exec(html)) !== null) {
      names.add(m[1]);
      if (names.size >= 200) break;
    }
    return { titles: Array.from(names) };
  });

// -------- Resolve a staging row to a real item via search --------
async function searchPlaces(q: string): Promise<{
  external_id: string;
  external_source: string;
  title: string;
  subtitle: string | null;
  image_url: string | null;
  genre: string | null;
} | null> {
  const key = process.env.GOOGLE_MAPS_API_KEY;
  if (!key) return null;
  const url = `https://places.googleapis.com/v1/places:searchText`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": key,
      "X-Goog-FieldMask":
        "places.id,places.displayName,places.formattedAddress,places.primaryTypeDisplayName,places.photos",
    },
    body: JSON.stringify({ textQuery: q, pageSize: 1 }),
  });
  if (!res.ok) return null;
  const json: any = await res.json();
  const p = json.places?.[0];
  if (!p) return null;
  const photo = p.photos?.[0]?.name;
  const image = photo
    ? `https://places.googleapis.com/v1/${photo}/media?maxWidthPx=400&key=${key}`
    : null;
  return {
    external_id: p.id,
    external_source: "google_places",
    title: p.displayName?.text ?? q,
    subtitle: p.formattedAddress ?? null,
    image_url: image,
    genre: p.primaryTypeDisplayName?.text ?? null,
  };
}

export const resolveStagingRow = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { id: string }) => z.object({ id: z.string().uuid() }).parse(d))
  .handler(async ({ data, context }) => {
    const { data: row, error } = await context.supabase
      .from("import_staging")
      .select("*")
      .eq("id", data.id)
      .single();
    if (error || !row) throw new Error(error?.message ?? "not found");

    const q = [row.raw_title, row.raw_creator].filter(Boolean).join(" ").slice(0, 120);
    const type = row.suggested_type as ItemType | null;
    let hit:
      | {
          external_id: string;
          external_source: string;
          title: string;
          subtitle: string | null;
          image_url: string | null;
          genre: string | null;
        }
      | null = null;

    if (type === "book") {
      const hits = await searchBooks({ data: { q } });
      hit = hits[0] ?? null;
    } else if (type === "movie") {
      const hits = await searchMovies({ data: { q } });
      hit = hits[0] ?? null;
    } else if (type === "tv") {
      const hits = await searchTv({ data: { q } });
      hit = hits[0] ?? null;
    } else if (type === "place") {
      hit = await searchPlaces(q);
    }

    await context.supabase.from("import_staging").update({
      resolved_external_id: hit?.external_id ?? null,
      resolved_external_source: hit?.external_source ?? null,
      resolved_image_url: hit?.image_url ?? null,
      resolved_subtitle: hit?.subtitle ?? row.raw_creator ?? null,
      resolved_genre: hit?.genre ?? null,
    }).eq("id", row.id);
    return { matched: !!hit, hit };
  });

// -------- Approve: create item + recommendation --------
async function approveRow(
  supabase: any,
  userId: string,
  row: any,
  opts: { rating?: number | null; note?: string | null; tripId?: string | null } = {},
) {
  if (!row.suggested_type) throw new Error("Set a type before approving");

  let itemId = row.resolved_item_id as string | null;
  if (!itemId && row.resolved_external_id && row.resolved_external_source) {
    const { data: existing } = await supabase
      .from("items")
      .select("id")
      .eq("external_source", row.resolved_external_source)
      .eq("external_id", row.resolved_external_id)
      .maybeSingle();
    itemId = existing?.id ?? null;
  }
  if (!itemId) {
    const { data: created, error: cErr } = await supabase
      .from("items")
      .insert({
        type: row.suggested_type,
        title: row.raw_title,
        subtitle: row.resolved_subtitle ?? row.raw_creator ?? null,
        image_url: row.resolved_image_url ?? null,
        external_id: row.resolved_external_id ?? null,
        external_source: row.resolved_external_source ?? null,
        genre: row.resolved_genre ?? null,
        link_url: row.raw_url ?? null,
      })
      .select("id")
      .single();
    if (cErr) throw new Error(cErr.message);
    itemId = created.id;
  }

  const rating =
    typeof opts.rating === "number"
      ? opts.rating
      : typeof row.raw_rating === "number"
      ? Math.round(row.raw_rating)
      : 8;

  const { error: rErr } = await supabase.from("recommendations").insert({
    user_id: userId,
    item_id: itemId,
    rating,
    note: (opts.note ?? row.raw_note ?? null)?.slice(0, 2000) || null,
    trip_id: opts.tripId ?? null,
    // Keeps the imported document's own structure — stops land under the
    // heading they appeared beneath ("Brunch", "Museums", "Day 2").
    trip_section: opts.tripId ? row.raw_section ?? null : null,
  });
  if (rErr) throw new Error(rErr.message);

  await supabase
    .from("import_staging")
    .update({ status: "imported", resolved_item_id: itemId })
    .eq("id", row.id);

  return itemId;
}

export const approveStagingRow = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { id: string; rating?: number | null; note?: string | null }) =>
    z
      .object({
        id: z.string().uuid(),
        rating: z.number().min(1).max(10).nullable().optional(),
        note: z.string().max(2000).nullable().optional(),
      })
      .parse(d),
  )
  .handler(async ({ data, context }) => {
    const { data: row, error } = await context.supabase
      .from("import_staging")
      .select("*")
      .eq("id", data.id)
      .single();
    if (error || !row) throw new Error(error?.message ?? "not found");

    await approveRow(context.supabase, context.userId, row, {
      rating: data.rating,
      note: data.note,
    });
    return { ok: true };
  });

// -------- Approve a batch of staged place rows as a single Trip --------
export const approveStagingAsTrip = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { ids: string[]; tripName: string; note?: string | null }) =>
    z
      .object({
        ids: z.array(z.string().uuid()).min(1).max(100),
        tripName: z.string().min(1).max(200),
        note: z.string().max(2000).nullable().optional(),
      })
      .parse(d),
  )
  .handler(async ({ data, context }) => {
    const { data: rows, error } = await context.supabase
      .from("import_staging")
      .select("*")
      .in("id", data.ids)
      .eq("status", "pending");
    if (error) throw new Error(error.message);
    if (!rows?.length) throw new Error("Nothing to import");

    const { data: tripItem, error: tiErr } = await context.supabase
      .from("items")
      .insert({ type: "trip", title: data.tripName.trim().slice(0, 200) })
      .select("id")
      .single();
    if (tiErr) throw new Error(tiErr.message);

    const { data: tripRec, error: trErr } = await context.supabase
      .from("recommendations")
      .insert({
        user_id: context.userId,
        item_id: tripItem.id,
        rating: 8,
        note: data.note?.slice(0, 2000) || null,
      })
      .select("id")
      .single();
    if (trErr) throw new Error(trErr.message);

    let added = 0;
    for (const row of rows) {
      try {
        await approveRow(context.supabase, context.userId, row, { tripId: tripRec.id });
        added++;
      } catch {
        // skip rows that can't be resolved; they stay in the queue
      }
    }

    return { tripId: tripRec.id as string, added };
  });

