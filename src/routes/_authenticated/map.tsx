import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { MapPin, Loader2, X, Star } from "lucide-react";
import { useTopFriends } from "@/lib/topFriends";

import { ClientOnly } from "@tanstack/react-router";
import { lazy, Suspense, useEffect, useMemo, useRef, useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { geocodeMissingPlaces } from "@/lib/geocode.functions";
import { CATEGORIES, categoryMeta, type ItemType } from "@/lib/categories";

const GoogleMap = lazy(() => import("@/components/GoogleMap").then((m) => ({ default: m.GoogleMap })));


export const Route = createFileRoute("/_authenticated/map")({
  head: () => ({
    meta: [
      { title: "Map — REX" },
      { name: "description", content: "Places your friends Rex, on a map." },
    ],
  }),
  component: MapPage,
});

function MapPage() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const geocode = useServerFn(geocodeMissingPlaces);
  const [geocoding, setGeocoding] = useState(false);
  const ranAuto = useRef(false);

  const [cat, setCat] = useState<ItemType | "all">("all");
  const [sub, setSub] = useState<string | null>(null);
  const [topOnly, setTopOnly] = useState(false);


  const { data } = useQuery({
    queryKey: ["map-places"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("items")
        .select("id, title, subtitle, type, genre, address, lat, lng, image_url, recommendations(id, rating, note, user_id, profiles(display_name, username, avatar_url))")
        .in("type", ["place", "event"])
        .order("created_at", { ascending: false })
        .limit(200);
      if (error) throw error;
      return data ?? [];
    },
  });

  const all = data ?? [];

  const cats = useMemo(() => {
    const present = new Set(all.map((p: any) => p.type));
    return CATEGORIES.filter((c) => present.has(c.type));
  }, [all]);

  const byCat = useMemo(
    () => (cat === "all" ? all : all.filter((p: any) => p.type === cat)),
    [all, cat],
  );

  const subs = useMemo(() => {
    const set = new Set<string>();
    byCat.forEach((p: any) => p.genre && set.add(p.genre));
    return [...set].sort();
  }, [byCat]);

  const { data: topSet } = useTopFriends();
  const topIds = topSet ?? new Set<string>();

  const filtered = useMemo(() => {
    const base = sub ? byCat.filter((p: any) => p.genre === sub) : byCat;
    if (!topOnly) return base;
    return base.filter((p: any) =>
      (p.recommendations ?? []).some((r: any) => topIds.has(r.user_id)),
    );
  }, [byCat, sub, topOnly, topSet]);


  const withLoc = filtered.filter((p: any) => p.lat != null && p.lng != null);
  const withoutLoc = filtered.filter((p: any) => p.lat == null || p.lng == null);
  const allWithoutLoc = all.filter((p: any) => p.lat == null || p.lng == null);


  const runGeocode = async () => {
    if (geocoding) return;
    setGeocoding(true);
    try {
      // Keep going in passes so a whole imported list resolves in one go.
      for (let pass = 0; pass < 8; pass++) {
        const res: any = await geocode({ data: { limit: 25 } });
        await qc.invalidateQueries({ queryKey: ["map-places"] });
        if (!res || res.reason === "no_key") break;
        if (!res.remaining || res.updated === 0) break;
      }
    } finally {
      setGeocoding(false);
    }
  };

  // Auto-locate any place/event missing coordinates every time Places opens.
  useEffect(() => {
    if (ranAuto.current) return;
    if (!data) return;
    if (allWithoutLoc.length === 0) return;
    ranAuto.current = true;
    runGeocode();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data]);

  const chip = (active: boolean) =>
    `shrink-0 rounded-full px-3 py-1.5 text-xs font-medium ring-1 transition ${
      active
        ? "bg-primary text-primary-foreground ring-primary"
        : "bg-card text-muted-foreground ring-border"
    }`;

  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h1 className="font-display text-3xl">Places</h1>
            <p className="mt-1 text-sm text-muted-foreground">Restaurants and spots your friends Rex.</p>
          </div>
          {allWithoutLoc.length > 0 && (
            <button
              onClick={runGeocode}
              disabled={geocoding}
              className="mt-1 inline-flex items-center gap-1.5 rounded-full bg-primary/10 px-3 py-1.5 text-xs font-medium text-primary disabled:opacity-60"
            >
              {geocoding ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <MapPin className="h-3.5 w-3.5" />}
              {geocoding ? "Locating…" : `Locate ${allWithoutLoc.length}`}
            </button>
          )}
        </div>

        {cats.length > 1 && (
          <div className="-mx-5 mt-3 flex gap-2 overflow-x-auto px-5 pb-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            <button className={chip(cat === "all")} onClick={() => { setCat("all"); setSub(null); }}>
              All
            </button>
            {cats.map((c) => (
              <button
                key={c.type}
                className={chip(cat === c.type)}
                onClick={() => { setCat(c.type); setSub(null); }}
              >
                {c.label}
              </button>
            ))}
          </div>
        )}

        {topIds.size > 0 && (
          <div className="mt-2">
            <button
              className={`${chip(topOnly)} inline-flex items-center gap-1.5`}
              onClick={() => setTopOnly((v) => !v)}
            >
              <Star className={topOnly ? "h-3.5 w-3.5 fill-current" : "h-3.5 w-3.5"} />
              Top friends only
            </button>
          </div>
        )}

        {subs.length > 0 && (
          <div className="-mx-5 mt-2 flex gap-2 overflow-x-auto px-5 pb-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            {subs.map((s) => (
              <button
                key={s}
                className={chip(sub === s)}
                onClick={() => setSub(sub === s ? null : s)}
              >
                {s}
              </button>
            ))}
            {sub && (
              <button className={chip(false)} onClick={() => setSub(null)}>
                <X className="h-3 w-3" />
              </button>
            )}
          </div>
        )}
      </header>


      <div className="relative m-4 h-72 overflow-hidden rounded-2xl bg-muted ring-1 ring-border">
        <ClientOnly fallback={<div className="h-full w-full animate-pulse bg-muted" />}>
          <Suspense fallback={<div className="h-full w-full animate-pulse bg-muted" />}>
            <GoogleMap
              key={`${cat}-${sub ?? ""}-${topOnly ? "top" : "all"}`}
              radiusMiles={10}
              places={withLoc.map((p: any) => {
                const recs = [...((p.recommendations ?? []) as any[])].sort(
                  (a, b) => (b.rating ?? 0) - (a.rating ?? 0),
                );
                // A top friend's Rex owns the pin when they've recommended this spot.
                const top = recs.find((r: any) => topIds.has(r.user_id)) ?? recs[0];
                return {
                  id: p.id,
                  title: p.title,
                  lat: Number(p.lat),
                  lng: Number(p.lng),
                  subtitle: p.subtitle ?? p.genre ?? null,
                  avatarUrl: top?.profiles?.avatar_url ?? null,
                  byName: top?.profiles?.display_name ?? top?.profiles?.username ?? null,
                  rating: top?.rating ?? null,
                  note: top?.note ?? null,
                };
              })}


              onSelect={(id) => navigate({ to: "/item/$id", params: { id } })}
            />
          </Suspense>
        </ClientOnly>
        {withLoc.length === 0 && (
          <div className="pointer-events-none absolute inset-x-3 bottom-3 rounded-xl bg-background/90 px-3 py-2 text-center text-xs text-muted-foreground backdrop-blur">
            {cat !== "all" || sub
              ? "No pins match this filter yet."
              : "No place Rex with a location yet — they'll appear here."}
          </div>
        )}
      </div>

      <div className="space-y-2 px-4 pb-4">
        {[...withLoc, ...withoutLoc].length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border bg-card p-6 text-center">
            <p className="text-sm text-muted-foreground">
              {cat !== "all" || sub ? "Nothing here for this filter." : "No places yet. Add one from the plus button."}
            </p>
          </div>
        ) : (
          [...withLoc, ...withoutLoc].map((p: any) => {
            const meta = categoryMeta((p.type ?? "place") as ItemType);
            const Icon = meta.icon;
            return (
            <Link
              key={p.id}
              to="/item/$id"
              params={{ id: p.id }}
              className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border"
            >
              <div className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-xl ${meta.tokenClass}`}>
                <Icon className="h-5 w-5" />
              </div>

              <div className="min-w-0 flex-1">
                <p className="truncate font-semibold">{p.title}</p>
                <p className="truncate text-xs text-muted-foreground">
                  {p.address || p.subtitle || "No location set"}
                </p>
              </div>
              <span className="text-xs font-medium text-muted-foreground">
                {p.recommendations?.length ?? 0} rec{(p.recommendations?.length ?? 0) === 1 ? "" : "s"}
              </span>
            </Link>
            );
          })

        )}
      </div>
    </div>
  );
}
