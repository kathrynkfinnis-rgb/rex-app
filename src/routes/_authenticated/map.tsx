import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { MapPin, Compass } from "lucide-react";

export const Route = createFileRoute("/_authenticated/map")({
  head: () => ({
    meta: [
      { title: "Map — T. Rex" },
      { name: "description", content: "Places your friends recommend, on a map." },
    ],
  }),
  component: MapPage,
});

function MapPage() {
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

      <div className="relative m-4 h-64 overflow-hidden rounded-2xl bg-gradient-to-br from-accent/20 via-primary/10 to-cat-place/20 ring-1 ring-border">
        <div className="absolute inset-0 opacity-40" style={{
          backgroundImage: "radial-gradient(circle at 20% 30%, hsla(0,0%,100%,.4) 1px, transparent 1px), radial-gradient(circle at 80% 60%, hsla(0,0%,100%,.4) 1px, transparent 1px)",
          backgroundSize: "24px 24px, 32px 32px",
        }} />
        {withLoc.length === 0 ? (
          <div className="relative flex h-full flex-col items-center justify-center gap-2 text-center">
            <Compass className="h-8 w-8 text-primary" />
            <p className="max-w-xs text-sm text-muted-foreground">
              A map view lights up here once you add place recommendations with a location.
            </p>
          </div>
        ) : (
          <div className="relative flex h-full items-center justify-center">
            {withLoc.slice(0, 5).map((p: any, i) => (
              <MapPin
                key={p.id}
                className="absolute h-8 w-8 fill-primary text-primary-foreground drop-shadow"
                style={{
                  left: `${15 + ((i * 17) % 70)}%`,
                  top: `${20 + ((i * 23) % 55)}%`,
                }}
              />
            ))}
          </div>
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
