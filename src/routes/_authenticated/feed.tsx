import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { supabase } from "@/integrations/supabase/client";
import { CATEGORIES, categoryMeta, splitGenres, hasGenre, type ItemType } from "@/lib/categories";
import { RecommendationCard, type FeedRow } from "@/components/RecommendationCard";

import { RequestCard, type RequestRow } from "@/components/RequestCard";
import rexLogo from "@/assets/rex-wordmark.png.asset.json";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { UserPlus, Mic, Plus, Search, X, User, Sparkles, ListChecks as ListIcon, Lock, Users as UsersIcon, Globe2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { searchProfiles } from "@/lib/friends.functions";

type SearchScope = "all" | "people" | "lists" | ItemType;

export const Route = createFileRoute("/_authenticated/feed")({
  head: () => ({
    meta: [
      { title: "Your feed — REX" },
      { name: "description", content: "The latest Rex from your friends." },
    ],
  }),
  component: FeedPage,
});

function FeedPage() {
  const qc = useQueryClient();
  const [filter, setFilter] = useState<ItemType | "all" | "asks">("all");
  const [subFilter, setSubFilter] = useState<string | "all">("all");
  const [rawQuery, setRawQuery] = useState("");
  const [query, setQuery] = useState("");
  const [searchScope, setSearchScope] = useState<SearchScope>("all");
  const [showFilters, setShowFilters] = useState(false);

  // Live updates: refetch the feed and asks whenever anything changes.
  useEffect(() => {
    const channel = supabase
      .channel("feed-live")
      .on("postgres_changes", { event: "*", schema: "public", table: "recommendations" }, () => {
        qc.invalidateQueries({ queryKey: ["feed"] });
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "requests" }, () => {
        qc.invalidateQueries({ queryKey: ["feed-requests"] });
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "recommendation_likes" }, () => {
        qc.invalidateQueries({ queryKey: ["likes-comments"] });
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "recommendation_comments" }, () => {
        qc.invalidateQueries({ queryKey: ["likes-comments"] });
      })
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [qc]);


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
        .select("id, rating, note, created_at, photo_url, photo_urls, tags, user_id, item_id, trip_id, items!inner(id, type, title, subtitle, image_url, genre), profiles!recommendations_user_id_fkey(username, display_name, avatar_url), creators(slug, name, color, emoji)")
        .is("trip_id", null)
        .order("created_at", { ascending: false })
        .limit(50);
      if (filter !== "all" && filter !== "asks") q = q.eq("items.type", filter);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as unknown as FeedRow[];
    },
  });

  const { data: requests } = useQuery({
    queryKey: ["feed-requests", filter],
    queryFn: async () => {
      let q = supabase
        .from("requests")
        .select("id, user_id, type, title, note, created_at, profiles!requests_user_id_profiles_fkey(username, display_name, avatar_url)")
        .order("created_at", { ascending: false })
        .limit(30);
      if (filter !== "all" && filter !== "asks") q = q.eq("type", filter);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as unknown as RequestRow[];
    },
  });

  // Build the subcategory list from the current category's rows
  const subcategories = useMemo(() => {
    if (filter === "all" || filter === "asks" || !data) return [] as string[];
    const set = new Set<string>();
    for (const r of data) {
      for (const g of splitGenres(r.items?.genre)) set.add(g);
    }
    return Array.from(set).sort((a, b) => a.localeCompare(b));
  }, [data, filter]);

  type FeedEntry = { kind: "rec"; row: FeedRow; created_at: string } | { kind: "req"; row: RequestRow; created_at: string };
  const visible = useMemo<FeedEntry[]>(() => {
    if (filter === "asks") {
      return (requests ?? []).map((r) => ({ kind: "req" as const, row: r, created_at: r.created_at }));
    }
    const recs = (data ?? [])
      .filter((r) => subFilter === "all" || hasGenre(r.items?.genre, subFilter))
      .map((r) => ({ kind: "rec" as const, row: r, created_at: r.created_at }));
    const reqs = subFilter === "all"
      ? (requests ?? []).map((r) => ({ kind: "req" as const, row: r, created_at: r.created_at }))
      : [];
    return [...recs, ...reqs].sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
  }, [data, requests, filter, subFilter]);


  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-30 border-b border-border bg-background/90 px-5 pb-3 pt-[calc(env(safe-area-inset-top)+1rem)] backdrop-blur">
        <div className="flex items-center justify-between">
          <div>
            <img src={rexLogo.url} alt="REX" className="h-12 w-auto object-contain" />
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
                : searchScope === "lists"
                  ? "Search collections…"
                  : searchScope === "all"
                    ? "Search Rex, people, collections, books, films, places…"
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
            <ScopeChip active={searchScope === "lists"} onClick={() => setSearchScope("lists")}>
              <ListIcon className="h-3.5 w-3.5" /> Collections
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
          <div className="mt-3">
            <button
              type="button"
              onClick={() => setShowFilters((s) => !s)}
              aria-expanded={showFilters}
              aria-controls="feed-filters"
              className={cn(
                "flex w-full items-center justify-between rounded-2xl border px-4 py-3 text-sm font-medium transition-colors",
                showFilters
                  ? "border-primary bg-primary text-primary-foreground"
                  : "border-border bg-card text-foreground hover:bg-muted/40",
              )}
            >
              <span className="flex items-center gap-2">
                <ListIcon className="h-4 w-4" />
                {filter === "all"
                  ? "Filters"
                  : filter === "asks"
                    ? `Filters: Asks${subFilter !== "all" ? ` · ${subFilter}` : ""}`
                    : `Filters: ${categoryMeta(filter).plural}${subFilter !== "all" ? ` · ${subFilter}` : ""}`}
              </span>
              <span className="text-xs opacity-80">{showFilters ? "Hide" : "Show"}</span>
            </button>

            {showFilters && (
              <div id="feed-filters" className="mt-2 space-y-3 rounded-2xl border border-border bg-card p-3">
                <div className="space-y-1.5">
                  <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Category</p>
                  <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                    <StackedChip active={filter === "all"} onClick={() => { setFilter("all"); setSubFilter("all"); }}>All</StackedChip>
                    <StackedChip active={filter === "asks"} onClick={() => { setFilter("asks"); setSubFilter("all"); }}>
                      <Sparkles className="h-3.5 w-3.5" /> Asks
                    </StackedChip>
                    {CATEGORIES.map((c) => (
                      <StackedChip key={c.type} active={filter === c.type} onClick={() => { setFilter(c.type); setSubFilter("all"); }}>
                        <c.icon className="h-3.5 w-3.5" />
                        {c.plural}
                      </StackedChip>
                    ))}
                  </div>
                </div>

                {filter !== "all" && filter !== "asks" && subcategories.length > 0 && (
                  <div className="space-y-1.5 border-t border-border pt-3">
                    <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Subcategory</p>
                    <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                      <StackedChip active={subFilter === "all"} onClick={() => setSubFilter("all")}>
                        All {categoryMeta(filter).plural.toLowerCase()}
                      </StackedChip>
                      {subcategories.map((g) => (
                        <StackedChip key={g} active={subFilter === g} onClick={() => setSubFilter(g)}>
                          {g}
                        </StackedChip>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        )}
      </header>

      {searching ? (
        <SearchResults query={query} feed={data ?? []} scope={searchScope} />
      ) : (
        <div className="space-y-2 px-3 py-3">
          <Link
            to="/ask"
            className="flex items-center gap-3 rounded-2xl bg-gradient-to-br from-accent/15 to-card p-3 ring-1 ring-accent/40 transition-transform active:scale-[0.99]"
          >
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-accent/20 text-accent-foreground">
              <Sparkles className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="font-medium">Ask friends for a Rex</p>
              <p className="truncate text-xs text-muted-foreground">Put out a blast — friends can chime in.</p>
            </div>
            <Plus className="h-4 w-4 text-muted-foreground" />
          </Link>

          {isLoading && (
            <>
              <SkeletonCard />
              <SkeletonCard />
            </>
          )}
          {!isLoading && visible.length === 0 && filter !== "asks" && <EmptyState />}
          {!isLoading && visible.length === 0 && filter === "asks" && (
            <p className="rounded-2xl border border-dashed border-border bg-card p-6 text-center text-sm text-muted-foreground">
              No asks yet — be the first to ask your friends.
            </p>
          )}
          {visible.map((entry) =>
            entry.kind === "rec"
              ? <RecommendationCard key={`r-${entry.row.id}`} rec={entry.row} />
              : <RequestCard key={`q-${entry.row.id}`} req={entry.row} />,
          )}
        </div>
      )}

    </div>
  );
}

function SearchResults({ query, feed, scope }: { query: string; feed: FeedRow[]; scope: SearchScope }) {
  const profilesFn = useServerFn(searchProfiles);

  const searchPeople = scope === "all" || scope === "people";
  const searchRex = scope !== "people" && scope !== "lists";
  const searchLists = scope === "all" || scope === "lists";

  const feedMatches = useMemo(() => {
    if (!searchRex) return [];
    const q = query.toLowerCase();
    return feed.filter((r) => {
      if (scope !== "all" && r.items?.type !== scope) return false;
      const t = r.items?.title?.toLowerCase() ?? "";
      const s = r.items?.subtitle?.toLowerCase() ?? "";
      const n = r.note?.toLowerCase() ?? "";
      const u = r.profiles?.username?.toLowerCase() ?? "";
      const d = r.profiles?.display_name?.toLowerCase() ?? "";
      const c = r.creators?.name?.toLowerCase() ?? "";
      return t.includes(q) || s.includes(q) || n.includes(q) || u.includes(q) || d.includes(q) || c.includes(q);
    });
  }, [feed, query, scope, searchRex]);

  // Search all Rex you're allowed to see (not just what's already loaded in the feed).
  const rex = useQuery({
    queryKey: ["search-rex", query, scope],
    enabled: searchRex,
    staleTime: 30_000,
    queryFn: async () => {
      let q = supabase
        .from("recommendations")
        .select("id, rating, note, created_at, photo_url, photo_urls, tags, user_id, item_id, items!inner(id, type, title, subtitle, image_url, genre), profiles!recommendations_user_id_fkey(username, display_name, avatar_url), creators(slug, name, color, emoji)")
        .or(`title.ilike.%${query}%,subtitle.ilike.%${query}%`, { referencedTable: "items" })
        .order("created_at", { ascending: false })
        .limit(30);
      if (scope !== "all") q = q.eq("items.type", scope as ItemType);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as unknown as FeedRow[];
    },
  });

  const allRex = useMemo(() => {
    const seen = new Set<string>();
    const out: FeedRow[] = [];
    for (const r of [...feedMatches, ...(rex.data ?? [])]) {
      if (seen.has(r.id)) continue;
      seen.add(r.id);
      out.push(r);
    }
    return out.slice(0, 30);
  }, [feedMatches, rex.data]);

  const lists = useQuery({
    queryKey: ["search-lists", query],
    enabled: searchLists,
    staleTime: 30_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("hitlist_lists")
        .select("id, user_id, name, emoji, item_type, visibility")
        .ilike("name", `%${query}%`)
        .order("created_at", { ascending: false })
        .limit(12);
      if (error) throw error;
      const rows = (data ?? []) as any[];
      const ownerIds = [...new Set(rows.map((r) => r.user_id))];
      const owners = new Map<string, any>();
      if (ownerIds.length > 0) {
        const { data: profs } = await supabase
          .from("profiles")
          .select("id, username, display_name")
          .in("id", ownerIds);
        for (const p of (profs ?? []) as any[]) owners.set(p.id, p);
      }
      return rows.map((r) => ({ ...r, profiles: owners.get(r.user_id) ?? null }));
    },
  });

  const people = useQuery({
    queryKey: ["search-people", query],
    queryFn: () => profilesFn({ data: { query, limit: 10 } }),
    staleTime: 30_000,
    enabled: searchPeople,
  });

  const anyLoading =
    (searchPeople && people.isLoading) ||
    (searchLists && lists.isLoading) ||
    (searchRex && rex.isLoading);
  const nothing =
    !anyLoading &&
    allRex.length === 0 &&
    (people.data?.length ?? 0) === 0 &&
    (lists.data?.length ?? 0) === 0;

  return (
    <div className="space-y-6 px-4 py-4">
      {allRex.length > 0 && (
        <Section title="Rex">
          <div className="space-y-3">
            {allRex.map((rec) => <RecommendationCard key={rec.id} rec={rec} />)}
          </div>
        </Section>
      )}

      {(lists.data?.length ?? 0) > 0 && (
        <Section title={<span className="flex items-center gap-1.5"><ListIcon className="h-3.5 w-3.5" /> Collections</span>}>
          <ul className="space-y-2">
            {lists.data!.map((l: any) => {
              const VIcon = l.visibility === "public" ? Globe2 : l.visibility === "friends" ? UsersIcon : Lock;
              return (
                <li key={l.id}>
                  <Link
                    to="/list/$id"
                    params={{ id: l.id }}
                    className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border transition-colors hover:bg-muted/60"
                  >
                    <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-secondary text-lg">
                      {l.emoji || "📋"}
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="truncate font-medium">{l.name}</p>
                      <p className="truncate text-xs text-muted-foreground">
                        Collection{l.profiles?.username ? ` · @${l.profiles.username}` : ""}
                      </p>
                    </div>
                    <VIcon className="h-4 w-4 shrink-0 text-muted-foreground" />
                  </Link>
                </li>
              );
            })}
          </ul>
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

      {anyLoading && (
        <p className="text-center text-sm text-muted-foreground">Searching…</p>
      )}
      {nothing && (
        <div className="mt-6 rounded-2xl border border-dashed border-border bg-card p-6 text-center">
          <p className="font-medium">No Rex for “{query}”</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Nobody you follow has Rexed this yet — add it yourself.
          </p>
          <Button asChild variant="outline" className="mt-4 h-10 rounded-full">
            <Link to="/add"><Plus className="mr-1.5 h-4 w-4" /> Add a Rex</Link>
          </Button>
        </div>
      )}
    </div>
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

function ScopeChip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition-colors",
        active
          ? "border-primary bg-primary text-primary-foreground"
          : "border-border bg-card text-foreground hover:bg-muted/40",
      )}
    >
      {children}
    </button>
  );
}

function StackedChip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "flex items-center justify-center gap-1.5 rounded-xl border px-3 py-2.5 text-sm font-medium transition-colors text-center",
        active
          ? "border-primary bg-primary text-primary-foreground"
          : "border-border bg-background text-foreground hover:bg-muted/40",
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
        <img src={rexLogo.url} alt="REX" className="h-7 w-auto object-contain" />
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
          <Link to="/add"><Plus className="mr-1.5 h-4 w-4" /> Add your first Rex</Link>
        </Button>
      </div>
    </div>
  );
}
