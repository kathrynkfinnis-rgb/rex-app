import { createFileRoute, Link, notFound } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { CrownRatingDisplay } from "@/components/CrownRating";
import { categoryMeta, splitGenres, type ItemType } from "@/lib/categories";
import { UserAvatar } from "@/components/UserAvatar";
import { ShareButton } from "@/components/ShareButton";
import { Luggage, MapPin, Navigation } from "lucide-react";

type SharedTrip = {
  id: string;
  rating: number;
  note: string | null;
  created_at: string;
  photo_url: string | null;
  photo_urls: string[] | null;
  item_id: string;
  item_title: string;
  item_subtitle: string | null;
  item_image_url: string | null;
  author_username: string | null;
  author_display_name: string | null;
  author_avatar_url: string | null;
};

type SharedStop = {
  id: string;
  rating: number;
  note: string | null;
  created_at: string;
  photo_url: string | null;
  photo_urls: string[] | null;
  item_id: string;
  item_type: ItemType;
  item_title: string;
  item_subtitle: string | null;
  item_image_url: string | null;
  item_genre: string | null;
  item_address: string | null;
  item_lat: number | null;
  item_lng: number | null;
};

const SITE = "https://pocket-app-pioneers.lovable.app";

function mapsHref(stop: SharedStop) {
  if (stop.item_lat != null && stop.item_lng != null) {
    return `https://www.google.com/maps/search/?api=1&query=${stop.item_lat},${stop.item_lng}`;
  }
  const q = [stop.item_title, stop.item_address].filter(Boolean).join(" ");
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(q)}`;
}

export const Route = createFileRoute("/t/$id")({
  loader: async ({ params }) => {
    const [tripRes, stopsRes] = await Promise.all([
      supabase.rpc("get_shared_trip", { trip_id: params.id }),
      supabase.rpc("get_shared_trip_stops", { trip_id: params.id }),
    ]);
    const trip = (tripRes.data as SharedTrip[] | null)?.[0];
    if (tripRes.error || !trip) throw notFound();
    return { trip, stops: ((stopsRes.data ?? []) as SharedStop[]) };
  },
  head: ({ params, loaderData }) => {
    const trip = loaderData?.trip;
    if (!trip) {
      return {
        meta: [
          { title: "Trip on REX 🦖" },
          { name: "description", content: "See the full itinerary for this trip on REX." },
        ],
      };
    }
    const who = trip.author_display_name || trip.author_username || "A friend";
    const count = loaderData?.stops.length ?? 0;
    const title = `${who}'s trip: ${trip.item_title} 🧳`;
    const desc = trip.note
      ? `"${trip.note.replace(/\s+/g, " ").slice(0, 155)}"`
      : `${count} ${count === 1 ? "stop" : "stops"} on REX 🦖 — the itinerary, in order, with every Rex.`;
    const image = (trip.photo_urls && trip.photo_urls[0]) || trip.photo_url || trip.item_image_url || undefined;
    const url = `${SITE}/t/${params.id}`;
    const meta: Array<Record<string, string>> = [
      { title },
      { name: "description", content: desc },
      { property: "og:title", content: title },
      { property: "og:description", content: desc },
      { property: "og:url", content: url },
      { property: "og:type", content: "article" },
      { property: "og:site_name", content: "REX 🦖" },
      { name: "twitter:card", content: image ? "summary_large_image" : "summary" },
      { name: "twitter:title", content: title },
      { name: "twitter:description", content: desc },
    ];
    if (image) {
      meta.push({ property: "og:image", content: image });
      meta.push({ name: "twitter:image", content: image });
    }
    return { meta, links: [{ rel: "canonical", href: url }] };
  },
  component: SharedTripPage,
});

function SharedTripPage() {
  const { trip, stops } = Route.useLoaderData();
  const { id } = Route.useParams();
  const { data: session, isPending } = useQuery({
    queryKey: ["share-session"],
    queryFn: async () => (await supabase.auth.getSession()).data.session,
    staleTime: 60_000,
  });
  const signedIn = !!session;
  const who = trip.author_display_name || trip.author_username || "A friend";
  const hero = (trip.photo_urls && trip.photo_urls[0]) || trip.photo_url || trip.item_image_url;
  const shareUrl = `${SITE}/t/${id}`;
  const mappable = stops.filter((s) => s.item_lat != null && s.item_lng != null);
  const allStopsHref =
    mappable.length > 1
      ? `https://www.google.com/maps/dir/${mappable.map((s) => `${s.item_lat},${s.item_lng}`).join("/")}`
      : mappable.length === 1
        ? mapsHref(mappable[0])
        : null;

  return (
    <div className="min-h-dvh bg-background">
      <header className="border-b border-border bg-background/90 px-4 py-3 backdrop-blur">
        <Link to="/" className="inline-flex items-center gap-2 font-display text-lg font-black">
          <span>🦖</span> REX
        </Link>
      </header>

      <main className="mx-auto max-w-lg space-y-4 px-4 py-6">
        <div className="overflow-hidden rounded-3xl bg-card shadow-sm ring-1 ring-border">
          {hero && <img src={hero} alt="" className="max-h-72 w-full object-cover" />}
          <div className="space-y-3 p-5">
            <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-primary">
              <Luggage className="h-4 w-4" /> Trip
              <div className="ml-auto"><CrownRatingDisplay value={trip.rating} size="sm" showNumber /></div>
            </div>
            <div>
              <h1 className="font-display text-2xl leading-tight">{trip.item_title}</h1>
              {trip.item_subtitle && <p className="mt-0.5 text-sm text-muted-foreground">{trip.item_subtitle}</p>}
              <p className="mt-1 text-sm text-muted-foreground">
                {stops.length} {stops.length === 1 ? "stop" : "stops"}
              </p>
            </div>
            {trip.note && (
              <blockquote className="rounded-2xl bg-muted/50 p-4 text-[15px] leading-snug">
                &ldquo;{trip.note}&rdquo;
              </blockquote>
            )}
            <div className="flex items-center gap-2 pt-1">
              <UserAvatar url={trip.author_avatar_url} name={who} size="sm" />
              <div className="text-sm">
                <span className="font-medium">{who}</span>
                {trip.author_username && <span className="text-muted-foreground"> · @{trip.author_username}</span>}
              </div>
            </div>
          </div>
        </div>

        {allStopsHref && (
          <a
            href={allStopsHref}
            target="_blank"
            rel="noreferrer"
            className="flex items-center justify-center gap-2 rounded-full border border-border bg-card px-5 py-3 text-sm font-semibold"
          >
            <MapPin className="h-4 w-4" /> See the whole route on the map
          </a>
        )}

        <h2 className="px-1 pt-2 font-display text-xl">Itinerary</h2>

        {stops.length === 0 && (
          <p className="rounded-2xl border border-dashed border-border bg-card p-6 text-center text-sm text-muted-foreground">
            No stops added to this trip yet.
          </p>
        )}

        {stops.length > 0 && (
          <ol className="relative space-y-3 pl-9">
            <span
              aria-hidden
              className="absolute bottom-6 left-[13px] top-6 w-px bg-gradient-to-b from-primary/40 via-border to-transparent"
            />
            {stops.map((stop, i) => {
              const meta = categoryMeta(stop.item_type);
              const Icon = meta.icon;
              const canMap = stop.item_lat != null || !!stop.item_address;
              return (
                <li key={stop.id} className="relative">
                  <span className="absolute -left-9 top-3 flex h-7 w-7 items-center justify-center rounded-full bg-background text-[11px] font-bold text-primary ring-2 ring-primary/30">
                    {i + 1}
                  </span>
                  <div className="mb-1 flex items-center gap-1.5 pl-0.5 text-[11px] font-semibold uppercase tracking-widest text-muted-foreground">
                    <Icon className="h-3.5 w-3.5" />
                    {meta.label}
                    {stop.item_genre && (
                      <span className="normal-case tracking-normal text-muted-foreground/80">
                        · {splitGenres(stop.item_genre).join(", ")}
                      </span>
                    )}
                  </div>
                  <div className="overflow-hidden rounded-2xl bg-card ring-1 ring-border">
                    <div className="flex gap-3 p-3">
                      {(stop.photo_urls?.[0] || stop.photo_url || stop.item_image_url) && (
                        <img
                          src={stop.photo_urls?.[0] || stop.photo_url || stop.item_image_url || ""}
                          alt=""
                          className="h-20 w-16 shrink-0 rounded-xl object-cover"
                        />
                      )}
                      <div className="min-w-0 flex-1">
                        <div className="flex items-start gap-2">
                          <h3 className="min-w-0 flex-1 font-semibold leading-tight">{stop.item_title}</h3>
                          <CrownRatingDisplay value={stop.rating} size="xs" showNumber />
                        </div>
                        {stop.item_subtitle && (
                          <p className="truncate text-xs text-muted-foreground">{stop.item_subtitle}</p>
                        )}
                        {stop.note && <p className="mt-1 text-sm leading-snug">&ldquo;{stop.note}&rdquo;</p>}
                        {canMap && (
                          <a
                            href={mapsHref(stop)}
                            target="_blank"
                            rel="noreferrer"
                            className="mt-2 inline-flex items-center gap-1.5 rounded-full bg-secondary/70 px-3 py-1 text-xs font-semibold text-secondary-foreground"
                          >
                            <Navigation className="h-3 w-3" /> Navigate
                          </a>
                        )}
                      </div>
                    </div>
                  </div>
                </li>
              );
            })}
          </ol>
        )}

        {isPending ? null : signedIn ? (
          <Link
            to="/trip/$id"
            params={{ id }}
            className="block rounded-full bg-primary px-5 py-3 text-center font-semibold text-primary-foreground shadow-sm active:scale-[0.99]"
          >
            Open in REX 🦖
          </Link>
        ) : (
          <div className="rounded-3xl bg-primary/10 p-5 text-center ring-1 ring-primary/20">
            <div className="text-lg font-semibold">Save this trip on REX 🦖</div>
            <p className="mt-1 text-sm text-muted-foreground">
              Keep every stop your friends actually loved, in one place.
            </p>
            <Link
              to="/auth"
              search={{ mode: "signup", ref: trip.author_username ?? undefined } as any}
              className="mt-4 block rounded-full bg-primary px-5 py-3 text-center font-semibold text-primary-foreground shadow-sm active:scale-[0.99]"
            >
              Join REX free
            </Link>
          </div>
        )}

        <div className="flex justify-center pt-1">
          <ShareButton url={shareUrl} text={`${who}'s trip: ${trip.item_title} 🧳 on REX 🦖`} label="Share this trip" />
        </div>
      </main>
    </div>
  );
}
