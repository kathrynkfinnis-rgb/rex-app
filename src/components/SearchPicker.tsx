import { useEffect, useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { Input } from "@/components/ui/input";
import { Search, Loader2, Pencil, MapPin, Ticket } from "lucide-react";
import { searchMovies, searchTv, searchPodcasts, type SearchHit } from "@/lib/search.functions";
import { searchBooksClient } from "@/lib/search-client";
import { searchPlaces, type PlaceHit } from "@/lib/places.functions";
import { searchEvents, type EventHit } from "@/lib/events.functions";
import type { ItemType } from "@/lib/categories";

export type AnyHit = SearchHit | PlaceHit | EventHit;

type Props = {
  type: ItemType;
  onPick: (hit: AnyHit) => void;
  onManual: () => void;
  near?: { lat: number; lng: number } | null;
};

export function SearchPicker({ type, onPick, onManual, near }: Props) {
  const [q, setQ] = useState("");
  const [results, setResults] = useState<AnyHit[]>([]);
  const [loading, setLoading] = useState(false);
  const movieFn = useServerFn(searchMovies);
  const tvFn = useServerFn(searchTv);
  const placesFn = useServerFn(searchPlaces);
  const podcastFn = useServerFn(searchPodcasts);

  useEffect(() => {
    const term = q.trim();
    if (term.length < 2) {
      setResults([]);
      return;
    }
    setLoading(true);
    const t = setTimeout(async () => {
      try {
        const hits: AnyHit[] =
          type === "book"
            ? await searchBooksClient(term)
            : type === "movie"
              ? await movieFn({ data: { q: term } })
              : type === "tv"
                ? await tvFn({ data: { q: term } })
                : type === "podcast"
                  ? await podcastFn({ data: { q: term } })
                  : await placesFn({ data: { q: term, near: near ?? null } });
        setResults(hits);
      } catch {
        setResults([]);
      } finally {
        setLoading(false);
      }
    }, 300);
    return () => clearTimeout(t);
  }, [q, type, movieFn, tvFn, placesFn, podcastFn, near?.lat, near?.lng]);

  const placeholder =
    type === "book"
      ? "Search books (title or author)…"
      : type === "movie"
        ? "Search movies…"
        : type === "tv"
          ? "Search TV shows…"
          : type === "podcast"
            ? "Search podcasts…"
            : "Search restaurants, cafés, places…";

  const isPlace = type === "place";

  return (
    <div className="space-y-3">
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          autoFocus
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={placeholder}
          className="h-12 rounded-xl pl-10"
        />
        {loading && (
          <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-muted-foreground" />
        )}
      </div>

      {results.length > 0 && (
        <ul className="divide-y divide-border overflow-hidden rounded-2xl bg-card ring-1 ring-border">
          {results.map((r) => (
            <li key={`${r.external_source}-${r.external_id}`}>
              <button
                type="button"
                onClick={() => onPick(r)}
                className="flex w-full items-center gap-3 p-3 text-left transition-colors hover:bg-muted/40 active:bg-muted"
              >
                {isPlace ? (
                  <div className="flex h-14 w-10 flex-none items-center justify-center rounded-md bg-secondary text-secondary-foreground ring-1 ring-border">
                    <MapPin className="h-5 w-5" />
                  </div>
                ) : r.image_url ? (
                  <img
                    src={r.image_url}
                    alt=""
                    className="h-14 w-10 flex-none rounded-md object-cover ring-1 ring-border"
                  />
                ) : (
                  <div className="h-14 w-10 flex-none rounded-md bg-muted" />
                )}
                <div className="min-w-0 flex-1">
                  <div className="truncate font-medium">{r.title}</div>
                  {r.subtitle && (
                    <div className="truncate text-sm text-muted-foreground">{r.subtitle}</div>
                  )}
                </div>
              </button>
            </li>
          ))}
        </ul>
      )}

      {q.trim().length >= 2 && !loading && results.length === 0 && (
        <div className="rounded-xl bg-muted/40 p-4 text-center text-sm text-muted-foreground">
          No matches. You can add it manually below.
        </div>
      )}

      <button
        type="button"
        onClick={onManual}
        className="flex w-full items-center justify-center gap-2 rounded-xl border border-dashed border-border py-3 text-sm text-muted-foreground transition-colors hover:bg-muted/40"
      >
        <Pencil className="h-4 w-4" /> Enter details manually
      </button>
    </div>
  );
}
