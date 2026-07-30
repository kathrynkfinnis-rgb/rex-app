import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import {
  LogOut, Smartphone, BookOpen, FileUp, Crown, Bell, Bookmark,
  Sparkles, Users, MessageCircle, Heart,
} from "lucide-react";
import { AvatarUploader } from "@/components/AvatarUploader";
import { EditProfileDialog } from "@/components/EditProfileDialog";
import { RecommendationCard, type FeedRow } from "@/components/RecommendationCard";
import { CATEGORIES } from "@/lib/categories";

export const Route = createFileRoute("/_authenticated/you")({
  head: () => ({
    meta: [
      { title: "Your profile — REX" },
      { name: "description", content: "Your Rex, activity summary and account settings on REX." },
      { property: "og:title", content: "Your profile — REX" },
      { property: "og:description", content: "Your Rex, activity summary and account settings on REX." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: YouPage,
});

function YouPage() {
  const navigate = useNavigate();
  const qc = useQueryClient();

  const { data: user } = useQuery({
    queryKey: ["me-user"],
    queryFn: async () => (await supabase.auth.getUser()).data.user,
  });

  const { data: profile } = useQuery({
    queryKey: ["me-profile", user?.id],
    enabled: !!user,
    queryFn: async () => {
      const { data } = await supabase.from("profiles").select("*").eq("id", user!.id).single();
      return data;
    },
  });

  const { data: isAdmin } = useQuery({
    queryKey: ["me-is-admin", user?.id],
    enabled: !!user,
    queryFn: async () => {
      const { data } = await supabase
        .from("user_roles").select("role")
        .eq("user_id", user!.id).eq("role", "admin").maybeSingle();
      return !!data;
    },
  });

  const { data: recs, isLoading: loadingRecs } = useQuery({
    queryKey: ["me-recs", user?.id],
    enabled: !!user,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("recommendations")
        .select("id, rating, note, created_at, photo_url, photo_urls, tags, user_id, item_id, items!inner(id, type, title, subtitle, image_url, genre), profiles!recommendations_user_id_fkey(username, display_name, avatar_url), creators(slug, name, color, emoji)")
        .eq("user_id", user!.id)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as FeedRow[];
    },
  });

  const { data: activity } = useQuery({
    queryKey: ["me-activity", user?.id],
    enabled: !!user,
    queryFn: async () => {
      const uid = user!.id;
      const [friends, comments, likes, lists, wants, blasts] = await Promise.all([
        supabase.from("friendships").select("id", { count: "exact", head: true })
          .eq("status", "accepted").or(`requester_id.eq.${uid},addressee_id.eq.${uid}`),
        supabase.from("recommendation_comments").select("id", { count: "exact", head: true }).eq("user_id", uid),
        supabase.from("recommendation_likes").select("id", { count: "exact", head: true }).eq("user_id", uid),
        supabase.from("hitlist_lists").select("id", { count: "exact", head: true }).eq("user_id", uid),
        supabase.from("wants").select("id", { count: "exact", head: true }).eq("user_id", uid),
        supabase.from("requests").select("id", { count: "exact", head: true }).eq("user_id", uid),
      ]);
      return {
        friends: friends.count ?? 0,
        comments: comments.count ?? 0,
        likes: likes.count ?? 0,
        lists: lists.count ?? 0,
        wants: wants.count ?? 0,
        blasts: blasts.count ?? 0,
      };
    },
  });

  async function signOut() {
    await qc.cancelQueries();
    qc.clear();
    await supabase.auth.signOut();
    navigate({ to: "/auth", search: { mode: "signin" }, replace: true });
  }

  const total = recs?.length ?? 0;
  const avg = total ? Math.round((recs!.reduce((s, r) => s + r.rating, 0) / total) * 10) / 10 : null;
  const last30 = recs?.filter((r) => Date.now() - new Date(r.created_at).getTime() < 30 * 864e5).length ?? 0;
  const byType = new Map<string, number>();
  for (const r of recs ?? []) {
    const t = (r as any).items?.type as string;
    if (t) byType.set(t, (byType.get(t) ?? 0) + 1);
  }
  const mix = [...byType.entries()].sort((a, b) => b[1] - a[1]);
  const maxMix = Math.max(1, ...mix.map(([, n]) => n));

  const isIOS = typeof navigator !== "undefined" && /iPhone|iPad|iPod/i.test(navigator.userAgent);
  const isStandalone = typeof window !== "undefined" && (window.matchMedia?.("(display-mode: standalone)").matches || (navigator as any).standalone);

  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-6 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <h1 className="font-display text-3xl">Your profile</h1>
        <div className="mt-4 flex items-center gap-4">
          {user ? (
            <AvatarUploader
              userId={user.id}
              currentUrl={profile?.avatar_url}
              displayName={profile?.display_name || profile?.username || user.email}
            />
          ) : null}
          <div className="min-w-0 flex-1">
            <p className="truncate font-display text-2xl">{profile?.display_name || profile?.username}</p>
            <p className="truncate text-sm text-muted-foreground">@{profile?.username}</p>
          </div>
          {user && profile?.username ? (
            <EditProfileDialog
              userId={user.id}
              username={profile.username}
              displayName={profile.display_name}
            />
          ) : null}
        </div>

        <div className="mt-5 grid grid-cols-4 gap-2">
          <Stat label="Rex" value={total} />
          <Stat label="Avg crowns" value={avg ?? "—"} />
          <Stat label="Friends" value={activity?.friends ?? 0} />
          <Stat label="Collections" value={activity?.lists ?? 0} />
        </div>
      </header>

      {isIOS && !isStandalone && (
        <div className="mx-4 mt-4 rounded-2xl border border-primary/30 bg-primary/5 p-4">
          <div className="flex items-start gap-3">
            <Smartphone className="mt-0.5 h-5 w-5 text-primary" />
            <div>
              <p className="font-semibold">Install REX on your iPhone</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Tap the Share icon in Safari, then <em>Add to Home Screen</em>.
              </p>
            </div>
          </div>
        </div>
      )}

      <section className="p-4">
        <h2 className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
          <Sparkles className="h-3.5 w-3.5" /> Your activity
        </h2>
        <div className="grid grid-cols-2 gap-2">
          <MiniStat icon={<Sparkles className="h-4 w-4" />} label="Rex last 30 days" value={last30} />
          <MiniStat icon={<MessageCircle className="h-4 w-4" />} label="Comments left" value={activity?.comments ?? 0} />
          <MiniStat icon={<Heart className="h-4 w-4" />} label="Posts liked" value={activity?.likes ?? 0} />
          <MiniStat icon={<Bookmark className="h-4 w-4" />} label="Saved to collections" value={activity?.wants ?? 0} />
          <MiniStat icon={<Users className="h-4 w-4" />} label="Blasts posted" value={activity?.blasts ?? 0} />
          <MiniStat icon={<Crown className="h-4 w-4" />} label="Friends" value={activity?.friends ?? 0} />
        </div>

        {mix.length > 0 && (
          <div className="mt-3 rounded-2xl border border-border bg-card p-4">
            <p className="mb-2 text-xs font-semibold uppercase tracking-widest text-muted-foreground">What you Rex</p>
            <div className="space-y-1.5">
              {mix.map(([type, n]) => (
                <div key={type} className="flex items-center gap-2">
                  <div className="w-20 shrink-0 truncate text-xs">
                    {CATEGORIES.find((c) => c.type === type)?.label ?? type}
                  </div>
                  <div className="h-2 flex-1 overflow-hidden rounded-full bg-muted">
                    <div className="h-full rounded-full bg-primary" style={{ width: `${Math.max(6, (n / maxMix) * 100)}%` }} />
                  </div>
                  <div className="w-6 text-right text-xs tabular-nums text-muted-foreground">{n}</div>
                </div>
              ))}
            </div>
          </div>
        )}
      </section>

      <section className="px-4 pb-2">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
            Your Rex
          </h2>
          <Link to="/me" className="text-xs font-medium text-primary">My Collections →</Link>
        </div>
        {loadingRecs ? (
          <div className="h-40 animate-pulse rounded-2xl bg-muted" />
        ) : total > 0 ? (
          <div className="space-y-3">
            {recs!.slice(0, 10).map((r) => <RecommendationCard key={r.id} rec={r} />)}
            {total > 10 && (
              <p className="pt-1 text-center text-xs text-muted-foreground">
                Showing your 10 most recent of {total}.
              </p>
            )}
          </div>
        ) : (
          <div className="rounded-2xl border border-dashed border-border bg-card p-6 text-center">
            <p className="text-sm text-muted-foreground">You haven't posted a Rex yet.</p>
            <Link to="/add" className="mt-3 inline-block">
              <Button className="rounded-full">Add your first</Button>
            </Link>
          </div>
        )}
      </section>

      <div className="space-y-2 p-5">
        <Link to="/notification-settings">
          <Button variant="outline" className="h-12 w-full gap-2 rounded-full">
            <Bell className="h-4 w-4" /> Notification settings
          </Button>
        </Link>
        <Link to="/import">
          <Button variant="outline" className="h-12 w-full gap-2 rounded-full">
            <FileUp className="h-4 w-4" /> Import from Sheet or Doc
          </Button>
        </Link>
        <Link to="/import-goodreads">
          <Button variant="outline" className="h-12 w-full gap-2 rounded-full">
            <BookOpen className="h-4 w-4" /> Import from Goodreads
          </Button>
        </Link>
        {isAdmin && (
          <Link to="/admin">
            <Button variant="outline" className="h-12 w-full gap-2 rounded-full border-primary/40 text-primary">
              <Crown className="h-4 w-4" /> REX admin dashboard
            </Button>
          </Link>
        )}
        <Button variant="outline" onClick={signOut} className="h-12 w-full gap-2 rounded-full">
          <LogOut className="h-4 w-4" /> Sign out
        </Button>
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number | string }) {
  return (
    <div className="rounded-xl border border-border bg-card px-2 py-2 text-center">
      <div className="font-display text-xl leading-none">{value}</div>
      <div className="mt-1 text-[10px] uppercase tracking-wide text-muted-foreground">{label}</div>
    </div>
  );
}

function MiniStat({ icon, label, value }: { icon: React.ReactNode; label: string; value: number }) {
  return (
    <div className="flex items-center gap-2 rounded-xl border border-border bg-card px-3 py-2.5">
      <span className="text-primary">{icon}</span>
      <div className="min-w-0">
        <div className="font-display text-lg leading-none">{value}</div>
        <div className="truncate text-[11px] text-muted-foreground">{label}</div>
      </div>
    </div>
  );
}
