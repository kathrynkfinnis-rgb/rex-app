import { Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { Crown } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { UserAvatar } from "@/components/UserAvatar";

export type TopRexxer = {
  user_id: string;
  username: string;
  display_name: string | null;
  avatar_url: string | null;
  rex_count: number;
};

export function useTopRexxers() {
  return useQuery({
    queryKey: ["top-rexxers"],
    staleTime: 5 * 60 * 1000,
    queryFn: async (): Promise<TopRexxer[]> => {
      const { data, error } = await (supabase as any).rpc("top_rexxers_weekly", { _limit: 5 });
      if (error) throw error;
      return (data ?? []) as TopRexxer[];
    },
  });
}

/** Small crown shown next to a top-5 weekly contributor's name. */
export function TopRexxerCrown({ userId, className = "" }: { userId: string; className?: string }) {
  const { data } = useTopRexxers();
  const rank = (data ?? []).findIndex((r) => r.user_id === userId);
  if (rank < 0) return null;
  return (
    <Crown
      className={`h-3.5 w-3.5 shrink-0 fill-amber-400 text-amber-500 ${className}`}
      aria-label={`Top Rexxer this week (#${rank + 1})`}
    />
  );
}

export function TopRexxersCard() {
  const { data, isLoading } = useTopRexxers();
  const rows = data ?? [];
  if (isLoading || rows.length === 0) return null;

  return (
    <div className="rounded-2xl bg-card p-3 ring-1 ring-border">
      <div className="mb-2 flex items-center gap-1.5">
        <Crown className="h-4 w-4 fill-amber-400 text-amber-500" />
        <h2 className="text-sm font-semibold">Top Rexxers this week</h2>
      </div>
      <ul className="space-y-1.5">
        {rows.map((r, i) => (
          <li key={r.user_id}>
            <Link
              to="/profile/$username"
              params={{ username: r.username }}
              className="flex items-center gap-2 rounded-xl px-1 py-1 hover:bg-muted"
            >
              <span className="w-4 shrink-0 text-center text-xs font-semibold text-muted-foreground">{i + 1}</span>
              <UserAvatar url={r.avatar_url} name={r.display_name || r.username} size="xs" />
              <span className="min-w-0 flex-1 truncate text-sm font-medium">
                {r.display_name || r.username}
              </span>
              {i === 0 && <Crown className="h-3.5 w-3.5 fill-amber-400 text-amber-500" />}
              <span className="shrink-0 text-xs text-muted-foreground">
                {r.rex_count} Rex{Number(r.rex_count) === 1 ? "" : "es"}
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
