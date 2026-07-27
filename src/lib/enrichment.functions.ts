import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

export type Review = {
  author: string;
  rating: number | null; // 0-10 scale
  text: string;
  url?: string | null;
  created_at?: string | null;
};

export type Enrichment = {
  source: string;
  source_url?: string | null;
  description?: string | null;
  facts: { label: string; value: string }[];
  score?: { value: number; scale: number; count?: number; label: string } | null;
  image_url?: string | null;
  reviews: Review[];
  extra_links?: { label: string; url: string }[];
};

const schema = z.object({ itemId: z.string().uuid() });

export const getItemEnrichment = createServerFn({ method: "GET" })
  .inputValidator((d: { itemId: string }) => schema.parse(d))
  .handler(async ({ data }): Promise<Enrichment | null> => {
    // Read item straight from DB with service role (public info, no PII)
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: item, error } = await supabaseAdmin
      .from("items")
      .select("id, type, title, subtitle, external_id, external_source, address, lat, lng")
      .eq("id", data.itemId)
      .single();
    if (error || !item) return null;

    try {
      if (item.type === "book") return await enrichBook(item);
      if (item.type === "movie") return await enrichTmdb(item, "movie");
      if (item.type === "tv") return await enrichTmdb(item, "tv");
      if (item.type === "place") return await enrichPlace(item);
    } catch (e) {
      console.error("enrichment failed", e);
      return null;
    }
    return null;
  });

async function enrichBook(item: any): Promise<Enrichment | null> {
  let volume: any = null;
  if (item.external_source === "google_books" && item.external_id) {
    const res = await fetch(`https://www.googleapis.com/books/v1/volumes/${encodeURIComponent(item.external_id)}`);
    if (res.ok) volume = await res.json();
  }
  if (!volume) {
    const q = `${item.title}${item.subtitle ? " " + item.subtitle : ""}`;
    const res = await fetch(`https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}&maxResults=1`);
    if (res.ok) {
      const json: any = await res.json();
      volume = json.items?.[0];
    }
  }
  if (!volume) return null;
  const v = volume.volumeInfo ?? {};
  const facts: Enrichment["facts"] = [];
  if (v.authors?.length) facts.push({ label: "Author", value: v.authors.join(", ") });
  if (v.publishedDate) facts.push({ label: "Published", value: String(v.publishedDate).slice(0, 4) });
  if (v.publisher) facts.push({ label: "Publisher", value: v.publisher });
  if (v.pageCount) facts.push({ label: "Pages", value: String(v.pageCount) });
  if (v.categories?.length) facts.push({ label: "Genre", value: v.categories.slice(0, 2).join(", ") });

  const goodreadsSearch = `https://www.goodreads.com/search?q=${encodeURIComponent((v.authors?.[0] ? v.authors[0] + " " : "") + (v.title ?? item.title))}`;

  return {
    source: "Google Books",
    source_url: v.infoLink ?? v.canonicalVolumeLink ?? null,
    description: stripHtml(v.description ?? null),
    facts,
    score: v.averageRating
      ? { value: Number(v.averageRating) * 2, scale: 10, count: v.ratingsCount ?? undefined, label: "Google Books" }
      : null,
    image_url: (v.imageLinks?.thumbnail ?? v.imageLinks?.smallThumbnail)?.replace(/^http:/, "https:") ?? null,
    reviews: [],
    extra_links: [{ label: "Search on Goodreads", url: goodreadsSearch }],
  };
}

async function enrichTmdb(item: any, kind: "movie" | "tv"): Promise<Enrichment | null> {
  const key = process.env.TMDB_API_KEY;
  if (!key) return null;
  let tmdbId = item.external_source === `tmdb_${kind}` ? item.external_id : null;
  if (!tmdbId) {
    const sr = await fetch(`https://api.themoviedb.org/3/search/${kind}?api_key=${key}&query=${encodeURIComponent(item.title)}&include_adult=false`);
    if (sr.ok) {
      const json: any = await sr.json();
      tmdbId = json.results?.[0]?.id ? String(json.results[0].id) : null;
    }
  }
  if (!tmdbId) return null;

  const [detailsRes, reviewsRes, creditsRes] = await Promise.all([
    fetch(`https://api.themoviedb.org/3/${kind}/${tmdbId}?api_key=${key}`),
    fetch(`https://api.themoviedb.org/3/${kind}/${tmdbId}/reviews?api_key=${key}&page=1`),
    fetch(`https://api.themoviedb.org/3/${kind}/${tmdbId}/credits?api_key=${key}`),
  ]);
  if (!detailsRes.ok) return null;
  const d: any = await detailsRes.json();
  const reviewsJson: any = reviewsRes.ok ? await reviewsRes.json() : { results: [] };
  const credits: any = creditsRes.ok ? await creditsRes.json() : {};

  const facts: Enrichment["facts"] = [];
  const year = (d.release_date || d.first_air_date || "").slice(0, 4);
  if (year) facts.push({ label: "Year", value: year });
  if (kind === "movie" && d.runtime) facts.push({ label: "Runtime", value: `${d.runtime} min` });
  if (kind === "tv" && d.number_of_seasons) facts.push({ label: "Seasons", value: String(d.number_of_seasons) });
  if (d.genres?.length) facts.push({ label: "Genre", value: d.genres.map((g: any) => g.name).slice(0, 3).join(", ") });
  const director = credits.crew?.find((c: any) => c.job === "Director")?.name;
  if (director) facts.push({ label: "Director", value: director });
  const creators = d.created_by?.map((c: any) => c.name).join(", ");
  if (creators) facts.push({ label: "Created by", value: creators });
  const cast = credits.cast?.slice(0, 3).map((c: any) => c.name).join(", ");
  if (cast) facts.push({ label: "Starring", value: cast });

  const reviews: Review[] = (reviewsJson.results ?? []).slice(0, 5).map((r: any) => ({
    author: r.author_details?.username || r.author || "Anonymous",
    rating: r.author_details?.rating ?? null, // TMDB reviews are already 0-10
    text: truncate(r.content ?? "", 800),
    url: r.url ?? null,
    created_at: r.created_at ?? null,
  }));

  const links: { label: string; url: string }[] = [];
  if (d.imdb_id) links.push({ label: "View on IMDb", url: `https://www.imdb.com/title/${d.imdb_id}` });
  else if (kind === "tv") links.push({ label: "Search on IMDb", url: `https://www.imdb.com/find?q=${encodeURIComponent(d.name || item.title)}` });

  return {
    source: "TMDB",
    source_url: `https://www.themoviedb.org/${kind}/${tmdbId}`,
    description: d.overview ?? null,
    facts,
    score: typeof d.vote_average === "number" && d.vote_count
      ? { value: Number(d.vote_average), scale: 10, count: d.vote_count, label: "TMDB" }
      : null,
    image_url: d.poster_path ? `https://image.tmdb.org/t/p/w500${d.poster_path}` : null,
    reviews,
    extra_links: links,
  };
}

async function enrichPlace(item: any): Promise<Enrichment | null> {
  const lovableKey = process.env.LOVABLE_API_KEY;
  const mapsKey = process.env.GOOGLE_MAPS_API_KEY;
  if (!lovableKey || !mapsKey) return null;
  const GATEWAY = "https://connector-gateway.lovable.dev/google_maps";

  let placeId: string | null = item.external_source === "google_places" ? item.external_id : null;
  if (!placeId) {
    // Text search fallback
    const searchRes = await fetch(`${GATEWAY}/places/v1/places:searchText`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${lovableKey}`,
        "X-Connection-Api-Key": mapsKey,
        "Content-Type": "application/json",
        "X-Goog-FieldMask": "places.id",
      },
      body: JSON.stringify({
        textQuery: `${item.title}${item.address ? " " + item.address : ""}`,
        maxResultCount: 1,
        ...(item.lat && item.lng
          ? { locationBias: { circle: { center: { latitude: item.lat, longitude: item.lng }, radius: 2000 } } }
          : {}),
      }),
    });
    if (searchRes.ok) {
      const json: any = await searchRes.json();
      placeId = json.places?.[0]?.id ?? null;
    }
  }
  if (!placeId) return null;

  const fields = [
    "id",
    "displayName",
    "formattedAddress",
    "location",
    "rating",
    "userRatingCount",
    "priceLevel",
    "primaryTypeDisplayName",
    "websiteUri",
    "googleMapsUri",
    "regularOpeningHours",
    "editorialSummary",
    "reviews",
    "photos",
  ].join(",");
  const detailsRes = await fetch(`${GATEWAY}/places/v1/places/${encodeURIComponent(placeId)}`, {
    headers: {
      Authorization: `Bearer ${lovableKey}`,
      "X-Connection-Api-Key": mapsKey,
      "X-Goog-FieldMask": fields,
    },
  });
  if (!detailsRes.ok) return null;
  const p: any = await detailsRes.json();

  const facts: Enrichment["facts"] = [];
  if (p.primaryTypeDisplayName?.text) facts.push({ label: "Type", value: p.primaryTypeDisplayName.text });
  if (p.formattedAddress) facts.push({ label: "Address", value: p.formattedAddress });
  if (p.priceLevel) {
    const map: Record<string, string> = {
      PRICE_LEVEL_FREE: "Free",
      PRICE_LEVEL_INEXPENSIVE: "$",
      PRICE_LEVEL_MODERATE: "$$",
      PRICE_LEVEL_EXPENSIVE: "$$$",
      PRICE_LEVEL_VERY_EXPENSIVE: "$$$$",
    };
    facts.push({ label: "Price", value: map[p.priceLevel] ?? p.priceLevel });
  }
  const todayIdx = new Date().getDay(); // 0=Sun
  const weekday = p.regularOpeningHours?.weekdayDescriptions?.[(todayIdx + 6) % 7];
  if (weekday) facts.push({ label: "Hours today", value: weekday.replace(/^[^:]+:\s*/, "") });

  const reviews: Review[] = (p.reviews ?? []).slice(0, 5).map((r: any) => ({
    author: r.authorAttribution?.displayName ?? "Google user",
    rating: typeof r.rating === "number" ? r.rating * 2 : null, // 5-scale -> 10-scale
    text: r.text?.text ?? r.originalText?.text ?? "",
    url: r.authorAttribution?.uri ?? null,
    created_at: r.publishTime ?? null,
  }));

  let image: string | null = null;
  const photoName = p.photos?.[0]?.name;
  if (photoName) {
    image = `${GATEWAY}/places/v1/${photoName}/media?maxWidthPx=800&skipHttpRedirect=false`;
    // But this URL requires auth headers; not directly embeddable. Skip and let existing item.image_url show.
    image = null;
  }

  const links: { label: string; url: string }[] = [];
  if (p.googleMapsUri) links.push({ label: "Open in Google Maps", url: p.googleMapsUri });
  if (p.websiteUri) links.push({ label: "Website", url: p.websiteUri });

  return {
    source: "Google Places",
    source_url: p.googleMapsUri ?? null,
    description: p.editorialSummary?.text ?? null,
    facts,
    score: typeof p.rating === "number"
      ? { value: p.rating * 2, scale: 10, count: p.userRatingCount, label: "Google" }
      : null,
    image_url: image,
    reviews,
    extra_links: links,
  };
}

function stripHtml(s: string | null): string | null {
  if (!s) return null;
  return s.replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
}
function truncate(s: string, n: number): string {
  return s.length > n ? s.slice(0, n).trimEnd() + "…" : s;
}
