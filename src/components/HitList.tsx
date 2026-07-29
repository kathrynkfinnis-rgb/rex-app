import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Lock, MoreHorizontal, Plus, Trash2, Users, Globe2, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { CATEGORIES, categoryMeta, type ItemType } from "@/lib/categories";
import { toast } from "sonner";
import type { FeedRow } from "@/components/RecommendationCard";

type Visibility = "draft" | "friends" | "public";
type ItemLite = { id: string; type: ItemType; title: string; subtitle: string | null; image_url: string | null };
type WantRow = { id: string; item_id: string; list_id: string | null; items: ItemLite };
type SavedRow = { id: string; list_id: string | null; recommendations: FeedRow };
type ListRow = { id: string; user_id: string; item_type: ItemType; name: string; emoji: string | null; visibility: Visibility };

type Entry =
  | { kind: "want"; id: string; itemType: ItemType; title: string; image: string | null; href: string; params: any; listId: string | null }
  | { kind: "saved"; id: string; itemType: ItemType; title: string; image: string | null; href: string; params: any; listId: string | null };

const VISIBILITY_META: Record<Visibility, { label: string; icon: typeof Lock; hint: string }> = {
  draft: { label: "Draft", icon: Lock, hint: "Only you" },
  friends: { label: "Friends", icon: Users, hint: "Visible to your friends" },
  public: { label: "Public", icon: Globe2, hint: "Anyone on REX (friends can share on)" },
};

export function HitList({ userId }: { userId: string }) {
  const qc = useQueryClient();
  const [newListFor, setNewListFor] = useState<ItemType | null>(null);
  const [newName, setNewName] = useState("");
  const [newEmoji, setNewEmoji] = useState("");
  const [newVisibility, setNewVisibility] = useState<Visibility>("draft");

  const { data: wants } = useQuery({
    queryKey: ["my-wants", userId],
    queryFn: async () => {
      const { data } = await supabase
        .from("wants")
        .select("id, item_id, list_id, items!inner(id, type, title, subtitle, image_url)")
        .eq("user_id", userId)
        .order("created_at", { ascending: false });
      return (data ?? []) as unknown as WantRow[];
    },
  });

  const { data: saved } = useQuery({
    queryKey: ["my-saved-posts", userId],
    queryFn: async () => {
      const { data } = await supabase
        .from("saved_posts")
        .select("id, list_id, recommendations!inner(id, rating, note, created_at, photo_url, photo_urls, user_id, item_id, items!inner(id, type, title, subtitle, image_url, genre), profiles!recommendations_user_id_fkey(username, display_name, avatar_url))")
        .eq("user_id", userId)
        .order("created_at", { ascending: false });
      return (data ?? []) as unknown as SavedRow[];
    },
  });

  const { data: lists } = useQuery({
    queryKey: ["my-hitlist-lists", userId],
    queryFn: async () => {
      const { data } = await supabase
        .from("hitlist_lists")
        .select("id, user_id, item_type, name, emoji, visibility")
        .eq("user_id", userId)
        .order("created_at", { ascending: true });
      return (data ?? []) as unknown as ListRow[];
    },
  });

  const entries: Entry[] = useMemo(() => {
    const out: Entry[] = [];
    for (const w of wants ?? []) {
      out.push({
        kind: "want",
        id: w.id,
        itemType: w.items.type,
        title: w.items.title,
        image: w.items.image_url,
        href: "/item/$id",
        params: { id: w.item_id },
        listId: w.list_id,
      });
    }
    for (const s of saved ?? []) {
      const item = s.recommendations.items;
      if (!item) continue;
      out.push({
        kind: "saved",
        id: s.id,
        itemType: item.type,
        title: item.title,
        image: item.image_url,
        href: "/r/$id",
        params: { id: s.recommendations.id },
        listId: s.list_id,
      });
    }
    return out;
  }, [wants, saved]);

  const byCategory = useMemo(() => {
    const map = new Map<ItemType, Entry[]>();
    for (const e of entries) {
      const arr = map.get(e.itemType) ?? [];
      arr.push(e);
      map.set(e.itemType, arr);
    }
    return map;
  }, [entries]);

  const listsByCategory = useMemo(() => {
    const m = new Map<ItemType, ListRow[]>();
    for (const l of lists ?? []) {
      const arr = m.get(l.item_type as ItemType) ?? [];
      arr.push(l);
      m.set(l.item_type as ItemType, arr);
    }
    return m;
  }, [lists]);

  const activeCategories = CATEGORIES.filter(
    (c) => (byCategory.get(c.type)?.length ?? 0) > 0 || (listsByCategory.get(c.type)?.length ?? 0) > 0,
  );

  async function moveEntry(entry: Entry, newListId: string | null) {
    const table = entry.kind === "want" ? "wants" : "saved_posts";
    const { error } = await supabase.from(table).update({ list_id: newListId }).eq("id", entry.id);
    if (error) return toast.error(error.message);
    qc.invalidateQueries({ queryKey: entry.kind === "want" ? ["my-wants", userId] : ["my-saved-posts", userId] });
  }

  async function removeEntry(entry: Entry) {
    const table = entry.kind === "want" ? "wants" : "saved_posts";
    const { error } = await supabase.from(table).delete().eq("id", entry.id);
    if (error) return toast.error(error.message);
    toast.success("Removed from My List");
    qc.invalidateQueries({ queryKey: entry.kind === "want" ? ["my-wants", userId] : ["my-saved-posts", userId] });
  }

  async function createList() {
    if (!newListFor || !newName.trim()) return;
    const { error } = await supabase.from("hitlist_lists").insert({
      user_id: userId,
      item_type: newListFor,
      name: newName.trim(),
      emoji: newEmoji.trim() || null,
      visibility: newVisibility,
    });
    if (error) return toast.error(error.message);
    toast.success("List created");
    setNewListFor(null);
    setNewName("");
    setNewEmoji("");
    setNewVisibility("draft");
    qc.invalidateQueries({ queryKey: ["my-hitlist-lists", userId] });
  }

  async function updateVisibility(list: ListRow, visibility: Visibility) {
    const { error } = await supabase.from("hitlist_lists").update({ visibility }).eq("id", list.id);
    if (error) return toast.error(error.message);
    toast.success(
      visibility === "draft"
        ? "List moved back to draft"
        : visibility === "friends"
        ? "Shared with friends"
        : "Published — anyone on REX can see it",
    );
    qc.invalidateQueries({ queryKey: ["my-hitlist-lists", userId] });
  }

  async function deleteList(list: ListRow) {
    const { error } = await supabase.from("hitlist_lists").delete().eq("id", list.id);
    if (error) return toast.error(error.message);
    toast.success("List deleted");
    qc.invalidateQueries({ queryKey: ["my-hitlist-lists", userId] });
    qc.invalidateQueries({ queryKey: ["my-wants", userId] });
    qc.invalidateQueries({ queryKey: ["my-saved-posts", userId] });
  }

  if (entries.length === 0 && (lists?.length ?? 0) === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        Nothing on your list yet — tap the bookmark on any post, or hit "Want to…" on an item page.
      </p>
    );
  }

  return (
    <div className="space-y-6">
      {activeCategories.map((cat) => {
        const all = byCategory.get(cat.type) ?? [];
        const subs = listsByCategory.get(cat.type) ?? [];
        const defaults = all.filter((e) => !e.listId);
        return (
          <div key={cat.type} className="space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="font-display text-lg">
                <span className="mr-2">{cat.hitDefaultEmoji}</span>
                {cat.hitDefaultLabel}{" "}
                <span className="text-sm text-muted-foreground">({defaults.length})</span>
              </h3>
              <Button
                variant="ghost"
                size="sm"
                className="h-8 gap-1 rounded-full text-xs"
                onClick={() => {
                  setNewListFor(cat.type);
                  setNewName("");
                  setNewEmoji("");
                  setNewVisibility("draft");
                }}
              >
                <Plus className="h-3.5 w-3.5" /> New list
              </Button>
            </div>

            <EntryList
              entries={defaults}
              lists={subs}
              cat={cat}
              onMove={moveEntry}
              onRemove={removeEntry}
            />

            {subs.map((list) => {
              const inList = all.filter((e) => e.listId === list.id);
              const VMeta = VISIBILITY_META[list.visibility];
              const VIcon = VMeta.icon;
              return (
                <div key={list.id} className="rounded-2xl border border-border bg-card/40 p-3">
                  <div className="mb-2 flex items-center justify-between gap-2">
                    <p className="min-w-0 truncate font-medium">
                      <span className="mr-1.5">{list.emoji ?? cat.hitDefaultEmoji}</span>
                      {list.name}{" "}
                      <span className="text-xs text-muted-foreground">({inList.length})</span>
                    </p>
                    <div className="flex items-center gap-1">
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <button
                            type="button"
                            className={cn(
                              "inline-flex items-center gap-1 rounded-full px-2 py-1 text-[11px] font-medium ring-1 ring-border",
                              list.visibility === "draft" && "bg-muted text-muted-foreground",
                              list.visibility === "friends" && "bg-primary/10 text-primary",
                              list.visibility === "public" && "bg-accent text-accent-foreground",
                            )}
                          >
                            <VIcon className="h-3 w-3" /> {VMeta.label}
                          </button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuLabel>Who can see this list</DropdownMenuLabel>
                          {(["draft", "friends", "public"] as Visibility[]).map((v) => {
                            const M = VISIBILITY_META[v];
                            const I = M.icon;
                            return (
                              <DropdownMenuItem key={v} onClick={() => updateVisibility(list, v)}>
                                <I className="mr-2 h-4 w-4" />
                                <span className="flex-1">
                                  {M.label}
                                  <span className="ml-1 text-xs text-muted-foreground">— {M.hint}</span>
                                </span>
                                {list.visibility === v ? <Check className="ml-2 h-3.5 w-3.5" /> : null}
                              </DropdownMenuItem>
                            );
                          })}
                        </DropdownMenuContent>
                      </DropdownMenu>
                      <button
                        type="button"
                        onClick={() => {
                          if (confirm(`Delete list "${list.name}"? Items go back to default.`)) deleteList(list);
                        }}
                        className="rounded-full p-1.5 text-muted-foreground hover:bg-muted hover:text-destructive"
                        aria-label="Delete list"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  </div>
                  {inList.length > 0 ? (
                    <EntryList
                      entries={inList}
                      lists={subs}
                      cat={cat}
                      onMove={moveEntry}
                      onRemove={removeEntry}
                    />
                  ) : (
                    <p className="text-xs text-muted-foreground">Empty — use ⋯ on an item to move it here.</p>
                  )}
                </div>
              );
            })}
          </div>
        );
      })}

      <Dialog open={!!newListFor} onOpenChange={(o) => !o && setNewListFor(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              New list{newListFor ? ` in ${categoryMeta(newListFor).plural}` : ""}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <label className="mb-1 block text-xs font-medium">Name</label>
              <Input
                autoFocus
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                placeholder="e.g. Tokyo list"
              />
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium">Emoji (optional)</label>
              <Input
                value={newEmoji}
                onChange={(e) => setNewEmoji(e.target.value)}
                placeholder="🏯"
                maxLength={4}
              />
            </div>
            <div>
              <label className="mb-1.5 block text-xs font-medium">Who can see it</label>
              <div className="grid grid-cols-3 gap-2">
                {(["draft", "friends", "public"] as Visibility[]).map((v) => {
                  const M = VISIBILITY_META[v];
                  const I = M.icon;
                  const active = newVisibility === v;
                  return (
                    <button
                      key={v}
                      type="button"
                      onClick={() => setNewVisibility(v)}
                      className={cn(
                        "flex flex-col items-center gap-1 rounded-xl border p-2 text-xs transition",
                        active ? "border-primary bg-primary/10 text-primary" : "border-border text-muted-foreground hover:bg-muted",
                      )}
                    >
                      <I className="h-4 w-4" />
                      <span className="font-medium">{M.label}</span>
                    </button>
                  );
                })}
              </div>
              <p className="mt-1.5 text-[11px] text-muted-foreground">{VISIBILITY_META[newVisibility].hint}</p>
            </div>
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setNewListFor(null)}>Cancel</Button>
            <Button onClick={createList} disabled={!newName.trim()}>Create</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function EntryList({
  entries,
  lists,
  cat,
  onMove,
  onRemove,
}: {
  entries: Entry[];
  lists: ListRow[];
  cat: (typeof CATEGORIES)[number];
  onMove: (entry: Entry, listId: string | null) => void;
  onRemove: (entry: Entry) => void;
}) {
  const Icon = cat.icon;
  if (entries.length === 0) return null;
  return (
    <div className="space-y-2">
      {entries.map((e) => (
        <div
          key={`${e.kind}-${e.id}`}
          className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border"
        >
          <Link
            to={e.href as any}
            params={e.params}
            className="flex min-w-0 flex-1 items-center gap-3"
          >
            <div className={cn("flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-xl", cat.tokenClass)}>
              {e.image ? (
                <img src={e.image} alt="" className="h-full w-full object-cover" />
              ) : (
                <Icon className="h-5 w-5" />
              )}
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate font-medium">{e.title}</p>
              <p className="truncate text-xs text-muted-foreground">
                {e.kind === "saved" ? "Saved post" : cat.wantVerb}
              </p>
            </div>
          </Link>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                aria-label="More"
                className="rounded-full p-2 text-muted-foreground hover:bg-muted"
              >
                <MoreHorizontal className="h-4 w-4" />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuLabel>Move to</DropdownMenuLabel>
              <DropdownMenuItem onClick={() => onMove(e, null)}>
                {cat.hitDefaultEmoji} {cat.hitDefaultLabel} (default)
              </DropdownMenuItem>
              {lists.map((l) => (
                <DropdownMenuItem key={l.id} onClick={() => onMove(e, l.id)}>
                  {l.emoji ?? cat.hitDefaultEmoji} {l.name}
                </DropdownMenuItem>
              ))}
              <DropdownMenuSeparator />
              <DropdownMenuItem className="text-destructive" onClick={() => onRemove(e)}>
                <Trash2 className="mr-2 h-4 w-4" /> Remove from My List
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      ))}
    </div>
  );
}
