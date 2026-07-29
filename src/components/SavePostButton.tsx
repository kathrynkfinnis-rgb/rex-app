import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Bookmark } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { cn } from "@/lib/utils";
import { toast } from "sonner";

export function SavePostButton({
  recommendationId,
  className,
}: {
  recommendationId: string;
  className?: string;
}) {
  const qc = useQueryClient();
  const { data: userId } = useQuery({
    queryKey: ["current-user-id"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    staleTime: 5 * 60 * 1000,
  });

  const { data: saved } = useQuery({
    queryKey: ["saved-post", recommendationId, userId],
    enabled: !!userId,
    queryFn: async () => {
      const { data } = await supabase
        .from("saved_posts")
        .select("id")
        .eq("recommendation_id", recommendationId)
        .eq("user_id", userId!)
        .maybeSingle();
      return !!data;
    },
  });

  const toggle = useMutation({
    mutationFn: async () => {
      if (!userId) throw new Error("Sign in to save");
      if (saved) {
        const { error } = await supabase
          .from("saved_posts")
          .delete()
          .eq("recommendation_id", recommendationId)
          .eq("user_id", userId);
        if (error) throw error;
        return false;
      }
      const { error } = await supabase
        .from("saved_posts")
        .insert({ recommendation_id: recommendationId, user_id: userId });
      if (error) throw error;
      return true;
    },
    onSuccess: (nowSaved) => {
      qc.setQueryData(["saved-post", recommendationId, userId], nowSaved);
      qc.invalidateQueries({ queryKey: ["my-saved-posts"] });
      toast.success(nowSaved ? "Saved" : "Removed from saves");
    },
    onError: (e: any) => toast.error(e.message || "Couldn't save"),
  });

  return (
    <button
      type="button"
      aria-label={saved ? "Unsave post" : "Save post"}
      aria-pressed={!!saved}
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        toggle.mutate();
      }}
      disabled={toggle.isPending}
      className={cn(
        "flex h-9 w-9 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-muted active:scale-95",
        saved && "text-primary",
        className
      )}
    >
      <Bookmark className={cn("h-5 w-5", saved && "fill-current")} />
    </button>
  );
}
