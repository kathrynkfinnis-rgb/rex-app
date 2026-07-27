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
async function callLovableAI(prompt: string, userText: string): Promise<ExtractedRec[]> {
  const key = process.env.LOVABLE_API_KEY;
  if (!key) throw new Error("LOVABLE_API_KEY not configured");
  const res = await fetch("https://ai.gateway.lovable.dev/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model: "google/gemini-2.5-flash",
      messages: [
        { role: "system", content: prompt },
        { role: "user", content: userText.slice(0, 60000) },
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "recommendations",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            required: ["items"],
            properties: {
              items: {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
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
                  },
                },
              },
            },
          },
        },
      },
    }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`AI extraction failed [${res.status}]: ${body.slice(0, 300)}`);
  }
  const json: any = await res.json();
  const content = json.choices?.[0]?.message?.content ?? "{}";
  try {
    const parsed = JSON.parse(content);
    const items: ExtractedRec[] = Array.isArray(parsed.items) ? parsed.items : [];
    return items.filter((i) => i.title && i.title.trim().length > 0);
  } catch {
    return [];
  }
}

const PROMPT = `You extract book/film/TV/restaurant recommendations from user notes, CSV rows, or podcast/blog text.

For each distinct recommendation, output:
- title: the work or place name only (no rating, no commentary)
- creator: author for books, director/showrunner for film/TV, cuisine or city for places (null if unknown)
- note: the person's comment about it, cleaned up (null if none)
- rating: if a numeric rating is present, normalize to a 1-10 scale (e.g. 4/5 -> 8, 9/10 -> 9). null if none.
- type: one of "book", "movie", "tv", "place" — your best guess

Skip lines that aren't specific works or places. Skip duplicates. Never invent items.`;

export const extractFromText = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { text: string; source: string }) =>
    z.object({ text: z.string().min(1).max(200000), source: z.string().min(1).max(80) }).parse(d),
  )
  .handler(async ({ data, context }) => {
    const extracted = await callLovableAI(PROMPT, data.text);
    if (!extracted.length) return { inserted: 0 };
    const rows = extracted.slice(0, 200).map((e) => ({
      user_id: context.userId,
      source: data.source,
      raw_title: e.title.trim().slice(0, 300),
      raw_creator: e.creator?.slice(0, 200) ?? null,
      raw_note: e.note?.slice(0, 2000) ?? null,
      raw_rating: typeof e.rating === "number" ? Math.max(1, Math.min(10, e.rating)) : null,
      suggested_type: e.type ?? null,
      status: "pending",
    }));
    const { error } = await context.supabase.from("import_staging").insert(rows);
    if (error) throw new Error(error.message);
    return { inserted: rows.length };
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
    if (!row.suggested_type) throw new Error("Set a type before approving");

    let itemId = row.resolved_item_id as string | null;
    if (!itemId && row.resolved_external_id && row.resolved_external_source) {
      const { data: existing } = await context.supabase
        .from("items")
        .select("id")
        .eq("external_source", row.resolved_external_source)
        .eq("external_id", row.resolved_external_id)
        .maybeSingle();
      itemId = existing?.id ?? null;
    }
    if (!itemId) {
      const { data: created, error: cErr } = await context.supabase
        .from("items")
        .insert({
          type: row.suggested_type,
          title: row.raw_title,
          subtitle: row.resolved_subtitle ?? row.raw_creator ?? null,
          image_url: row.resolved_image_url ?? null,
          external_id: row.resolved_external_id ?? null,
          external_source: row.resolved_external_source ?? null,
          genre: row.resolved_genre ?? null,
        })
        .select("id")
        .single();
      if (cErr) throw new Error(cErr.message);
      itemId = created.id;
    }

    const rating =
      typeof data.rating === "number"
        ? data.rating
        : typeof row.raw_rating === "number"
        ? Math.round(row.raw_rating)
        : 8;

    const { error: rErr } = await context.supabase.from("recommendations").insert({
      user_id: context.userId,
      item_id: itemId,
      rating,
      note: (data.note ?? row.raw_note ?? null)?.slice(0, 2000) || null,
    });
    if (rErr) throw new Error(rErr.message);

    await context.supabase
      .from("import_staging")
      .update({ status: "imported", resolved_item_id: itemId })
      .eq("id", row.id);

    return { ok: true };
  });
