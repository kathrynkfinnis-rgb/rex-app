import { createFileRoute, Link, useRouteContext } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Crown, Users, TrendingUp, MessageCircle, Heart, Bookmark, Megaphone, Sparkles, ArrowLeft, Zap, Network, BarChart3 } from "lucide-react";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/admin")({
  head: () => ({
    meta: [
      { title: "REX Admin — KPI Dashboard" },
      { name: "description", content: "Internal REX admin dashboard for monitoring users, growth and content activity." },
      { name: "robots", content: "noindex,nofollow" },
    ],
  }),
  component: AdminPage,
});

type UserKpis = {
  total_users: number;
  new_24h: number; new_7d: number; new_30d: number;
  dau: number; wau: number; mau: number;
};
type ContentKpis = {
  recs_total: number; recs_7d: number;
  blasts_total: number; blasts_7d: number;
  rec_comments_total: number; rec_comments_7d: number;
  blast_comments_total: number; blast_comments_7d: number;
  likes_total: number; likes_7d: number;
  saves_total: number; saves_7d: number;
};
type WeekPoint = { week: string; count: number };
type EngagementKpis = {
  total_users: number; activated_users: number; users_with_friend: number;
  friendships_accepted: number; friendships_pending: number; friend_accept_rate: number;
  avg_friends: number; recs_per_active_user: number;
  recs_with_photo: number; recs_with_note: number; avg_rating: number;
  lists_total: number; lists_published: number; wants_total: number;
  items_total: number; places_geocoded: number; places_total: number;
  blasts_answered: number; blasts_total: number; imports_total: number;
  by_category: { type: string; count: number }[];
  signups_by_week: WeekPoint[];
  recs_by_week: WeekPoint[];
  top_contributors: { username: string; display_name: string | null; count: number }[];
};

function AdminPage() {
  const { user } = useRouteContext({ from: "/_authenticated" });

  const { data: isAdmin, isLoading: roleLoading } = useQuery({
    queryKey: ["is-admin", user.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("user_roles")
        .select("role")
        .eq("user_id", user.id)
        .eq("role", "admin")
        .maybeSingle();
      if (error) return false;
      return !!data;
    },
  });

  const enabled = !!isAdmin;

  const usersQ = useQuery({
    queryKey: ["admin-kpis-users"],
    enabled,
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("admin_kpis_users");
      if (error) throw error;
      return data as UserKpis;
    },
  });

  const contentQ = useQuery({
    queryKey: ["admin-kpis-content"],
    enabled,
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("admin_kpis_content");
      if (error) throw error;
      return data as ContentKpis;
    },
  });

  const adminsQ = useQuery({
    queryKey: ["admin-team"],
    enabled,
    queryFn: async () => {
      const { data: roles } = await supabase
        .from("user_roles")
        .select("user_id, created_at, role")
        .eq("role", "admin");
      const ids = (roles ?? []).map((r) => r.user_id);
      if (ids.length === 0) return [];
      const { data: profiles } = await supabase
        .from("profiles")
        .select("id, username, display_name, avatar_url")
        .in("id", ids);
      return (profiles ?? []).map((p) => ({
        ...p,
        since: roles!.find((r) => r.user_id === p.id)?.created_at,
      }));
    },
  });

  if (roleLoading) {
    return <div className="p-6 pt-20 text-sm text-muted-foreground">Loading…</div>;
  }

  if (!isAdmin) {
    return (
      <div className="p-6 pt-24 text-center">
        <Crown className="mx-auto h-10 w-10 text-muted-foreground" />
        <h1 className="mt-3 text-lg font-semibold">Admin only</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          This dashboard is restricted to the REX admin team.
        </p>
        <Link to="/feed" className="mt-4 inline-block text-sm text-primary underline">Back to feed</Link>
      </div>
    );
  }

  const u = usersQ.data;
  const c = contentQ.data;

  return (
    <div className="px-4 pb-8 pt-20">
      <div className="mb-4 flex items-center gap-2">
        <Link to="/me" className="rounded-full p-1 text-muted-foreground hover:bg-muted"><ArrowLeft className="h-5 w-5" /></Link>
        <div>
          <h1 className="text-xl font-bold flex items-center gap-2">
            <Crown className="h-5 w-5 text-primary" /> REX Admin
          </h1>
          <p className="text-xs text-muted-foreground">Live KPIs · refreshes every 60s</p>
        </div>
      </div>

      <Section title="Users & growth" icon={<Users className="h-4 w-4" />}>
        <div className="grid grid-cols-2 gap-2">
          <Kpi label="Total users" value={u?.total_users} big />
          <Kpi label="Signups · 24h" value={u?.new_24h} accent />
          <Kpi label="Signups · 7d" value={u?.new_7d} />
          <Kpi label="Signups · 30d" value={u?.new_30d} />
          <Kpi label="DAU" value={u?.dau} sub="posted a rec · 24h" />
          <Kpi label="WAU" value={u?.wau} sub="posted · 7d" />
          <Kpi label="MAU" value={u?.mau} sub="posted · 30d" />
          <Kpi label="WAU / MAU" value={ratio(u?.wau, u?.mau)} sub="stickiness" />
        </div>
      </Section>

      <Section title="Content activity" icon={<TrendingUp className="h-4 w-4" />}>
        <div className="grid grid-cols-2 gap-2">
          <Pair icon={<Sparkles className="h-4 w-4" />} label="Recommendations" total={c?.recs_total} recent={c?.recs_7d} />
          <Pair icon={<Megaphone className="h-4 w-4" />} label="Blasts" total={c?.blasts_total} recent={c?.blasts_7d} />
          <Pair icon={<MessageCircle className="h-4 w-4" />} label="Rec comments" total={c?.rec_comments_total} recent={c?.rec_comments_7d} />
          <Pair icon={<MessageCircle className="h-4 w-4" />} label="Blast comments" total={c?.blast_comments_total} recent={c?.blast_comments_7d} />
          <Pair icon={<Heart className="h-4 w-4" />} label="Likes" total={c?.likes_total} recent={c?.likes_7d} />
          <Pair icon={<Bookmark className="h-4 w-4" />} label="Saves" total={c?.saves_total} recent={c?.saves_7d} />
        </div>
      </Section>

      <Section title="Admin team" icon={<Crown className="h-4 w-4" />}>
        <div className="space-y-2">
          {(adminsQ.data ?? []).map((a) => (
            <Link
              key={a.id}
              to="/profile/$username"
              params={{ username: a.username }}
              className="flex items-center gap-3 rounded-xl border border-border bg-card p-3"
            >
              <div
                className="flex h-9 w-9 items-center justify-center rounded-full bg-primary text-xs font-semibold text-primary-foreground bg-cover bg-center"
                style={a.avatar_url ? { backgroundImage: `url(${a.avatar_url})` } : undefined}
              >
                {!a.avatar_url && (a.display_name || a.username || "?").slice(0, 1).toUpperCase()}
              </div>
              <div className="flex-1 min-w-0">
                <div className="text-sm font-semibold truncate">{a.display_name || a.username}</div>
                <div className="text-xs text-muted-foreground truncate">@{a.username}</div>
              </div>
              <Crown className="h-4 w-4 text-primary" />
            </Link>
          ))}
          {adminsQ.data?.length === 0 && (
            <p className="text-xs text-muted-foreground">No admins yet.</p>
          )}
          <p className="pt-2 text-[11px] text-muted-foreground">
            To add more admins, ask Lovable to run a migration granting them the <code>admin</code> role.
          </p>
        </div>
      </Section>
    </div>
  );
}

function Section({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="mb-6">
      <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold text-muted-foreground uppercase tracking-wide">
        {icon} {title}
      </h2>
      {children}
    </section>
  );
}

function Kpi({ label, value, sub, big, accent }: { label: string; value?: number | string; sub?: string; big?: boolean; accent?: boolean }) {
  return (
    <div className={cn(
      "rounded-xl border border-border bg-card p-3",
      accent && "border-primary/40 bg-primary/5",
      big && "col-span-2",
    )}>
      <div className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className={cn("mt-1 font-bold tabular-nums", big ? "text-3xl" : "text-2xl")}>
        {value ?? "—"}
      </div>
      {sub && <div className="mt-0.5 text-[11px] text-muted-foreground">{sub}</div>}
    </div>
  );
}

function Pair({ icon, label, total, recent }: { icon: React.ReactNode; label: string; total?: number; recent?: number }) {
  return (
    <div className="rounded-xl border border-border bg-card p-3">
      <div className="flex items-center gap-1.5 text-[11px] uppercase tracking-wide text-muted-foreground">
        {icon} {label}
      </div>
      <div className="mt-1 text-2xl font-bold tabular-nums">{total ?? "—"}</div>
      <div className="text-[11px] text-muted-foreground">
        <span className="text-primary font-semibold">+{recent ?? 0}</span> in last 7d
      </div>
    </div>
  );
}

function ratio(a?: number, b?: number) {
  if (!a || !b) return "—";
  return `${Math.round((a / b) * 100)}%`;
}
