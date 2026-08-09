import type { SearchHit } from "@/lib/search.functions";

// Client-side podcast search. Apple blocks Cloudflare Workers' egress IPs, so
// the same iTunes request that works locally returns nothing from the deployed
// server. iTunes does send CORS headers, so calling it from the browser gets us
// the full catalogue (with publisher + genre) without an API key or a proxy.
export async function searchPodcastsClient(q: string): Promise<SearchHit[]> {
  const term = q.trim();
  if (!term) return [];
  const url = `https://itunes.apple.com/search?media=podcast&entity=podcast&limit=15&term=${encodeURIComponent(term)}`;
  const res = await fetch(url);
  if (!res.ok) return [];
  const json: any = await res.json();
  return (json.results ?? []).map((r: any): SearchHit => ({
    external_id: String(r.collectionId ?? r.trackId),
    external_source: "itunes_podcast" as const,
    title: r.collectionName ?? r.trackName ?? "Untitled",
    subtitle: r.artistName ?? null,
    image_url: r.artworkUrl600 ?? r.artworkUrl100 ?? null,
    genre: Array.isArray(r.genres)
      ? r.genres.find((g: string) => g && g !== "Podcasts") ?? r.primaryGenreName ?? null
      : r.primaryGenreName ?? null,
  }));
}

// Client-side book search. Uses OpenLibrary (no key, generous quota, CORS-friendly)
// so we don't hit the shared server-IP quota on Google Books.
export async function searchBooksClient(q: string): Promise<SearchHit[]> {
  const term = q.trim();
  if (!term) return [];
  const url = `https://openlibrary.org/search.json?q=${encodeURIComponent(term)}&limit=15&fields=key,title,author_name,first_publish_year,cover_i,edition_key,subject`;
  const res = await fetch(url);
  if (!res.ok) return [];
  const json: any = await res.json();
  const docs: any[] = json.docs ?? [];
  return docs
    .map((d): SearchHit | null => {
      const key: string | undefined = d.key; // e.g. "/works/OL12345W"
      if (!key) return null;
      const cover = d.cover_i ? `https://covers.openlibrary.org/b/id/${d.cover_i}-M.jpg` : null;
      const authors: string[] = d.author_name ?? [];
      const year = d.first_publish_year ? ` · ${d.first_publish_year}` : "";
      const subjects: string[] = Array.isArray(d.subject) ? d.subject : [];
      // Prefer a short, clean subject as the genre (skip long descriptive tags).
      const genre = subjects.find((s) => typeof s === "string" && s.length <= 22) ?? subjects[0] ?? null;
      return {
        external_id: key.replace(/^\//, ""),
        external_source: "google_books", // reuse existing enum value; treated as generic book id
        title: d.title ?? "Untitled",
        subtitle: authors.length ? authors.join(", ") + year : year.replace(/^ · /, "") || null,
        image_url: cover,
        genre: genre ? String(genre) : null,
      };
    })
    .filter((x): x is SearchHit => !!x);
}
