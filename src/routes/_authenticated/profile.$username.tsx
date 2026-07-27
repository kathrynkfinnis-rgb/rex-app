import { createFileRoute, Link, notFound } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { RecommendationCard, type FeedRow } from "@/components/RecommendationCard";
import { CrownRatingDisplay } from "@/components/CrownRating";
import { ArrowLeft } from "lucide-react";

export const Route = createFileRoute("/_authenticated/profile/$username")({
  head: ({ params }) => ({
    meta: [
      { title: `@${params.username} — REX` },
      { name: "description", content: `Recommendations from @${params.username} on REX.` },
    ],
  }),
  component: ProfilePage,
});

function ProfilePage() {
  const { username } = Route.useParams();

  const { data: profile, isLoading: loadingProfile, error } = useQuery({
    queryKey: ["profile", username],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("profiles")
        .select("id, username, display_name, avatar_url, created_at")
        .eq("username", username)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
  });

  const { data: recs, isLoading: loadingRecs } = useQuery({
    queryKey: ["profile-recs", profile?.id],
    queryFn: async () => {
      if (!profile) return [];
      const { data, error } = await supabase
        .from("recommendations")
        .select("id, rating, note, created_at, photo_url, user_id, item_id, items!inner(id, type, title, subtitle, image_url, genre), profiles!recommendations_user_id_fkey(username, display_name, avatar_url), creators(slug, name, color, emoji)")
        .eq("user_id", profile.id)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as FeedRow[];
    },
    enabled: !!profile,
  });

  const avgRating = recs && recs.length
    ? Math.round((recs.reduce((s, r) => s + r.rating, 0) / recs.length) * 10) / 10
    : null;

  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-6 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <Link to="/friends" className="mb-3 inline-flex items-center gap-1 text-sm text-muted-foreground">
          <ArrowLeft className="h-4 w-4" /> Back
        </Link>
        {loadingProfile ? (
          <div className="h-16 w-full animate-pulse rounded-2xl bg-muted" />
        ) : !profile ? (
          <div className="rounded-2xl border border-dashed border-border p-6 text-center">
            <p className="font-medium">Profile not found</p>
            <p className="mt-1 text-sm text-muted-foreground">
              @{username} may not exist, or you need to be friends to see them.
            </p>
          </div>
        ) : (
          <div className="flex items-center gap-4">
            <div className="flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full bg-primary text-2xl font-semibold text-primary-foreground">
              {profile.avatar_url ? (
                <img src={profile.avatar_url} alt="" className="h-full w-full object-cover" />
              ) : (
                (profile.display_name || profile.username || "?").slice(0, 1).toUpperCase()
              )}
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate font-display text-2xl">{profile.display_name || profile.username}</p>
              <p className="truncate text-sm text-muted-foreground">@{profile.username}</p>
              {recs && recs.length > 0 && (
                <div className="mt-2 flex items-center gap-3 text-sm text-muted-foreground">
                  <span>{recs.length} rec{recs.length === 1 ? "" : "s"}</span>
                  {avgRating != null && (
                    <span className="flex items-center gap-1">
                      avg <CrownRatingDisplay value={Math.round(avgRating)} size="xs" showNumber />
                    </span>
                  )}
                </div>
              )}
            </div>
          </div>
        )}
      </header>

      {profile && (
        <section className="p-4">
          <h2 className="mb-3 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
            Recommendations
          </h2>
          {loadingRecs ? (
            <div className="h-40 animate-pulse rounded-2xl bg-muted" />
          ) : recs && recs.length > 0 ? (
            <div className="space-y-3">
              {recs.map((r) => <RecommendationCard key={r.id} rec={r} />)}
            </div>
          ) : (
            <div className="rounded-2xl border border-dashed border-border bg-card p-6 text-center">
              <p className="text-sm text-muted-foreground">Nothing posted yet.</p>
            </div>
          )}
        </section>
      )}
    </div>
  );
}
