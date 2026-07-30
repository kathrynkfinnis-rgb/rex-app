import { createFileRoute, Outlet, redirect, Link, useRouteContext } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { BottomNav } from "@/components/BottomNav";
import { NotificationBell } from "@/components/NotificationBell";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated")({
  ssr: false,
  beforeLoad: async () => {
    const { data, error } = await supabase.auth.getUser();
    if (error || !data.user) throw redirect({ to: "/auth", search: { mode: "signin" } });
    return { user: data.user };
  },
  component: AuthedLayout,
});

function ProfileButton() {
  const { user } = useRouteContext({ from: "/_authenticated" });
  const { data: profile } = useQuery({
    queryKey: ["layout-profile", user.id],
    queryFn: async () => {
      const { data } = await supabase
        .from("profiles")
        .select("display_name, username, avatar_url")
        .eq("id", user.id)
        .single();
      return data;
    },
  });

  const initial = (profile?.display_name || profile?.username || user.email || "?").slice(0, 1).toUpperCase();

  return (
    <Link
      to="/you"
      className={cn(
        "pointer-events-auto flex h-10 w-10 items-center justify-center rounded-full bg-primary text-sm font-semibold text-primary-foreground shadow-md ring-2 ring-background transition-transform active:scale-95",
        profile?.avatar_url && "bg-cover bg-center text-transparent"
      )}
      style={profile?.avatar_url ? { backgroundImage: `url(${profile.avatar_url})` } : undefined}
      aria-label="Your profile"
    >
      {initial}
    </Link>
  );
}

function AuthedLayout() {
  const { user } = useRouteContext({ from: "/_authenticated" });
  return (
    <div className="min-h-screen bg-background pb-24">
      <div className="fixed left-1/2 top-[calc(env(safe-area-inset-top)+0.75rem)] z-40 w-full max-w-md -translate-x-1/2 px-4 pointer-events-none">
        <div className="flex items-center justify-between gap-2">
          <Link
            to="/feedback"
            aria-label="Send feedback"
            className="pointer-events-auto flex h-10 w-10 items-center justify-center rounded-full bg-card text-foreground shadow-md ring-2 ring-background transition-transform active:scale-95"
          >
            <MessageSquarePlus className="h-5 w-5" />
          </Link>
          <div className="flex gap-2">
            <NotificationBell userId={user.id} />
            <ProfileButton />
          </div>
        </div>
      </div>

      <div className="mx-auto max-w-md">
        <Outlet />
      </div>
      <BottomNav />
    </div>
  );
}
