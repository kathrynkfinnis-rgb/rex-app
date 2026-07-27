import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

export type SearchHit = {
  external_id: string;
  external_source: "google_books" | "tmdb_movie" | "tmdb_tv";
  title: string;
  subtitle: string | null;
  image_url: string | null;
};

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
      return {
        external_id: it.id,
        external_source: "google_books" as const,
        title: v.title ?? "Untitled",
        subtitle: (v.authors ?? []).join(", ") || null,
        image_url: img ? img.replace(/^http:/, "https:") : null,
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
    }));
  });
