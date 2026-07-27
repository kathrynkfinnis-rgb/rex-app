import type { SearchHit } from "@/lib/search.functions";

// Client-side book search. Uses OpenLibrary (no key, generous quota, CORS-friendly)
// so we don't hit the shared server-IP quota on Google Books.
export async function searchBooksClient(q: string): Promise<SearchHit[]> {
  const term = q.trim();
  if (!term) return [];
  const url = `https://openlibrary.org/search.json?q=${encodeURIComponent(term)}&limit=15&fields=key,title,author_name,first_publish_year,cover_i,edition_key`;
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
      return {
        external_id: key.replace(/^\//, ""),
        external_source: "google_books", // reuse existing enum value; treated as generic book id
        title: d.title ?? "Untitled",
        subtitle: authors.length ? authors.join(", ") + year : year.replace(/^ · /, "") || null,
        image_url: cover,
      };
    })
    .filter((x): x is SearchHit => !!x);
}
