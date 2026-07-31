import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { RecommendationCard, type FeedRow } from "@/components/RecommendationCard";
import { CrownRatingDisplay } from "@/components/CrownRating";
import { LikesComments } from "@/components/LikesComments";
import { UserAvatar } from "@/components/UserAvatar";
import { Button } from "@/components/ui/button";
import { ArrowLeft, Plus, Luggage } from "lucide-react";
import { formatDistanceToNow } from "date-fns";

const SELECT =
  "id, rating, note, created_at, photo_url, photo_urls, tags, user_id, item_id, trip_id, items!inner(id, type, title, subtitle, image_url, genre), profiles!recommendations_user_id_fkey(username, display_name, avatar_url), creators(slug, name, color, emoji)";

export const Route = createFileRoute("/_authenticated/trip/$id")({
  head: () => ({
    meta: [
      { title: "Trip — REX" },
      { name: "description", content: "Every Rex from this trip, in one place." },
    ],
  }),
  component: TripPage,
});

function TripPage() {
  const { id } = Route.useParams();
  const navigate = useNavigate();

  const { data: uid } = useQuery({
    queryKey: ["current-user-id"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    staleTime: 5 * 60 * 1000,
  });

  const trip = useQuery({
    queryKey: ["trip", id],
    queryFn: async () => {
      const { data, error } = await supabase.from("recommendations").select(SELECT).eq("id", id).maybeSingle();
      if (error) throw error;
      return (data ?? null) as unknown as FeedRow | null;
    },
  });

  const stops = useQuery({
    queryKey: ["trip-stops", id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("recommendations")
        .select(SELECT)
        .eq("trip_id", id)
        .order("created_at", { ascending: true });
      if (error) throw error;
      return (data ?? []) as unknown as FeedRow[];
    },
  });

  const t = trip.data;
  const isOwner = !!uid && !!t && uid === t.user_id;
  const photos = (t?.photo_urls?.length ? t.photo_urls : t?.photo_url ? [t.photo_url] : []) as string[];

  return (
    <div className="min-h-screen">
      <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <button
          onClick={() => navigate({ to: "/feed" })}
          className="flex items-center gap-2 text-sm text-muted-foreground"
        >
          <ArrowLeft className="h-4 w-4" /> Back
        </button>

        {trip.isLoading && <div className="mt-4 h-8 w-2/3 animate-pulse rounded bg-muted" />}

        {t && (
          <>
            <div className="mt-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-primary">
              <Luggage className="h-4 w-4" /> Trip
            </div>
            <h1 className="mt-1 font-display text-3xl leading-tight">{t.items?.title}</h1>
            {t.items?.subtitle && <p className="text-sm text-muted-foreground">{t.items.subtitle}</p>}
            <div className="mt-2 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
              <CrownRatingDisplay value={t.rating} size="xs" showNumber />
              <span>·</span>
              <span>{stops.data?.length ?? 0} {stops.data?.length === 1 ? "stop" : "stops"}</span>
              <span>·</span>
              <span>{formatDistanceToNow(new Date(t.created_at), { addSuffix: true }).replace("about ", "")}</span>
            </div>
            {t.profiles?.username && (
              <Link
                to="/profile/$username"
                params={{ username: t.profiles.username }}
                className="mt-2 inline-flex items-center gap-2 rounded-full bg-card px-2 py-1 text-sm ring-1 ring-border"
              >
                <UserAvatar url={t.profiles.avatar_url} name={t.profiles.display_name || t.profiles.username} size="xs" />
                <span className="font-medium">{t.profiles.display_name || t.profiles.username}</span>
              </Link>
            )}
          </>
        )}
      </header>

      {!trip.isLoading && !t && (
        <p className="p-6 text-center text-sm text-muted-foreground">This trip doesn't exist any more.</p>
      )}

      {t && (
        <div className="space-y-3 px-3 py-3">
          {t.note && (
            <p className="rounded-2xl bg-card p-3 text-sm leading-snug ring-1 ring-border">&ldquo;{t.note}&rdquo;</p>
          )}

          {photos.length > 0 && (
            <div className="grid grid-cols-2 gap-1 overflow-hidden rounded-2xl">
              {photos.slice(0, 4).map((url) => (
                <img key={url} src={url} alt="" className="aspect-[4/3] w-full object-cover" />
              ))}
            </div>
          )}

          <div className="rounded-2xl bg-card px-3 py-1.5 ring-1 ring-border">
            <LikesComments recommendationId={t.id} />
          </div>

          {isOwner && (
            <Button
              onClick={() => navigate({ to: "/add", search: { trip: t.id } })}
              className="h-12 w-full gap-2 rounded-full font-semibold shadow-lg shadow-primary/30"
            >
              <Plus className="h-4 w-4" /> Add Rex to this trip
            </Button>
          )}

          <div className="flex items-center justify-between px-1 pt-1">
            <h2 className="font-display text-xl">Itinerary</h2>
            {(stops.data?.some((s) => s.items?.type === "place" || s.items?.type === "event") ?? false) && (
              <Link to="/map" className="text-sm font-semibold text-primary">
                See on map
              </Link>
            )}
          </div>

          {stops.isLoading && <div className="h-24 animate-pulse rounded-2xl bg-muted" />}

          {!stops.isLoading && (stops.data?.length ?? 0) === 0 && (
            <p className="rounded-2xl border border-dashed border-border bg-card p-6 text-center text-sm text-muted-foreground">
              {isOwner
                ? "No stops yet — add the restaurants, museums, bars and hotels that made this trip. Each one becomes its own Rex too."
                : "No stops added to this trip yet."}
            </p>
          )}

          {(stops.data?.length ?? 0) > 0 && (
            <ol className="relative space-y-3 pl-9">
              <span
                aria-hidden
                className="absolute bottom-6 left-[13px] top-6 w-px bg-gradient-to-b from-primary/40 via-border to-transparent"
              />
              {stops.data!.map((rec, i) => {
                const meta = categoryMeta((rec.items?.type ?? "other") as ItemType);
                const Icon = meta.icon;
                return (
                  <li key={rec.id} className="relative">
                    <span className="absolute -left-9 top-3 flex h-7 w-7 items-center justify-center rounded-full bg-background text-[11px] font-bold text-primary ring-2 ring-primary/30">
                      {i + 1}
                    </span>
                    <div className="mb-1 flex items-center gap-1.5 pl-0.5 text-[11px] font-semibold uppercase tracking-widest text-muted-foreground">
                      <Icon className="h-3.5 w-3.5" />
                      {meta.label}
                      {rec.items?.genre && (
                        <span className="normal-case tracking-normal text-muted-foreground/80">
                          · {splitGenres(rec.items.genre).join(", ")}
                        </span>
                      )}
                    </div>
                    <RecommendationCard rec={rec} />
                  </li>
                );
              })}
            </ol>
          )}

        </div>
      )}
    </div>
  );
}
