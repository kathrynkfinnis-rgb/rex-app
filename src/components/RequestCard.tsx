import { Link } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { formatDistanceToNow } from "date-fns";
import { MessageCircle, Sparkles, Trash2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { UserAvatar } from "@/components/UserAvatar";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { cn } from "@/lib/utils";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { toast } from "sonner";

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
  const qc = useQueryClient();
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);

  const { data: uid } = useQuery({
    queryKey: ["current-user-id"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    staleTime: 5 * 60 * 1000,
  });
  const isOwner = uid && uid === req.user_id;

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

  async function handleDelete() {
    setDeleting(true);
    const { error } = await supabase.from("requests").delete().eq("id", req.id);
    setDeleting(false);
    if (error) { toast.error(error.message); return; }
    toast.success("Blast deleted");
    setConfirmDelete(false);
    qc.invalidateQueries();
  }

  return (
    <>
    <Link
      to="/ask/$id"
      params={{ id: req.id }}
      className="relative block overflow-hidden rounded-2xl bg-gradient-to-br from-accent/15 via-card to-card p-4 shadow-sm ring-1 ring-accent/40 transition-transform active:scale-[0.99]"
    >
      {isOwner && (
        <button
          type="button"
          onClick={(e) => { e.preventDefault(); e.stopPropagation(); setConfirmDelete(true); }}
          className="absolute right-1.5 top-1.5 z-10 flex h-7 w-7 items-center justify-center rounded-full bg-background/80 text-muted-foreground shadow-sm ring-1 ring-border backdrop-blur hover:text-destructive"
          aria-label="Delete blast"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      )}
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
    <AlertDialog open={confirmDelete} onOpenChange={setConfirmDelete}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Delete this blast?</AlertDialogTitle>
          <AlertDialogDescription>
            This removes your ask and all replies. This can't be undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction
            onClick={(e) => { e.preventDefault(); handleDelete(); }}
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
          >
            {deleting ? "Deleting…" : "Delete"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
    </>
  );
}
