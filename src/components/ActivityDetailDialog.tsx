import { useQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { formatDistanceToNow } from "date-fns";
import { supabase } from "@/integrations/supabase/client";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { Sparkles } from "lucide-react";
import { UserAvatar } from "@/components/UserAvatar";
import { categoryMeta, type ItemType } from "@/lib/categories";

export type ActivityKind =
  | "recent"
  | "comments"
  | "likes"
  | "wants"
  | "blasts"
  | "friends";

export const ACTIVITY_TITLES: Record<ActivityKind, string> = {
  recent: "Your Rex — last 30 days",
  comments: "Comments you've left",
  likes: "Rex you've liked",
  wants: "Saved to collections",
  blasts: "Blasts you've posted",
  friends: "Your friends",
};

type Entry = {
  key: string;
  title: string;
  sub?: string | null;
  when?: string | null;
  icon?: React.ComponentType<{ className?: string }> | null;
  avatar?: { url: string | null; name: string | null } | null;
  to: string;
  params?: Record<string, string>;
};

function itemIcon(type?: string | null) {
  if (!type) return null;
  try {
    return categoryMeta(type as ItemType).icon ?? null;
  } catch {
    return null;
  }
}

async function loadEntries(kind: ActivityKind, uid: string): Promise<Entry[]> {
  if (kind === "recent") {
    const since = new Date(Date.now() - 30 * 864e5).toISOString();
    const { data, error } = await supabase
      .from("recommendations")
      .select("id, created_at, rating, items!inner(title, type)")
      .eq("user_id", uid)
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(100);
    if (error) throw error;
    return (data ?? []).map((r: any) => ({
      key: r.id,
      title: r.items?.title ?? "Rex",
      sub: `${r.rating}/10 crowns`,
      when: r.created_at,
      icon: itemIcon(r.items?.type),
      to: "/r/$id",
      params: { id: r.id },
    }));
  }

  if (kind === "comments") {
    const { data, error } = await supabase
      .from("recommendation_comments")
      .select("id, body, created_at, recommendation_id, recommendations!inner(items!inner(title, type))")
      .eq("user_id", uid)
      .order("created_at", { ascending: false })
      .limit(100);
    if (error) throw error;
    return (data ?? []).map((c: any) => ({
      key: c.id,
      title: c.recommendations?.items?.title ?? "Rex",
      sub: c.body,
      when: c.created_at,
      icon: itemIcon(c.recommendations?.items?.type),
      to: "/r/$id",
      params: { id: c.recommendation_id },
    }));
  }

  if (kind === "likes") {
    const { data, error } = await supabase
      .from("recommendation_likes")
      .select("id, created_at, recommendation_id, recommendations!inner(rating, items!inner(title, type))")
      .eq("user_id", uid)
      .order("created_at", { ascending: false })
      .limit(100);
    if (error) throw error;
    return (data ?? []).map((l: any) => ({
      key: l.id,
      title: l.recommendations?.items?.title ?? "Rex",
      sub: l.recommendations ? `${l.recommendations.rating}/10 crowns` : null,
      when: l.created_at,
      icon: itemIcon(l.recommendations?.items?.type),
      to: "/r/$id",
      params: { id: l.recommendation_id },
    }));
  }

  if (kind === "wants") {
    const { data, error } = await supabase
      .from("wants")
      .select("id, created_at, item_id, items!inner(title, subtitle, type)")
      .eq("user_id", uid)
      .order("created_at", { ascending: false })
      .limit(100);
    if (error) throw error;
    return (data ?? []).map((w: any) => ({
      key: w.id,
      title: w.items?.title ?? "Item",
      sub: w.items?.subtitle,
      when: w.created_at,
      icon: itemIcon(w.items?.type),
      to: "/item/$id",
      params: { id: w.item_id },
    }));
  }

  if (kind === "blasts") {
    const { data, error } = await supabase
      .from("requests")
      .select("id, title, note, created_at")
      .eq("user_id", uid)
      .order("created_at", { ascending: false })
      .limit(100);
    if (error) throw error;
    return (data ?? []).map((b: any) => ({
      key: b.id,
      title: b.title,
      sub: b.note,
      when: b.created_at,
      to: "/ask/$id",
      params: { id: b.id },
    }));
  }

  const { data: fs, error } = await supabase
    .from("friendships")
    .select("id, requester_id, addressee_id, updated_at")
    .eq("status", "accepted")
    .or(`requester_id.eq.${uid},addressee_id.eq.${uid}`);
  if (error) throw error;
  const ids = (fs ?? []).map((f) => (f.requester_id === uid ? f.addressee_id : f.requester_id));
  if (ids.length === 0) return [];
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, username, display_name, avatar_url")
    .in("id", ids);
  return (profiles ?? []).map((p) => ({
    key: p.id,
    title: p.display_name || p.username,
    sub: `@${p.username}`,
    avatar: { url: p.avatar_url, name: p.display_name || p.username },
    to: "/profile/$username",
    params: { username: p.username },
  }));
}

export function ActivityDetailDialog({
  kind,
  userId,
  onClose,
}: {
  kind: ActivityKind | null;
  userId: string | undefined;
  onClose: () => void;
}) {
  const { data, isLoading } = useQuery({
    queryKey: ["activity-detail", kind, userId],
    enabled: !!kind && !!userId,
    queryFn: () => loadEntries(kind!, userId!),
  });

  return (
    <Dialog open={!!kind} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[80vh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{kind ? ACTIVITY_TITLES[kind] : ""}</DialogTitle>
          <DialogDescription className="sr-only">Activity details</DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="space-y-2">
            {[0, 1, 2].map((i) => (
              <div key={i} className="h-14 animate-pulse rounded-xl bg-muted" />
            ))}
          </div>
        ) : (data?.length ?? 0) === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">Nothing here yet.</p>
        ) : (
          <ul className="space-y-1.5">
            {data!.map((e) => (
              <li key={e.key}>
                <Link
                  to={e.to as any}
                  params={e.params as any}
                  onClick={onClose}
                  className="flex items-start gap-2.5 rounded-xl bg-secondary/50 px-3 py-2.5 transition-colors hover:bg-secondary"
                >
                  {e.avatar ? (
                    <UserAvatar url={e.avatar.url} name={e.avatar.name} size="xs" className="mt-0.5" />
                  ) : e.icon ? (
                    <e.icon className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
                  ) : (
                    <Sparkles className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
                  )}
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold">{e.title}</p>
                    {e.sub && (
                      <p className="line-clamp-2 text-xs text-muted-foreground">{e.sub}</p>
                    )}
                  </div>
                  {e.when && (
                    <span className="shrink-0 pt-0.5 text-[10px] text-muted-foreground">
                      {formatDistanceToNow(new Date(e.when), { addSuffix: true })}
                    </span>
                  )}
                </Link>
              </li>
            ))}
          </ul>
        )}
      </DialogContent>
    </Dialog>
  );
}
