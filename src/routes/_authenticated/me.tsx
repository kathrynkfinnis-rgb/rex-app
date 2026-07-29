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
        <h1 className="font-display text-3xl">My List</h1>
        <p className="mt-1 text-sm text-muted-foreground">Everything you want to read, watch, eat and do.</p>
      </header>

      <section className="p-4">
        {user ? <HitList userId={user.id} /> : null}
      </section>
    </div>
  );
}

