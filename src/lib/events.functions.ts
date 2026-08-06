import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

export type EventHit = {
  external_id: string;
  external_source: "ticketmaster_event" | "google_places";
  title: string;
  subtitle: string | null;
  image_url: string | null;
  address: string | null;
  lat: number | null;
  lng: number | null;
  genre: string | null;
  url: string | null;
};

const inputSchema = z.object({
  q: z.string().min(1).max(120),
  near: z.object({ lat: z.number(), lng: z.number() }).nullable().optional(),
});

function fmtDate(iso: string | undefined | null): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (isNaN(d.getTime())) return null;
  return d.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" });
}

async function searchTicketmaster(q: string, near?: { lat: number; lng: number } | null): Promise<EventHit[]> {
  const key = process.env.TICKETMASTER_API_KEY;
  if (!key) return [];
  const params = new URLSearchParams({
    keyword: q,
    size: "12",
    sort: "date,asc",
    apikey: key,
  });
  if (near) {
    params.set("latlong", `${near.lat},${near.lng}`);
    params.set("radius", "50");
    params.set("unit", "km");
  }
  try {
    const res = await fetch(`https://app.ticketmaster.com/discovery/v2/events.json?${params}`);
    if (!res.ok) return [];
    const json: any = await res.json();
    const events: any[] = json?._embedded?.events ?? [];
    return events.map((e) => {
      const venue = e?._embedded?.venues?.[0];
      const when = fmtDate(e?.dates?.start?.localDate ?? e?.dates?.start?.dateTime);
      const venueName = venue?.name ?? null;
      const city = venue?.city?.name ?? null;
      const address = [venue?.address?.line1, city, venue?.country?.name].filter(Boolean).join(", ") || null;
      const parts = [when, venueName, city].filter(Boolean);
      const images: any[] = Array.isArray(e.images) ? e.images : [];
      const img = images.find((i) => i.ratio === "16_9" && i.width >= 640) ?? images[0];
      const genre = e?.classifications?.[0]?.genre?.name ?? e?.classifications?.[0]?.segment?.name ?? null;
      return {
        external_id: String(e.id),
        external_source: "ticketmaster_event" as const,
        title: e.name ?? "Untitled event",
        subtitle: parts.join(" · ") || null,
        image_url: img?.url ?? null,
        address,
        lat: venue?.location?.latitude ? Number(venue.location.latitude) : null,
        lng: venue?.location?.longitude ? Number(venue.location.longitude) : null,
        genre: genre && genre !== "Undefined" ? genre : null,
        url: e.url ?? null,
      };
    });
  } catch {
    return [];
  }
}

async function searchGooglePlacesEvents(q: string, near?: { lat: number; lng: number } | null): Promise<EventHit[]> {
  const gmk = process.env.GOOGLE_MAPS_API_KEY;
  if (!gmk) return [];
  const body: Record<string, unknown> = { textQuery: q, pageSize: 8 };
  if (near) {
    body.locationBias = {
      circle: { center: { latitude: near.lat, longitude: near.lng }, radius: 50000 },
    };
  }
  try {
    const res = await fetch("https://places.googleapis.com/v1/places:searchText", {
      method: "POST",
      headers: {
        "X-Goog-Api-Key": gmk,
        "Content-Type": "application/json",
        "X-Goog-FieldMask":
          "places.id,places.displayName,places.formattedAddress,places.shortFormattedAddress,places.location,places.primaryTypeDisplayName,places.websiteUri",
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) return [];
    const json: any = await res.json();
    const places: any[] = json.places ?? [];
    return places.map((p) => ({
      external_id: p.id,
      external_source: "google_places" as const,
      title: p.displayName?.text ?? "Untitled",
      subtitle: p.shortFormattedAddress ?? p.formattedAddress ?? null,
      image_url: null,
      address: p.formattedAddress ?? p.shortFormattedAddress ?? null,
      lat: typeof p.location?.latitude === "number" ? p.location.latitude : null,
      lng: typeof p.location?.longitude === "number" ? p.location.longitude : null,
      genre: p.primaryTypeDisplayName?.text ?? null,
      url: p.websiteUri ?? null,
    }));
  } catch {
    return [];
  }
}

export const searchEvents = createServerFn({ method: "POST" })
  .inputValidator((d: { q: string; near?: { lat: number; lng: number } | null }) => inputSchema.parse(d))
  .handler(async ({ data }): Promise<EventHit[]> => {
    const tm = await searchTicketmaster(data.q, data.near ?? null);
    if (tm.length >= 3) return tm;
    const google = await searchGooglePlacesEvents(data.q, data.near ?? null);
    // Merge: Ticketmaster first, then Google fallback (dedupe by external_id + source).
    const seen = new Set<string>();
    const merged: EventHit[] = [];
    for (const hit of [...tm, ...google]) {
      const key = `${hit.external_source}:${hit.external_id}`;
      if (seen.has(key)) continue;
      seen.add(key);
      merged.push(hit);
    }
    return merged;
  });
