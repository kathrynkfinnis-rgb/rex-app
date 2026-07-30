import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Bookmark, BookmarkCheck } from "lucide-react";
import { toast } from "sonner";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { cn } from "@/lib/utils";
import { AddToListDialog } from "@/components/AddToListDialog";

export function WantButton({
  itemId,
  itemType,
  itemTitle,
  className,
}: {
  itemId: string;
  itemType: ItemType;
  itemTitle?: string;
  className?: string;
}) {
  const qc = useQueryClient();
  const [busy, setBusy] = useState(false);
  const [pickerOpen, setPickerOpen] = useState(false);
  const cat = categoryMeta(itemType);
  const verb = cat.wantVerb;

  const { data: userRes } = useQuery({
    queryKey: ["me"],
    queryFn: async () => (await supabase.auth.getUser()).data.user,
  });
  const uid = userRes?.id;

  const { data: want } = useQuery({
    queryKey: ["want", itemId, uid],
    queryFn: async () => {
      if (!uid) return null;
      const { data } = await supabase
        .from("wants")
        .select("id, list_id")
        .eq("user_id", uid)
        .eq("item_id", itemId)
        .maybeSingle();
      return (data ?? null) as { id: string; list_id: string | null } | null;
    },
    enabled: !!uid,
  });

  const active = !!want;

  async function quickAdd() {
    if (!uid || busy) return;
    setBusy(true);
    try {
      const { error } = await supabase.from("wants").insert({ user_id: uid, item_id: itemId });
      if (error) throw error;
      await qc.invalidateQueries({ queryKey: ["want", itemId, uid] });
      qc.invalidateQueries({ queryKey: ["my-wants", uid] });
      setPickerOpen(true);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Couldn't save");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Button
        type="button"
        onClick={() => (active ? setPickerOpen(true) : quickAdd())}
        disabled={busy}
        variant="outline"
        className={cn(
          "h-11 w-full gap-2 rounded-full",
          active ? "border-primary bg-primary/10 text-primary hover:bg-primary/15" : "",
          className,
        )}
      >
        {active ? <BookmarkCheck className="h-4 w-4" /> : <Bookmark className="h-4 w-4" />}
        {active ? "On your collection — change" : verb}
      </Button>

      <AddToListDialog
        open={pickerOpen}
        onOpenChange={setPickerOpen}
        kind="want"
        entryId={want?.id ?? null}
        currentListId={want?.list_id ?? null}
        itemType={itemType}
        title={itemTitle}
      />
    </>
  );
}
