import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { RecommendationCard, type FeedRow } from "@/components/RecommendationCard";
import { toast } from "sonner";
import { LogOut, Smartphone } from "lucide-react";

export const Route = createFileRoute("/_authenticated/me")({
  head: () => ({
    meta: [
      { title: "Your profile — Reco" },
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

  const { data: myRecs } = useQuery({
    queryKey: ["my-recs", user?.id],
    queryFn: async () => {
      if (!user) return [];
      const { data } = await supabase
        .from("recommendations")
        .select("id, rating, note, created_at, photo_url, user_id, item_id, items!inner(id, type, title, subtitle, image_url), profiles!recommendations_user_id_fkey(username, display_name, avatar_url)")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false });
      return (data ?? []) as unknown as FeedRow[];
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
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-primary text-2xl font-semibold text-primary-foreground">
            {(profile?.display_name || profile?.username || user?.email || "?").slice(0, 1).toUpperCase()}
          </div>
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
              <p className="font-semibold">Install Reco on your iPhone</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Tap the Share icon in Safari, then <em>Add to Home Screen</em>. You'll get an app icon and notifications when friends post.
              </p>
            </div>
          </div>
        </div>
      )}

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

      <div className="p-5">
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
