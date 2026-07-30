import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Check, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { categoryMeta, type ItemType } from "@/lib/categories";

type ListRow = { id: string; name: string; emoji: string | null; item_type: string };

/**
 * Lets a user file an already-saved entry into one of their lists.
 * The quick path (just save) has already happened — this is the "be specific" step.
 */
export function AddToListDialog({
  open,
  onOpenChange,
  kind,
  entryId,
  itemType,
  currentListId,
  title,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  kind: "saved" | "want";
  entryId: string | null;
  itemType: ItemType;
  currentListId: string | null;
  title?: string;
}) {
  const qc = useQueryClient();
  const cat = categoryMeta(itemType);
  const [creating, setCreating] = useState(false);
  const [newName, setNewName] = useState("");
  const [busy, setBusy] = useState(false);

  const { data: userId } = useQuery({
    queryKey: ["current-user-id"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    staleTime: 5 * 60 * 1000,
  });

  const { data: lists } = useQuery({
    queryKey: ["lists-for-type", userId, itemType],
    enabled: !!userId && open,
    queryFn: async () => {
      const { data } = await supabase
        .from("hitlist_lists")
        .select("id, name, emoji, item_type")
        .eq("user_id", userId!)
        .eq("item_type", itemType)
        .order("created_at", { ascending: true });
      return (data ?? []) as ListRow[];
    },
  });

  const table = kind === "want" ? "wants" : "saved_posts";

  function refresh() {
    qc.invalidateQueries({ queryKey: ["my-wants"] });
    qc.invalidateQueries({ queryKey: ["my-saved-posts"] });
    qc.invalidateQueries({ queryKey: ["my-hitlist-lists"] });
    qc.invalidateQueries({ queryKey: ["lists-for-type"] });
    qc.invalidateQueries({ queryKey: ["saved-post"] });
    qc.invalidateQueries({ queryKey: ["want"] });
  }

  async function moveTo(listId: string | null, label: string) {
    if (!entryId || busy) return;
    setBusy(true);
    const { error } = await supabase.from(table).update({ list_id: listId }).eq("id", entryId);
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success(`Saved to ${label}`);
    refresh();
    onOpenChange(false);
  }

  async function createAndMove() {
    if (!userId || !newName.trim() || busy) return;
    setBusy(true);
    const { data, error } = await supabase
      .from("hitlist_lists")
      .insert({ user_id: userId, item_type: itemType, name: newName.trim(), visibility: "draft" })
      .select("id, name")
      .single();
    if (error || !data) {
      setBusy(false);
      return toast.error(error?.message ?? "Couldn't create list");
    }
    setBusy(false);
    setCreating(false);
    setNewName("");
    await moveTo(data.id, data.name);
  }

  async function remove() {
    if (!entryId || busy) return;
    setBusy(true);
    const { error } = await supabase.from(table).delete().eq("id", entryId);
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success("Removed from My Lists");
    refresh();
    onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Add to a list</DialogTitle>
          <DialogDescription className="truncate">
            {title ? title : `Saved to your ${cat.label.toLowerCase()} list`}
          </DialogDescription>
        </DialogHeader>

        <div className="max-h-72 space-y-1.5 overflow-y-auto">
          <ListOption
            emoji={cat.hitDefaultEmoji}
            name={`${cat.hitDefaultLabel} (default)`}
            active={!currentListId}
            onClick={() => moveTo(null, cat.hitDefaultLabel)}
          />
          {(lists ?? []).map((l) => (
            <ListOption
              key={l.id}
              emoji={l.emoji ?? cat.hitDefaultEmoji}
              name={l.name}
              active={currentListId === l.id}
              onClick={() => moveTo(l.id, l.name)}
            />
          ))}
        </div>

        {creating ? (
          <div className="flex gap-2">
            <Input
              autoFocus
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              placeholder={`e.g. Tokyo ${cat.plural.toLowerCase()}`}
              onKeyDown={(e) => e.key === "Enter" && createAndMove()}
            />
            <Button onClick={createAndMove} disabled={!newName.trim() || busy}>
              Create
            </Button>
          </div>
        ) : (
          <Button variant="outline" className="w-full gap-1 rounded-full" onClick={() => setCreating(true)}>
            <Plus className="h-4 w-4" /> New list
          </Button>
        )}

        <button
          type="button"
          onClick={remove}
          disabled={busy}
          className="mx-auto flex items-center gap-1.5 text-xs text-muted-foreground hover:text-destructive"
        >
          <Trash2 className="h-3.5 w-3.5" /> Remove from My Lists
        </button>
      </DialogContent>
    </Dialog>
  );
}

function ListOption({
  emoji,
  name,
  active,
  onClick,
}: {
  emoji: string;
  name: string;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex w-full items-center gap-2 rounded-xl border border-border px-3 py-2.5 text-left text-sm transition-colors hover:bg-muted",
        active && "border-primary bg-primary/10",
      )}
    >
      <span>{emoji}</span>
      <span className="min-w-0 flex-1 truncate">{name}</span>
      {active ? <Check className="h-4 w-4 text-primary" /> : null}
    </button>
  );
}
