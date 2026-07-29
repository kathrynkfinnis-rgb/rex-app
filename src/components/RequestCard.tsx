import { Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { formatDistanceToNow } from "date-fns";
import { MessageCircle, Sparkles } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { UserAvatar } from "@/components/UserAvatar";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { cn } from "@/lib/utils";

export type RequestRow = {
  id: string;
  user_id: string;
  type: ItemType | null;
  title: string;
  note: string | null;
  created_at: string;
  profiles: {
    username: string;
    display_name: string | null;
    avatar_url: string | null;
  } | null;
};

export function RequestCard({ req }: { req: RequestRow }) {
  const author = req.profiles;
  const cat = req.type ? categoryMeta(req.type) : null;
  const Icon = cat?.icon ?? Sparkles;

  const { data: count } = useQuery({
    queryKey: ["request-comments-count", req.id],
    queryFn: async () => {
      const { count } = await supabase
        .from("request_comments")
        .select("id", { count: "exact", head: true })
        .eq("request_id", req.id);
      return count ?? 0;
    },
    staleTime: 30_000,
  });

  return (
    <Link
      to="/ask/$id"
      params={{ id: req.id }}
      className="relative block overflow-hidden rounded-2xl bg-gradient-to-br from-accent/15 via-card to-card p-4 shadow-sm ring-1 ring-accent/40 transition-transform active:scale-[0.99]"
    >
      <div className="flex items-center gap-2">
        <span className="inline-flex items-center gap-1 rounded-full bg-accent/20 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-widest text-accent-foreground">
          <Sparkles className="h-3 w-3" /> Asking
        </span>
        {cat && (
          <span className={cn("inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider", cat.tokenClass)}>
            <Icon className="h-3 w-3" /> {cat.label}
          </span>
        )}
      </div>

      <h3 className="mt-2 font-display text-xl leading-snug">{req.title}</h3>
      {req.note && <p className="mt-1 text-sm leading-snug text-muted-foreground">{req.note}</p>}

      <div className="mt-3 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <UserAvatar url={author?.avatar_url} name={author?.display_name || author?.username} size="sm" />
          <div className="text-xs">
            <span className="font-medium">{author?.display_name || author?.username}</span>
            <span className="text-muted-foreground"> · {formatDistanceToNow(new Date(req.created_at), { addSuffix: true })}</span>
          </div>
        </div>
        <span className="inline-flex items-center gap-1 rounded-full bg-background/60 px-2.5 py-1 text-xs font-medium text-muted-foreground ring-1 ring-border">
          <MessageCircle className="h-3.5 w-3.5" /> {count ?? 0}
        </span>
      </div>
    </Link>
  );
}
