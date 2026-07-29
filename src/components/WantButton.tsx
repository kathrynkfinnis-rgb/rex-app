import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Bookmark, BookmarkCheck } from "lucide-react";
import { toast } from "sonner";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { cn } from "@/lib/utils";

export function WantButton({ itemId, itemType, className }: { itemId: string; itemType: ItemType; className?: string }) {
  const qc = useQueryClient();
  const [busy, setBusy] = useState(false);
  const verb = categoryMeta(itemType).wantVerb;

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
        .select("id")
        .eq("user_id", uid)
        .eq("item_id", itemId)
        .maybeSingle();
      return data;
    },
    enabled: !!uid,
  });

  const active = !!want;

  async function toggle() {
    if (!uid || busy) return;
    setBusy(true);
    try {
      if (active) {
        const { error } = await supabase.from("wants").delete().eq("user_id", uid).eq("item_id", itemId);
        if (error) throw error;
        toast.success("Removed from My List");
      } else {
        const { error } = await supabase.from("wants").insert({ user_id: uid, item_id: itemId });
        if (error) throw error;
        toast.success(`Added to My List — ${verb.toLowerCase()}`);
      }
      qc.invalidateQueries({ queryKey: ["want", itemId, uid] });
      qc.invalidateQueries({ queryKey: ["my-wants", uid] });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Couldn't save");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Button
      type="button"
      onClick={toggle}
      disabled={busy}
      variant="outline"
      className={cn(
        "h-11 w-full gap-2 rounded-full",
        active
          ? "border-primary bg-primary/10 text-primary hover:bg-primary/15"
          : "",
        className,
      )}
    >
      {active ? <BookmarkCheck className="h-4 w-4" /> : <Bookmark className="h-4 w-4" />}
      {active ? "On your list" : verb}
    </Button>
  );
}
