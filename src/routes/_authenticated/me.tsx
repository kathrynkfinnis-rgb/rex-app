import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { RecommendationCard, type FeedRow } from "@/components/RecommendationCard";
import { toast } from "sonner";
import { LogOut, Smartphone, BookOpen, FileUp, Bookmark, BookmarkCheck, Crown } from "lucide-react";
import { AvatarUploader } from "@/components/AvatarUploader";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/me")({
  head: () => ({
    meta: [
      { title: "Your profile — REX" },
      { name: "description", content: "Your recommendations and settings." },
    ],
  }),
  component: MePage,
});

function MePage() {
  const navigate = useNavigate();
  const qc = useQueryClient();

  const { data: user } = useQuery({
    queryKey: ["me-user"],
    queryFn: async () => (await supabase.auth.getUser()).data.user,
  });

  const { data: profile } = useQuery({
    queryKey: ["me-profile", user?.id],
    queryFn: async () => {
      if (!user) return null;
      const { data } = await supabase.from("profiles").select("*").eq("id", user.id).single();
      return data;
    },
    enabled: !!user,
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


  const { data: myRecs } = useQuery({
    queryKey: ["my-recs", user?.id],
    queryFn: async () => {
      if (!user) return [];
      const { data } = await supabase
        .from("recommendations")
        .select("id, rating, note, created_at, photo_url, photo_urls, user_id, item_id, items!inner(id, type, title, subtitle, image_url), profiles!recommendations_user_id_fkey(username, display_name, avatar_url)")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false });
      return (data ?? []) as unknown as FeedRow[];
    },
    enabled: !!user,
  });

  const { data: myWants } = useQuery({
    queryKey: ["my-wants", user?.id],
    queryFn: async () => {
      if (!user) return [];
      const { data } = await supabase
        .from("wants")
        .select("id, created_at, item_id, items!inner(id, type, title, subtitle, image_url)")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false });
      return (data ?? []) as unknown as Array<{
        id: string;
        item_id: string;
        items: { id: string; type: ItemType; title: string; subtitle: string | null; image_url: string | null };
      }>;
    },
    enabled: !!user,
  });

  const { data: mySaved } = useQuery({
    queryKey: ["my-saved-posts", user?.id],
    queryFn: async () => {
      if (!user) return [];
      const { data } = await supabase
        .from("saved_posts")
        .select("id, created_at, recommendations!inner(id, rating, note, created_at, photo_url, photo_urls, user_id, item_id, items!inner(id, type, title, subtitle, image_url, genre), profiles!recommendations_user_id_fkey(username, display_name, avatar_url))")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false });
      return (data ?? []) as unknown as Array<{ id: string; recommendations: FeedRow }>;
    },
    enabled: !!user,
  });

  async function signOut() {
    await qc.cancelQueries();
    qc.clear();
    await supabase.auth.signOut();
    navigate({ to: "/auth", search: { mode: "signin" }, replace: true });
  }

  const isIOS = typeof navigator !== "undefined" && /iPhone|iPad|iPod/i.test(navigator.userAgent);
  const isStandalone = typeof window !== "undefined" && (window.matchMedia?.("(display-mode: standalone)").matches || (navigator as any).standalone);

  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-6 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <h1 className="font-display text-3xl">You</h1>
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
        </div>
      </header>

      {isIOS && !isStandalone && (
        <div className="mx-4 mt-4 rounded-2xl border border-primary/30 bg-primary/5 p-4">
          <div className="flex items-start gap-3">
            <Smartphone className="mt-0.5 h-5 w-5 text-primary" />
            <div>
              <p className="font-semibold">Install REX on your iPhone</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Tap the Share icon in Safari, then <em>Add to Home Screen</em>. You'll get an app icon and notifications when friends post.
              </p>
            </div>
          </div>
        </div>
      )}

      <section className="p-4">
        <h2 className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
          <Bookmark className="h-3.5 w-3.5" /> Your want-to list
        </h2>
        {myWants && myWants.length > 0 ? (
          <div className="space-y-2">
            {myWants.map((w) => {
              const cat = categoryMeta(w.items.type);
              const Icon = cat.icon;
              return (
                <Link
                  key={w.id}
                  to="/item/$id"
                  params={{ id: w.item_id }}
                  className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border transition-colors active:scale-[0.99]"
                >
                  <div className={cn("flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-xl", cat.tokenClass)}>
                    {w.items.image_url ? (
                      <img src={w.items.image_url} alt="" className="h-full w-full object-cover" />
                    ) : (
                      <Icon className="h-5 w-5" />
                    )}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">{w.items.title}</p>
                    <p className="truncate text-xs text-muted-foreground">{cat.wantVerb}</p>
                  </div>
                </Link>
              );
            })}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">Nothing saved yet — tap "Want to…" on any recommendation.</p>
        )}
      </section>

      <section className="p-4">
        <h2 className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
          <BookmarkCheck className="h-3.5 w-3.5" /> Saved posts
        </h2>
        {mySaved && mySaved.length > 0 ? (
          <div className="space-y-3">
            {mySaved.map((s) => <RecommendationCard key={s.id} rec={s.recommendations} />)}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">Nothing saved yet — tap the bookmark on any post to save it here.</p>
        )}
      </section>

      <section className="p-4">
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-widest text-muted-foreground">Your recommendations</h2>
        {myRecs && myRecs.length > 0 ? (
          <div className="space-y-3">
            {myRecs.map((r) => <RecommendationCard key={r.id} rec={r} />)}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">You haven't posted any yet.</p>
        )}
      </section>

      <div className="space-y-2 p-5">
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
        <Button
          variant="outline"
          onClick={signOut}
          className="h-12 w-full gap-2 rounded-full"
        >
          <LogOut className="h-4 w-4" /> Sign out
        </Button>

      </div>
    </div>
  );
}
