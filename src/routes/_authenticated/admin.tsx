import { createFileRoute, Link, useRouteContext } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Crown, Users, TrendingUp, MessageCircle, Heart, Bookmark, Megaphone, Sparkles, ArrowLeft, Zap, Network, BarChart3 } from "lucide-react";
import { cn } from "@/lib/utils";
import { AdminTeamManager } from "@/components/AdminTeamManager";


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

  const engQ = useQuery({
    queryKey: ["admin-kpis-engagement"],
    enabled,
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await (supabase.rpc as any)("admin_kpis_engagement");
      if (error) throw error;
      return data as EngagementKpis;
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
  const e = engQ.data;

  return (
    <div className="px-4 pb-8 pt-20">
      <div className="mb-4 flex items-center gap-2">
        <Link to="/you" className="rounded-full p-1 text-muted-foreground hover:bg-muted"><ArrowLeft className="h-5 w-5" /></Link>
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

      <Section title="Activation & funnel" icon={<Zap className="h-4 w-4" />}>
        <div className="grid grid-cols-2 gap-2">
          <Kpi label="Activation rate" value={ratio(e?.activated_users, e?.total_users)} sub={`${e?.activated_users ?? 0} posted ≥1 rec`} accent />
          <Kpi label="Connected rate" value={ratio(e?.users_with_friend, e?.total_users)} sub={`${e?.users_with_friend ?? 0} have ≥1 friend`} />
          <Kpi label="Recs / active user" value={e?.recs_per_active_user} sub="depth of use" />
          <Kpi label="Avg crowns" value={e?.avg_rating} sub="rating quality" />
          <Kpi label="Recs with photo" value={ratio(e?.recs_with_photo, c?.recs_total)} sub="richness" />
          <Kpi label="Recs with note" value={ratio(e?.recs_with_note, c?.recs_total)} sub="richness" />
          <Kpi label="Blast answer rate" value={ratio(e?.blasts_answered, e?.blasts_total)} sub="asks with ≥1 reply" />
          <Kpi label="Places geocoded" value={ratio(e?.places_geocoded, e?.places_total)} sub="map coverage" />
        </div>
      </Section>

      <Section title="Social graph" icon={<Network className="h-4 w-4" />}>
        <div className="grid grid-cols-2 gap-2">
          <Kpi label="Friendships" value={e?.friendships_accepted} sub="accepted" />
          <Kpi label="Pending requests" value={e?.friendships_pending} />
          <Kpi label="Accept rate" value={e?.friend_accept_rate != null ? `${e.friend_accept_rate}%` : undefined} />
          <Kpi label="Avg friends / user" value={e?.avg_friends} />
          <Kpi label="Lists created" value={e?.lists_total} sub={`${e?.lists_published ?? 0} published`} />
          <Kpi label="Want-to saves" value={e?.wants_total} />
          <Kpi label="Catalog items" value={e?.items_total} />
          <Kpi label="Bulk imports" value={e?.imports_total} />
        </div>
      </Section>

      <Section title="Trends · last 8 weeks" icon={<BarChart3 className="h-4 w-4" />}>
        <div className="space-y-2">
          <Spark label="Signups per week" points={e?.signups_by_week} />
          <Spark label="Recs per week" points={e?.recs_by_week} />
        </div>
      </Section>

      <Section title="Category mix" icon={<Sparkles className="h-4 w-4" />}>
        <div className="rounded-xl border border-border bg-card p-3 space-y-1.5">
          {(e?.by_category ?? []).map((row) => (
            <div key={row.type} className="flex items-center gap-2">
              <div className="w-20 shrink-0 text-xs capitalize">{row.type}</div>
              <div className="h-2 flex-1 overflow-hidden rounded-full bg-muted">
                <div
                  className="h-full rounded-full bg-primary"
                  style={{ width: `${pct(row.count, e?.by_category)}%` }}
                />
              </div>
              <div className="w-8 text-right text-xs tabular-nums text-muted-foreground">{row.count}</div>
            </div>
          ))}
          {(e?.by_category?.length ?? 0) === 0 && <p className="text-xs text-muted-foreground">No recommendations yet.</p>}
        </div>
      </Section>

      <Section title="Top contributors" icon={<TrendingUp className="h-4 w-4" />}>
        <div className="rounded-xl border border-border bg-card p-3 space-y-2">
          {(e?.top_contributors ?? []).map((t, i) => (
            <Link
              key={t.username}
              to="/profile/$username"
              params={{ username: t.username }}
              className="flex items-center gap-2 text-sm"
            >
              <span className="w-4 text-xs text-muted-foreground tabular-nums">{i + 1}</span>
              <span className="flex-1 truncate font-medium">{t.display_name || t.username}</span>
              <span className="text-xs tabular-nums text-muted-foreground">{t.count} recs</span>
            </Link>
          ))}
          {(e?.top_contributors?.length ?? 0) === 0 && <p className="text-xs text-muted-foreground">No data yet.</p>}
        </div>
      </Section>



      <Section title="Admin team" icon={<Crown className="h-4 w-4" />}>
        <AdminTeamManager currentUserId={user?.id} />
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

function pct(count: number, rows?: { count: number }[]) {
  const max = Math.max(1, ...(rows ?? []).map((r) => r.count));
  return Math.max(4, Math.round((count / max) * 100));
}

function Spark({ label, points }: { label: string; points?: { week: string; count: number }[] }) {
  const data = points ?? [];
  const max = Math.max(1, ...data.map((d) => d.count));
  return (
    <div className="rounded-xl border border-border bg-card p-3">
      <div className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</div>
      {data.length === 0 ? (
        <p className="mt-2 text-xs text-muted-foreground">No data yet.</p>
      ) : (
        <div className="mt-2 flex h-16 items-end gap-1">
          {data.map((d) => (
            <div key={d.week} className="flex flex-1 flex-col items-center gap-1">
              <div
                className="w-full rounded-t bg-primary/70"
                style={{ height: `${Math.max(6, (d.count / max) * 100)}%` }}
                title={`${d.week}: ${d.count}`}
              />
              <span className="text-[9px] text-muted-foreground">{d.week.slice(5)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
