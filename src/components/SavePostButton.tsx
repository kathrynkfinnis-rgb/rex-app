import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Bookmark } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import { AddToListDialog } from "@/components/AddToListDialog";
import type { ItemType } from "@/lib/categories";

export function SavePostButton({
  recommendationId,
  itemType = "other",
  itemTitle,
  className,
}: {
  recommendationId: string;
  itemType?: ItemType;
  itemTitle?: string;
  className?: string;
}) {
  const qc = useQueryClient();
  const [pickerOpen, setPickerOpen] = useState(false);

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
        .select("id, list_id")
        .eq("recommendation_id", recommendationId)
        .eq("user_id", userId!)
        .maybeSingle();
      return (data ?? null) as { id: string; list_id: string | null } | null;
    },
  });

  const save = useMutation({
    mutationFn: async () => {
      if (!userId) throw new Error("Sign in to save");
      const { data, error } = await supabase
        .from("saved_posts")
        .insert({ recommendation_id: recommendationId, user_id: userId })
        .select("id, list_id")
        .single();
      if (error) throw error;
      return data as { id: string; list_id: string | null };
    },
    onSuccess: (row) => {
      qc.setQueryData(["saved-post", recommendationId, userId], row);
      qc.invalidateQueries({ queryKey: ["my-saved-posts"] });
      toast.success("Added to My Lists", {
        description: "Filed under your default list.",
        action: { label: "Choose list", onClick: () => setPickerOpen(true) },
      });
    },
    onError: (e: any) => toast.error(e.message || "Couldn't save"),
  });

  return (
    <>
      <button
        type="button"
        aria-label={saved ? "Change list" : "Save to My Lists"}
        aria-pressed={!!saved}
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          if (saved) setPickerOpen(true);
          else save.mutate();
        }}
        disabled={save.isPending}
        className={cn(
          "flex h-9 w-9 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-muted active:scale-95",
          saved && "text-primary",
          className,
        )}
      >
        <Bookmark className={cn("h-5 w-5", saved && "fill-current")} />
      </button>

      <AddToListDialog
        open={pickerOpen}
        onOpenChange={setPickerOpen}
        kind="saved"
        entryId={saved?.id ?? null}
        currentListId={saved?.list_id ?? null}
        itemType={itemType}
        title={itemTitle}
      />
    </>
  );
}
