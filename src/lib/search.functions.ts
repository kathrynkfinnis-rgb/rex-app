import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

export type SearchHit = {
  external_id: string;
  external_source: "google_books" | "tmdb_movie" | "tmdb_tv" | "itunes_podcast";
  title: string;
  subtitle: string | null;
  image_url: string | null;
  genre: string | null;
};

// TMDB genre id → name (movies + TV).
const TMDB_GENRES: Record<number, string> = {
  28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
  99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
  27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance",
  878: "Sci-Fi", 10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western",
  10759: "Action & Adventure", 10762: "Kids", 10763: "News", 10764: "Reality",
  10765: "Sci-Fi & Fantasy", 10766: "Soap", 10767: "Talk", 10768: "War & Politics",
};

function tmdbGenreName(ids: unknown): string | null {
  if (!Array.isArray(ids) || !ids.length) return null;
  for (const id of ids) {
    const name = TMDB_GENRES[Number(id)];
    if (name) return name;
  }
  return null;
}

const querySchema = z.object({ q: z.string().min(1).max(120) });

export const searchBooks = createServerFn({ method: "GET" })
  .inputValidator((d: { q: string }) => querySchema.parse(d))
  .handler(async ({ data }): Promise<SearchHit[]> => {
    const url = `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(data.q)}&maxResults=12&printType=books`;
    const res = await fetch(url);
    if (!res.ok) return [];
    const json: any = await res.json();
    const items: any[] = json.items ?? [];
    return items.map((it) => {
      const v = it.volumeInfo ?? {};
      const img: string | undefined = v.imageLinks?.thumbnail ?? v.imageLinks?.smallThumbnail;
      const cats: string[] = Array.isArray(v.categories) ? v.categories : [];
      return {
        external_id: it.id,
        external_source: "google_books" as const,
        title: v.title ?? "Untitled",
        subtitle: (v.authors ?? []).join(", ") || null,
        image_url: img ? img.replace(/^http:/, "https:") : null,
        genre: cats[0] ? cats[0].split("/")[0].trim() : null,
      };
    });
  });

export const searchMovies = createServerFn({ method: "GET" })
  .inputValidator((d: { q: string }) => querySchema.parse(d))
  .handler(async ({ data }): Promise<SearchHit[]> => {
    const key = process.env.TMDB_API_KEY;
    if (!key) return [];
    const url = `https://api.themoviedb.org/3/search/movie?api_key=${key}&query=${encodeURIComponent(data.q)}&include_adult=false`;
    const res = await fetch(url);
    if (!res.ok) return [];
    const json: any = await res.json();
    return (json.results ?? []).slice(0, 15).map((r: any) => ({
      external_id: String(r.id),
      external_source: "tmdb_movie" as const,
      title: r.title ?? r.original_title ?? "Untitled",
      subtitle: r.release_date ? String(r.release_date).slice(0, 4) : null,
      image_url: r.poster_path ? `https://image.tmdb.org/t/p/w200${r.poster_path}` : null,
      genre: tmdbGenreName(r.genre_ids),
    }));
  });

export const searchTv = createServerFn({ method: "GET" })
  .inputValidator((d: { q: string }) => querySchema.parse(d))
  .handler(async ({ data }): Promise<SearchHit[]> => {
    const key = process.env.TMDB_API_KEY;
    if (!key) return [];
    const url = `https://api.themoviedb.org/3/search/tv?api_key=${key}&query=${encodeURIComponent(data.q)}&include_adult=false`;
    const res = await fetch(url);
    if (!res.ok) return [];
    const json: any = await res.json();
    return (json.results ?? []).slice(0, 15).map((r: any) => ({
      external_id: String(r.id),
      external_source: "tmdb_tv" as const,
      title: r.name ?? r.original_name ?? "Untitled",
      subtitle: r.first_air_date ? String(r.first_air_date).slice(0, 4) : null,
      image_url: r.poster_path ? `https://image.tmdb.org/t/p/w200${r.poster_path}` : null,
      genre: tmdbGenreName(r.genre_ids),
    }));
  });

export const searchPodcasts = createServerFn({ method: "GET" })
  .inputValidator((d: { q: string }) => querySchema.parse(d))
  .handler(async ({ data }): Promise<SearchHit[]> => {
    const url = `https://itunes.apple.com/search?media=podcast&entity=podcast&limit=15&term=${encodeURIComponent(data.q)}`;
    const res = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
        Accept: "application/json",
      },
    });
    if (!res.ok) return [];
    const json: any = await res.json();
    return (json.results ?? []).map((r: any) => ({
      external_id: String(r.collectionId ?? r.trackId),
      external_source: "itunes_podcast" as const,
      title: r.collectionName ?? r.trackName ?? "Untitled",
      subtitle: r.artistName ?? null,
      image_url: r.artworkUrl600 ?? r.artworkUrl100 ?? null,
      genre: Array.isArray(r.genres) ? r.genres.find((g: string) => g && g !== "Podcasts") ?? r.primaryGenreName ?? null : r.primaryGenreName ?? null,
    }));
  });
