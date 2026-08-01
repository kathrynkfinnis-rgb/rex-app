import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Input } from "@/components/ui/input";
import { Search, Luggage, MapPin, Loader2, X } from "lucide-react";
import { categoryMeta, type ItemType } from "@/lib/categories";

export const Route = createFileRoute("/_authenticated/trips")({
  head: () => ({
    meta: [
      { title: "Find a trip — REX" },
      { name: "description", content: "Search trips your friends have Rexed and open their stops on the map." },
      { property: "og:title", content: "Find a trip — REX" },
      { property: "og:description", content: "Search trips your friends have Rexed and open their stops on the map." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: TripsPage,
});

type TripRow = {
  id: string;
  created_at: string;
  note: string | null;
  tags: string[] | null;
  items: { title: string; subtitle: string | null; image_url: string | null } | null;
  profiles: { username: string; display_name: string | null; avatar_url: string | null } | null;
};

function TripsPage() {
  const navigate = useNavigate();
  const [q, setQ] = useState("");
  const [tag, setTag] = useState<string | null>(null);
  const [stopType, setStopType] = useState<ItemType | null>(null);

  const { data: trips, isLoading } = useQuery({
    queryKey: ["all-trips"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("recommendations")
        .select(
          "id, created_at, note, tags, items!inner(title, subtitle, image_url, type), profiles!recommendations_user_id_fkey(username, display_name, avatar_url)",
        )
        .eq("items.type", "trip")
        .order("created_at", { ascending: false })
        .limit(300);
      if (error) throw error;
      return (data ?? []) as unknown as TripRow[];
    },
  });

  const ids = useMemo(() => (trips ?? []).map((t) => t.id), [trips]);

  // Stops power both the "n stops" line and the type filters.
  const { data: stops } = useQuery({
    enabled: ids.length > 0,
    queryKey: ["all-trip-stops", ids.join(",")],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("recommendations")
        .select("trip_id, items!inner(type, title)")
        .in("trip_id", ids);
      if (error) throw error;
      return (data ?? []) as any[];
    },
  });

  const stopsByTrip = useMemo(() => {
    const map = new Map<string, { types: Set<ItemType>; titles: string[]; count: number }>();
    for (const s of stops ?? []) {
      const key = s.trip_id as string;
      const entry = map.get(key) ?? { types: new Set<ItemType>(), titles: [], count: 0 };
      entry.types.add(s.items?.type as ItemType);
      if (s.items?.title) entry.titles.push(s.items.title as string);
      entry.count += 1;
      map.set(key, entry);
    }
    return map;
  }, [stops]);

  const allTags = useMemo(() => {
    const set = new Set<string>();
    (trips ?? []).forEach((t) => (t.tags ?? []).forEach((x) => set.add(x)));
    return [...set].sort();
  }, [trips]);

  const allStopTypes = useMemo(() => {
    const set = new Set<ItemType>();
    stopsByTrip.forEach((v) => v.types.forEach((t) => set.add(t)));
    return [...set];
  }, [stopsByTrip]);

  const results = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return (trips ?? []).filter((t) => {
      const info = stopsByTrip.get(t.id);
      if (tag && !(t.tags ?? []).includes(tag)) return false;
      if (stopType && !info?.types.has(stopType)) return false;
      if (!needle) return true;
      const hay = [
        t.items?.title,
        t.items?.subtitle,
        t.note,
        t.profiles?.display_name,
        t.profiles?.username,
        ...(t.tags ?? []),
        ...(info?.titles ?? []),
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return hay.includes(needle);
    });
  }, [trips, stopsByTrip, q, tag, stopType]);

  const chip = (active: boolean) =>
    `shrink-0 rounded-full px-3 py-1.5 text-xs font-medium ring-1 transition ${
      active ? "bg-primary text-primary-foreground ring-primary" : "bg-card text-muted-foreground ring-border"
    }`;

  return (
    <div className="pb-24">
      <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <div className="flex items-center gap-2">
          <Luggage className="h-5 w-5 text-primary" />
          <h1 className="font-display text-3xl">Find a trip</h1>
        </div>
        <p className="mt-1 text-sm text-muted-foreground">
          Search trips, then open all their stops on the map.
        </p>

        <div className="relative mt-3">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search trips, cities, stops or people"
            className="h-12 rounded-xl pl-9"
            aria-label="Search trips"
          />
        </div>

        {allStopTypes.length > 0 && (
          <div className="-mx-5 mt-3 flex gap-2 overflow-x-auto px-5 pb-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            <span className="flex shrink-0 items-center pr-0.5 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
              Includes
            </span>
            {allStopTypes.map((t) => (
              <button
                key={t}
                className={chip(stopType === t)}
                onClick={() => setStopType(stopType === t ? null : t)}
              >
                {categoryMeta(t).label}
              </button>
            ))}
          </div>
        )}

        {allTags.length > 0 && (
          <div className="-mx-5 mt-2 flex gap-2 overflow-x-auto px-5 pb-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            <span className="flex shrink-0 items-center pr-0.5 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
              Tags
            </span>
            {allTags.map((t) => (
              <button key={t} className={chip(tag === t)} onClick={() => setTag(tag === t ? null : t)}>
                #{t}
              </button>
            ))}
          </div>
        )}

        {(tag || stopType || q) && (
          <button
            className="mt-2 inline-flex items-center gap-1 text-xs font-medium text-muted-foreground underline"
            onClick={() => {
              setTag(null);
              setStopType(null);
              setQ("");
            }}
          >
            <X className="h-3 w-3" /> Clear filters
          </button>
        )}
      </header>

      <div className="space-y-3 px-5 py-4">
        {isLoading && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Loading trips…
          </div>
        )}

        {!isLoading && results.length === 0 && (
          <p className="rounded-2xl bg-card p-6 text-center text-sm text-muted-foreground ring-1 ring-border">
            No trips match that yet.
          </p>
        )}

        {results.map((t) => {
          const info = stopsByTrip.get(t.id);
          const who = t.profiles?.display_name || t.profiles?.username || "Someone";
          return (
            <div key={t.id} className="rounded-2xl bg-card p-4 ring-1 ring-border">
              <div className="flex items-start gap-3">
                {t.items?.image_url && (
                  <img
                    src={t.items.image_url}
                    alt={t.items?.title ?? "Trip"}
                    loading="lazy"
                    className="h-14 w-14 shrink-0 rounded-xl object-cover"
                  />
                )}
                <div className="min-w-0 flex-1">
                  <p className="truncate font-display text-lg">{t.items?.title}</p>
                  {t.items?.subtitle && (
                    <p className="truncate text-sm text-muted-foreground">{t.items.subtitle}</p>
                  )}
                  <p className="mt-0.5 text-xs text-muted-foreground">
                    {who} · {info?.count ?? 0} stop{(info?.count ?? 0) === 1 ? "" : "s"}
                  </p>
                  {(t.tags?.length ?? 0) > 0 && (
                    <div className="mt-1.5 flex flex-wrap gap-1">
                      {t.tags!.map((x) => (
                        <span key={x} className="rounded-full bg-muted px-2 py-0.5 text-[11px] text-muted-foreground">
                          #{x}
                        </span>
                      ))}
                    </div>
                  )}
                </div>
              </div>

              <div className="mt-3 flex gap-2">
                <button
                  onClick={() => navigate({ to: "/map", search: { trip: t.id } })}
                  className="inline-flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-primary px-3 py-2 text-sm font-medium text-primary-foreground"
                >
                  <MapPin className="h-4 w-4" /> Show on map
                </button>
                <Link
                  to="/trip/$id"
                  params={{ id: t.id }}
                  className="inline-flex flex-1 items-center justify-center rounded-xl bg-background px-3 py-2 text-sm font-medium ring-1 ring-border"
                >
                  Open trip
                </Link>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
