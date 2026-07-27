import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { MapPin, Compass } from "lucide-react";
import { ClientOnly } from "@tanstack/react-router";
import { lazy, Suspense } from "react";

const GoogleMap = lazy(() => import("@/components/GoogleMap").then((m) => ({ default: m.GoogleMap })));

export const Route = createFileRoute("/_authenticated/map")({
  head: () => ({
    meta: [
      { title: "Map — REX" },
      { name: "description", content: "Places your friends recommend, on a map." },
    ],
  }),
  component: MapPage,
});

function MapPage() {
  const navigate = useNavigate();
  const { data } = useQuery({
    queryKey: ["map-places"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("items")
        .select("id, title, subtitle, address, lat, lng, image_url, recommendations(id, rating, user_id, profiles(display_name, username))")
        .eq("type", "place")
        .order("created_at", { ascending: false })
        .limit(100);
      if (error) throw error;
      return data ?? [];
    },
  });

  const withLoc = (data ?? []).filter((p: any) => p.lat != null && p.lng != null);
  const withoutLoc = (data ?? []).filter((p: any) => p.lat == null || p.lng == null);

  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <h1 className="font-display text-3xl">Places</h1>
        <p className="mt-1 text-sm text-muted-foreground">Restaurants and spots your friends recommend.</p>
      </header>

      <div className="relative m-4 h-72 overflow-hidden rounded-2xl bg-muted ring-1 ring-border">
        {withLoc.length === 0 ? (
          <div className="flex h-full flex-col items-center justify-center gap-2 text-center px-6">
            <Compass className="h-8 w-8 text-primary" />
            <p className="max-w-xs text-sm text-muted-foreground">
              A map view lights up here once you add place recommendations with a location.
            </p>
          </div>
        ) : (
          <ClientOnly fallback={<div className="h-full w-full animate-pulse bg-muted" />}>
            {() => (
              <Suspense fallback={<div className="h-full w-full animate-pulse bg-muted" />}>
                <GoogleMap
                  places={withLoc.map((p: any) => ({ id: p.id, title: p.title, lat: Number(p.lat), lng: Number(p.lng) }))}
                  onSelect={(id) => navigate({ to: "/item/$id", params: { id } })}
                />
              </Suspense>
            )}
          </ClientOnly>
        )}
      </div>

      <div className="space-y-2 px-4 pb-4">
        {[...withLoc, ...withoutLoc].length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border bg-card p-6 text-center">
            <p className="text-sm text-muted-foreground">No places yet. Add one from the plus button.</p>
          </div>
        ) : (
          [...withLoc, ...withoutLoc].map((p: any) => (
            <Link
              key={p.id}
              to="/item/$id"
              params={{ id: p.id }}
              className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border"
            >
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-cat-place/15 text-cat-place">
                <MapPin className="h-5 w-5" />
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
          ))
        )}
      </div>
    </div>
  );
}
