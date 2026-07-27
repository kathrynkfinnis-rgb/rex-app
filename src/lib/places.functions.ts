import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

export type PlaceHit = {
  external_id: string;
  external_source: "google_places";
  title: string;
  subtitle: string | null;
  image_url: string | null;
  photo_name: string | null;
  address: string | null;
  lat: number | null;
  lng: number | null;
  genre: string | null;
};

const GATEWAY = "https://connector-gateway.lovable.dev/google_maps";

function gwHeaders(): Record<string, string> | null {
  const lovable = process.env.LOVABLE_API_KEY;
  const gmk = process.env.GOOGLE_MAPS_API_KEY;
  if (!lovable || !gmk) return null;
  return {
    Authorization: `Bearer ${lovable}`,
    "X-Connection-Api-Key": gmk,
    "Content-Type": "application/json",
  };
}

export const searchPlaces = createServerFn({ method: "POST" })
  .inputValidator((d: { q: string; near?: { lat: number; lng: number } | null }) =>
    z
      .object({
        q: z.string().min(1).max(120),
        near: z.object({ lat: z.number(), lng: z.number() }).nullable().optional(),
      })
      .parse(d),
  )
  .handler(async ({ data }): Promise<PlaceHit[]> => {
    const headers = gwHeaders();
    if (!headers) return [];
    const body: Record<string, unknown> = { textQuery: data.q, pageSize: 10 };
    if (data.near) {
      body.locationBias = {
        circle: {
          center: { latitude: data.near.lat, longitude: data.near.lng },
          radius: 25000,
        },
      };
    }
    const res = await fetch(`${GATEWAY}/places/v1/places:searchText`, {
      method: "POST",
      headers: {
        ...headers,
        "X-Goog-FieldMask":
          "places.id,places.displayName,places.formattedAddress,places.shortFormattedAddress,places.location,places.photos,places.primaryTypeDisplayName",
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
      photo_name: p.photos?.[0]?.name ?? null,
      address: p.formattedAddress ?? p.shortFormattedAddress ?? null,
      lat: typeof p.location?.latitude === "number" ? p.location.latitude : null,
      lng: typeof p.location?.longitude === "number" ? p.location.longitude : null,
    }));
  });

export const getPlacePhotoUrl = createServerFn({ method: "POST" })
  .inputValidator((d: { photoName: string; maxWidth?: number }) =>
    z.object({ photoName: z.string().min(1), maxWidth: z.number().int().min(50).max(1600).optional() }).parse(d),
  )
  .handler(async ({ data }): Promise<string | null> => {
    const headers = gwHeaders();
    if (!headers) return null;
    const w = data.maxWidth ?? 800;
    const res = await fetch(
      `${GATEWAY}/places/v1/${data.photoName}/media?maxWidthPx=${w}&skipHttpRedirect=true`,
      { headers },
    );
    if (!res.ok) return null;
    const json: any = await res.json();
    return typeof json.photoUri === "string" ? json.photoUri : null;
  });
