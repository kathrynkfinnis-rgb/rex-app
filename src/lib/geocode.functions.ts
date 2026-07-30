import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const GATEWAY = "https://connector-gateway.lovable.dev/google_maps";

export const geocodeMissingPlaces = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { limit?: number }) =>
    z.object({ limit: z.number().int().min(1).max(50).optional() }).parse(d ?? {}),
  )
  .handler(async ({ data, context }) => {
    const lovable = process.env.LOVABLE_API_KEY;
    const gmk = process.env.GOOGLE_MAPS_API_KEY;
    if (!lovable || !gmk) return { updated: 0, checked: 0, remaining: 0, reason: "no_key" as const };

    const { supabase } = context;
    const limit = data.limit ?? 25;

    // Pull candidate place items missing coordinates.
    const { data: rows, error } = await supabase
      .from("items")
      .select("id, title, subtitle, address")
      .in("type", ["place", "event"])
      .is("lat", null)
      .order("created_at", { ascending: false })
      .limit(limit);
    if (error || !rows) return { updated: 0, checked: 0, remaining: 0 };

    const headers = {
      Authorization: `Bearer ${lovable}`,
      "X-Connection-Api-Key": gmk,
      "Content-Type": "application/json",
      "X-Goog-FieldMask":
        "places.formattedAddress,places.location,places.id,places.primaryTypeDisplayName",
    };

    let updated = 0;
    for (const row of rows) {
      const q = [row.title, row.address, row.subtitle].filter(Boolean).join(", ");
      if (!q) continue;
      try {
        const res = await fetch(`${GATEWAY}/places/v1/places:searchText`, {
          method: "POST",
          headers,
          body: JSON.stringify({ textQuery: q, pageSize: 1 }),
        });
        if (!res.ok) continue;
        const json: any = await res.json();
        const p = json.places?.[0];
        const lat = p?.location?.latitude;
        const lng = p?.location?.longitude;
        if (typeof lat !== "number" || typeof lng !== "number") continue;
        const { error: upErr } = await supabase
          .from("items")
          .update({
            lat,
            lng,
            address: row.address ?? p.formattedAddress ?? null,
            external_id: p.id ?? null,
            external_source: "google_places",
          })
          .eq("id", row.id);
        if (!upErr) updated += 1;
      } catch {
        // skip
      }
    }
    const { count } = await supabase
      .from("items")
      .select("id", { count: "exact", head: true })
      .in("type", ["place", "event"])
      .is("lat", null);
    return { updated, checked: rows.length, remaining: count ?? 0 };
  });
