import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { LogOut, Smartphone, BookOpen, FileUp, Bookmark, Crown } from "lucide-react";
import { AvatarUploader } from "@/components/AvatarUploader";
import { HitList } from "@/components/HitList";

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
          <Bookmark className="h-3.5 w-3.5" /> My List
        </h2>
        {user ? <HitList userId={user.id} /> : null}
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
