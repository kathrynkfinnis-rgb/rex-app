import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { supabase } from "@/integrations/supabase/client";
import { CATEGORIES, categoryMeta, type ItemType } from "@/lib/categories";
import { RecommendationCard, type FeedRow } from "@/components/RecommendationCard";
import { TRexLogo } from "@/components/TRexLogo";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { UserPlus, Mic, Plus, Search, X, User } from "lucide-react";
import { cn } from "@/lib/utils";
import { searchProfiles } from "@/lib/friends.functions";
import { searchBooks, searchMovies, searchTv, searchPodcasts, type SearchHit } from "@/lib/search.functions";
import { searchPlaces, type PlaceHit } from "@/lib/places.functions";

type SearchScope = "all" | "people" | ItemType;

export const Route = createFileRoute("/_authenticated/feed")({
  head: () => ({
    meta: [
      { title: "Your feed — REX" },
      { name: "description", content: "The latest recommendations from your friends." },
    ],
  }),
  component: FeedPage,
});

function FeedPage() {
  const [filter, setFilter] = useState<ItemType | "all">("all");
  const [subFilter, setSubFilter] = useState<string | "all">("all");
  const [rawQuery, setRawQuery] = useState("");
  const [query, setQuery] = useState("");
  const [searchScope, setSearchScope] = useState<SearchScope>("all");

  // debounce search input
  useEffect(() => {
    const t = setTimeout(() => setQuery(rawQuery.trim()), 250);
    return () => clearTimeout(t);
  }, [rawQuery]);

  // reset subcategory when the top-level category changes
  useEffect(() => {
    setSubFilter("all");
  }, [filter]);

  const searching = query.length >= 2;

  const { data, isLoading } = useQuery({
    queryKey: ["feed", filter],
    queryFn: async () => {
      let q = supabase
        .from("recommendations")
        .select("id, rating, note, created_at, photo_url, user_id, item_id, items!inner(id, type, title, subtitle, image_url, genre), profiles!recommendations_user_id_fkey(username, display_name, avatar_url), creators(slug, name, color, emoji)")
        .order("created_at", { ascending: false })
        .limit(50);
      if (filter !== "all") q = q.eq("items.type", filter);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as unknown as FeedRow[];
    },
  });

  // Build the subcategory list from the current category's rows
  const subcategories = useMemo(() => {
    if (filter === "all" || !data) return [] as string[];
    const set = new Set<string>();
    for (const r of data) {
      const g = r.items?.genre?.trim();
      if (g) set.add(g);
    }
    return Array.from(set).sort((a, b) => a.localeCompare(b));
  }, [data, filter]);

  const visible = useMemo(() => {
    if (!data) return [];
    if (subFilter === "all") return data;
    const s = subFilter.toLowerCase();
    return data.filter((r) => (r.items?.genre ?? "").toLowerCase() === s);
  }, [data, subFilter]);


  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-30 border-b border-border bg-background/90 px-5 pb-3 pt-[calc(env(safe-area-inset-top)+1rem)] backdrop-blur">
        <div className="flex items-center justify-between">
          <div>
            <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-widest text-primary">
              <TRexLogo className="h-4 w-4" /> REX
            </div>
            <h1 className="mt-0.5 font-display text-3xl">{searching ? "Search" : "Your feed"}</h1>
          </div>
        </div>
        <div className="relative mt-3">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={rawQuery}
            onChange={(e) => setRawQuery(e.target.value)}
            placeholder={
              searchScope === "people"
                ? "Search people…"
                : searchScope === "all"
                  ? "Search recs, people, books, films, places…"
                  : `Search ${categoryMeta(searchScope).plural.toLowerCase()}…`
            }
            aria-label="Search"
            className="h-11 rounded-full border-border bg-card pl-9 pr-9"
          />
          {rawQuery && (
            <button
              type="button"
              onClick={() => setRawQuery("")}
              aria-label="Clear search"
              className="absolute right-2 top-1/2 flex h-7 w-7 -translate-y-1/2 items-center justify-center rounded-full text-muted-foreground hover:bg-muted"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
        {searching && (
          <div className="scrollbar-none mt-2 flex gap-2 overflow-x-auto -mx-5 px-5">
            <ScopeChip active={searchScope === "all"} onClick={() => setSearchScope("all")}>All</ScopeChip>
            <ScopeChip active={searchScope === "people"} onClick={() => setSearchScope("people")}>
              <User className="h-3.5 w-3.5" /> People
            </ScopeChip>
            {CATEGORIES.map((c) => (
              <ScopeChip key={c.type} active={searchScope === c.type} onClick={() => setSearchScope(c.type)}>
                <c.icon className="h-3.5 w-3.5" />
                {c.plural}
              </ScopeChip>
            ))}
          </div>
        )}
        {!searching && (
          <div className="scrollbar-none mt-3 flex gap-2 overflow-x-auto -mx-5 px-5">
            <Chip active={filter === "all"} onClick={() => setFilter("all")}>All</Chip>
            {CATEGORIES.map((c) => (
              <Chip key={c.type} active={filter === c.type} onClick={() => setFilter(c.type)}>
                <c.icon className="h-3.5 w-3.5" />
                {c.plural}
              </Chip>
            ))}
          </div>
        )}
        {!searching && filter !== "all" && subcategories.length > 0 && (
          <div className="scrollbar-none mt-2 flex gap-2 overflow-x-auto -mx-5 px-5">
            <SubChip active={subFilter === "all"} onClick={() => setSubFilter("all")}>All {categoryMeta(filter).plural.toLowerCase()}</SubChip>
            {subcategories.map((g) => (
              <SubChip key={g} active={subFilter === g} onClick={() => setSubFilter(g)}>
                {g}
              </SubChip>
            ))}
          </div>
        )}
      </header>

      {searching ? (
        <SearchResults query={query} feed={data ?? []} scope={searchScope} />
      ) : (
        <div className="space-y-3 px-4 py-4">
          {isLoading && (
            <>
              <SkeletonCard />
              <SkeletonCard />
            </>
          )}
          {!isLoading && (data?.length ?? 0) === 0 && <EmptyState />}
          {!isLoading && (data?.length ?? 0) > 0 && visible.length === 0 && (
            <p className="rounded-2xl border border-dashed border-border bg-card p-6 text-center text-sm text-muted-foreground">
              No {subFilter.toLowerCase()} recs in your feed yet.
            </p>
          )}
          {visible.map((rec) => <RecommendationCard key={rec.id} rec={rec} />)}
        </div>
      )}

    </div>
  );
}

function SearchResults({ query, feed }: { query: string; feed: FeedRow[] }) {
  const profilesFn = useServerFn(searchProfiles);
  const booksFn = useServerFn(searchBooks);
  const moviesFn = useServerFn(searchMovies);
  const tvFn = useServerFn(searchTv);
  const placesFn = useServerFn(searchPlaces);
  const podcastsFn = useServerFn(searchPodcasts);

  const feedMatches = useMemo(() => {
    const q = query.toLowerCase();
    return feed.filter((r) => {
      const t = r.items?.title?.toLowerCase() ?? "";
      const s = r.items?.subtitle?.toLowerCase() ?? "";
      const n = r.note?.toLowerCase() ?? "";
      const u = r.profiles?.username?.toLowerCase() ?? "";
      const d = r.profiles?.display_name?.toLowerCase() ?? "";
      const c = r.creators?.name?.toLowerCase() ?? "";
      return t.includes(q) || s.includes(q) || n.includes(q) || u.includes(q) || d.includes(q) || c.includes(q);
    }).slice(0, 10);
  }, [feed, query]);

  const people = useQuery({
    queryKey: ["search-people", query],
    queryFn: () => profilesFn({ data: { query, limit: 10 } }),
    staleTime: 30_000,
  });

  const books = useQuery({
    queryKey: ["search-books", query],
    queryFn: () => booksFn({ data: { q: query } }),
    staleTime: 60_000,
  });
  const movies = useQuery({
    queryKey: ["search-movies", query],
    queryFn: () => moviesFn({ data: { q: query } }),
    staleTime: 60_000,
  });
  const tv = useQuery({
    queryKey: ["search-tv", query],
    queryFn: () => tvFn({ data: { q: query } }),
    staleTime: 60_000,
  });
  const places = useQuery({
    queryKey: ["search-places", query],
    queryFn: () => placesFn({ data: { q: query, near: null } }),
    staleTime: 60_000,
  });
  const podcasts = useQuery({
    queryKey: ["search-podcasts", query],
    queryFn: () => podcastsFn({ data: { q: query } }),
    staleTime: 60_000,
  });

  const catalog: { type: ItemType; hits: (SearchHit | PlaceHit)[] }[] = [
    { type: "book", hits: (books.data ?? []).slice(0, 6) },
    { type: "movie", hits: (movies.data ?? []).slice(0, 6) },
    { type: "tv", hits: (tv.data ?? []).slice(0, 6) },
    { type: "podcast", hits: (podcasts.data ?? []).slice(0, 6) },
    { type: "place", hits: (places.data ?? []).slice(0, 6) },
  ];

  const anyLoading = people.isLoading || books.isLoading || movies.isLoading || tv.isLoading || places.isLoading || podcasts.isLoading;
  const nothing =
    !anyLoading &&
    feedMatches.length === 0 &&
    (people.data?.length ?? 0) === 0 &&
    catalog.every((c) => c.hits.length === 0);

  return (
    <div className="space-y-6 px-4 py-4">
      {feedMatches.length > 0 && (
        <Section title="In your feed">
          <div className="space-y-3">
            {feedMatches.map((rec) => <RecommendationCard key={rec.id} rec={rec} />)}
          </div>
        </Section>
      )}

      {(people.data?.length ?? 0) > 0 && (
        <Section title="People">
          <ul className="space-y-2">
            {people.data!.map((p: any) => (
              <li key={p.id}>
                <Link
                  to="/profile/$username"
                  params={{ username: p.username }}
                  className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border transition-colors hover:bg-muted/60"
                >
                  <div
                    className="flex h-10 w-10 items-center justify-center rounded-full bg-secondary text-sm font-semibold"
                    style={p.avatar_url ? { backgroundImage: `url(${p.avatar_url})`, backgroundSize: "cover", backgroundPosition: "center" } : undefined}
                  >
                    {!p.avatar_url && (p.display_name || p.username || "?").slice(0, 1).toUpperCase()}
                  </div>
                  <div className="min-w-0">
                    <p className="truncate font-medium">{p.display_name || p.username}</p>
                    <p className="truncate text-xs text-muted-foreground">@{p.username}</p>
                  </div>
                </Link>
              </li>
            ))}
          </ul>
        </Section>
      )}

      {catalog.map(({ type, hits }) => hits.length > 0 && (
        <CatalogSection key={type} type={type} hits={hits} />
      ))}

      {anyLoading && (
        <p className="text-center text-sm text-muted-foreground">Searching…</p>
      )}
      {nothing && (
        <div className="mt-6 rounded-2xl border border-dashed border-border bg-card p-6 text-center">
          <p className="font-medium">No results for “{query}”</p>
          <p className="mt-1 text-sm text-muted-foreground">Try a different spelling or add it yourself.</p>
          <Button asChild variant="outline" className="mt-4 h-10 rounded-full">
            <Link to="/add"><Plus className="mr-1.5 h-4 w-4" /> Add a rec</Link>
          </Button>
        </div>
      )}
    </div>
  );
}

function CatalogSection({ type, hits }: { type: ItemType; hits: (SearchHit | PlaceHit)[] }) {
  const meta = categoryMeta(type);
  const Icon = meta.icon;
  return (
    <Section title={
      <span className="flex items-center gap-1.5">
        <Icon className="h-3.5 w-3.5" /> {meta.plural}
      </span>
    }>
      <ul className="space-y-2">
        {hits.map((h) => (
          <li key={`${h.external_source}-${h.external_id}`}>
            <Link
              to="/add"
              className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border transition-colors hover:bg-muted/60"
            >
              <div className="h-12 w-12 shrink-0 overflow-hidden rounded-lg bg-muted">
                {h.image_url && (
                  <img src={h.image_url} alt="" className="h-full w-full object-cover" loading="lazy" />
                )}
              </div>
              <div className="min-w-0 flex-1">
                <p className="truncate font-medium">{h.title}</p>
                {h.subtitle && <p className="truncate text-xs text-muted-foreground">{h.subtitle}</p>}
                {"address" in h && h.address && (
                  <p className="truncate text-xs text-muted-foreground">{h.address}</p>
                )}
              </div>
              <Plus className="h-4 w-4 shrink-0 text-muted-foreground" />
            </Link>
          </li>
        ))}
      </ul>
    </Section>
  );
}

function Section({ title, children }: { title: React.ReactNode; children: React.ReactNode }) {
  return (
    <section>
      <h2 className="mb-2 text-xs font-semibold uppercase tracking-widest text-muted-foreground">{title}</h2>
      {children}
    </section>
  );
}

function Chip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "flex shrink-0 items-center gap-1.5 rounded-full border px-4 py-1.5 text-sm font-medium transition-colors",
        active
          ? "border-primary bg-primary text-primary-foreground"
          : "border-border bg-card text-foreground",
      )}
    >
      {children}
    </button>
  );
}

function SubChip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-medium transition-colors",
        active
          ? "border-primary/50 bg-primary/10 text-primary"
          : "border-border bg-background text-muted-foreground hover:text-foreground",
      )}
    >
      {children}
    </button>
  );
}

function SkeletonCard() {

  return <div className="h-40 animate-pulse rounded-2xl bg-muted" />;
}

function EmptyState() {
  return (
    <div className="mt-8 rounded-3xl border border-dashed border-border bg-card p-6 text-center">
      <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-primary/10">
        <TRexLogo className="h-7 w-7" />
      </div>
      <h2 className="mt-3 font-display text-2xl">Your feed is empty</h2>
      <p className="mx-auto mt-2 max-w-xs text-sm text-muted-foreground">
        Add friends or follow a creator — their picks will land here.
      </p>
      <div className="mt-5 grid gap-2">
        <Button asChild className="h-11 rounded-full">
          <Link to="/friends"><UserPlus className="mr-1.5 h-4 w-4" /> Add friends</Link>
        </Button>
        <Button asChild variant="outline" className="h-11 rounded-full">
          <Link to="/creators"><Mic className="mr-1.5 h-4 w-4" /> Follow creators</Link>
        </Button>
        <Button asChild variant="ghost" className="h-11 rounded-full">
          <Link to="/add"><Plus className="mr-1.5 h-4 w-4" /> Add your first rec</Link>
        </Button>
      </div>
    </div>
  );
}
