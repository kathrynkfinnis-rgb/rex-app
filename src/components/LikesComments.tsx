import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Heart, MessageCircle, Send, Trash2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { formatDistanceToNow } from "date-fns";
import { toast } from "sonner";

type CommentRow = {
  id: string;
  body: string;
  created_at: string;
  user_id: string;
  profiles: { username: string; display_name: string | null; avatar_url: string | null } | null;
};
type LikeRow = { id: string; user_id: string };

export function LikesComments({
  recommendationId,
  compact = false,
  autoOpenComments = false,
}: {
  recommendationId: string;
  compact?: boolean;
  autoOpenComments?: boolean;
}) {
  const qc = useQueryClient();
  const [open, setOpen] = useState(autoOpenComments);
  const [body, setBody] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const { data: uid } = useQuery({
    queryKey: ["me-id"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    staleTime: Infinity,
  });

  const likesKey = ["rec-likes", recommendationId];
  const commentsKey = ["rec-comments", recommendationId];

  const { data: likes = [] } = useQuery({
    queryKey: likesKey,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("recommendation_likes")
        .select("id, user_id")
        .eq("recommendation_id", recommendationId);
      if (error) throw error;
      return (data ?? []) as LikeRow[];
    },
  });

  const { data: comments = [] } = useQuery({
    queryKey: commentsKey,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("recommendation_comments")
        .select("id, body, created_at, user_id, profiles!recommendation_comments_user_id_fkey(username, display_name, avatar_url)")
        .eq("recommendation_id", recommendationId)
        .order("created_at", { ascending: true });
      if (error) throw error;
      return (data ?? []) as unknown as CommentRow[];
    },
    enabled: open || !compact,
  });

  const myLike = likes.find((l) => l.user_id === uid);
  const liked = !!myLike;

  async function toggleLike(e?: React.MouseEvent) {
    e?.preventDefault();
    e?.stopPropagation();
    if (!uid) return;
    try {
      if (liked) {
        const { error } = await supabase.from("recommendation_likes").delete().eq("id", myLike!.id);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from("recommendation_likes")
          .insert({ recommendation_id: recommendationId, user_id: uid });
        if (error) throw error;
      }
      qc.invalidateQueries({ queryKey: likesKey });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Couldn't update like");
    }
  }

  async function postComment() {
    if (!uid || !body.trim()) return;
    setSubmitting(true);
    try {
      const { error } = await supabase
        .from("recommendation_comments")
        .insert({ recommendation_id: recommendationId, user_id: uid, body: body.trim() });
      if (error) throw error;
      setBody("");
      qc.invalidateQueries({ queryKey: commentsKey });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Couldn't post");
    } finally {
      setSubmitting(false);
    }
  }

  async function deleteComment(id: string) {
    try {
      const { error } = await supabase.from("recommendation_comments").delete().eq("id", id);
      if (error) throw error;
      qc.invalidateQueries({ queryKey: commentsKey });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Couldn't delete");
    }
  }

  return (
    <div className={cn(compact ? "px-4 py-2" : "px-0 py-0")}>
      <div className="flex items-center gap-4 text-sm">
        <button
          type="button"
          onClick={toggleLike}
          className={cn(
            "inline-flex items-center gap-1.5 rounded-full py-1 pr-1 transition-colors",
            liked ? "text-primary" : "text-muted-foreground hover:text-foreground",
          )}
          aria-pressed={liked}
          aria-label={liked ? "Unlike" : "Like"}
        >
          <Heart className={cn("h-4 w-4", liked && "fill-current")} />
          <span className="tabular-nums font-medium">{likes.length}</span>
        </button>
        <button
          type="button"
          onClick={(e) => {
            e.preventDefault();
            e.stopPropagation();
            setOpen((v) => !v);
          }}
          className="inline-flex items-center gap-1.5 rounded-full py-1 text-muted-foreground hover:text-foreground"
        >
          <MessageCircle className="h-4 w-4" />
          <span className="tabular-nums font-medium">{comments.length}</span>
        </button>
      </div>

      {(open || !compact) && (
        <div className={cn("mt-2 space-y-2", compact && "border-t border-border pt-3")}>
          {comments.map((c) => (
            <div key={c.id} className="flex items-start gap-2 rounded-xl bg-secondary/40 px-3 py-2">
              <div className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-secondary text-[11px] font-semibold">
                {(c.profiles?.display_name || c.profiles?.username || "?").slice(0, 1).toUpperCase()}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline gap-1.5">
                  <span className="text-xs font-semibold">
                    {c.profiles?.display_name || c.profiles?.username || "Someone"}
                  </span>
                  <span className="text-[10px] text-muted-foreground">
                    {formatDistanceToNow(new Date(c.created_at), { addSuffix: true })}
                  </span>
                </div>
                <p className="text-sm leading-snug whitespace-pre-wrap break-words">{c.body}</p>
              </div>
              {c.user_id === uid && (
                <button
                  type="button"
                  onClick={(e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    deleteComment(c.id);
                  }}
                  className="text-muted-foreground hover:text-destructive"
                  aria-label="Delete comment"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              )}
            </div>
          ))}

          <form
            onSubmit={(e) => {
              e.preventDefault();
              e.stopPropagation();
              postComment();
            }}
            onClick={(e) => e.stopPropagation()}
            className="flex items-center gap-2"
          >
            <input
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder="Add a comment…"
              maxLength={1000}
              className="min-w-0 flex-1 rounded-full border border-border bg-background px-4 py-2 text-sm outline-none focus:border-primary"
            />
            <button
              type="submit"
              disabled={submitting || !body.trim()}
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground disabled:opacity-40"
              aria-label="Post comment"
            >
              <Send className="h-4 w-4" />
            </button>
          </form>
        </div>
      )}
    </div>
  );
}
