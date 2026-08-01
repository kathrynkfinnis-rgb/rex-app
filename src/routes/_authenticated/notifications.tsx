import { createFileRoute, Link, useRouteContext } from "@tanstack/react-router";
import { useEffect } from "react";
import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import { formatDistanceToNow } from "date-fns";
import { supabase } from "@/integrations/supabase/client";
import { UserAvatar } from "@/components/UserAvatar";
import { Button } from "@/components/ui/button";
import { Settings, CheckCheck, Bell } from "lucide-react";
import { notifCopy, notifTarget, type NotificationRow } from "@/lib/notifications";

export const Route = createFileRoute("/_authenticated/notifications")({
  head: () => ({
    meta: [
      { title: "Notifications — REX" },
      { name: "description", content: "See who's engaging with your Rex and blasts." },
    ],
  }),
  component: NotificationsPage,
});

function NotificationsPage() {
  const { user } = useRouteContext({ from: "/_authenticated" });
  const qc = useQueryClient();

  const { data: items = [], isLoading } = useQuery({
    queryKey: ["notifications", user.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("notifications")
        .select("id, user_id, actor_id, type, entity_type, entity_id, data, read_at, created_at, actor:profiles!notifications_actor_id_fkey(username, display_name, avatar_url)")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(100);
      if (error) {
        // Fallback: no FK on actor — fetch actors separately
        const base = await supabase
          .from("notifications")
          .select("id, user_id, actor_id, type, entity_type, entity_id, data, read_at, created_at")
          .eq("user_id", user.id)
          .order("created_at", { ascending: false })
          .limit(100);
        if (base.error) throw base.error;
        const rows = (base.data ?? []) as unknown as NotificationRow[];
        const actorIds = Array.from(new Set(rows.map((r) => r.actor_id).filter(Boolean))) as string[];
        if (actorIds.length) {
          const { data: profs } = await supabase
            .from("profiles")
            .select("id, username, display_name, avatar_url")
            .in("id", actorIds);
          const byId = new Map((profs ?? []).map((p: any) => [p.id, p]));
          for (const r of rows) r.actor = r.actor_id ? (byId.get(r.actor_id) as any) : null;
        }
        return rows;
      }
      return (data ?? []) as unknown as NotificationRow[];
    },
  });

  useEffect(() => {
    // Mark all read on view
    const unread = items.filter((n) => !n.read_at).map((n) => n.id);
    if (unread.length === 0) return;
    supabase
      .from("notifications")
      .update({ read_at: new Date().toISOString() })
      .in("id", unread)
      .then(() => {
        qc.invalidateQueries({ queryKey: ["notif-unread", user.id] });
      });
  }, [items, qc, user.id]);

  const clearAll = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from("notifications").delete().eq("user_id", user.id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["notifications", user.id] });
      qc.invalidateQueries({ queryKey: ["notif-unread", user.id] });
    },
  });

  return (
    <div className="px-4 pb-24 pt-20">
      <div className="mb-4 flex items-center justify-between">
        <h1 className="text-2xl font-bold">Notifications</h1>
        <Link
          to="/notification-settings"
          className="flex h-9 w-9 items-center justify-center rounded-full bg-card text-foreground"
          aria-label="Notification settings"
        >
          <Settings className="h-4 w-4" />
        </Link>
      </div>

      {isLoading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : items.length === 0 ? (
        <div className="mt-16 flex flex-col items-center gap-3 text-center">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-card">
            <Bell className="h-7 w-7 text-muted-foreground" />
          </div>
          <p className="font-semibold">You're all caught up</p>
          <p className="max-w-xs text-sm text-muted-foreground">
            When friends comment, like, or send you a blast you'll see it here.
          </p>
          <Link to="/notification-settings" className="mt-2 text-sm text-primary underline">
            Notification settings
          </Link>
        </div>
      ) : (
        <>
          <ul className="space-y-2">
            {items.map((n) => {
              const target = notifTarget(n);
              return (
              <li key={n.id}>
                <Link
                  {...(target as any)}
                  className={`flex items-start gap-3 rounded-2xl p-3 transition-colors ${
                    n.read_at ? "bg-card/60" : "bg-card ring-1 ring-primary/30"
                  }`}
                >
                  <UserAvatar
                    url={n.actor?.avatar_url ?? null}
                    name={n.actor?.display_name || n.actor?.username || "?"}
                    size="md"
                  />
                  <div className="min-w-0 flex-1">
                    <p className="line-clamp-3 text-sm">{notifCopy(n)}</p>
                    <p className="mt-0.5 text-[11px] text-muted-foreground">
                      {formatDistanceToNow(new Date(n.created_at), { addSuffix: true })}
                    </p>
                  </div>
                  {!n.read_at && <span className="mt-1 h-2 w-2 shrink-0 rounded-full bg-primary" />}
                </Link>
              </li>
              );
            })}
          </ul>
          <div className="mt-6 flex justify-center">
            <Button variant="ghost" size="sm" onClick={() => clearAll.mutate()} disabled={clearAll.isPending}>
              <CheckCheck className="mr-2 h-4 w-4" /> Clear all
            </Button>
          </div>
        </>
      )}
    </div>
  );
}
