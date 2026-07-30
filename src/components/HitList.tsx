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
import { CollaboratorStack, CollaboratorsDialog, type Collaborator } from "@/components/ListCollaborators";
import { UserAvatar } from "@/components/UserAvatar";

type Visibility = "draft" | "friends" | "public";
type ItemLite = { id: string; type: ItemType; title: string; subtitle: string | null; image_url: string | null };
type WantRow = { id: string; user_id: string; item_id: string; list_id: string | null; items: ItemLite };
type SavedRow = { id: string; user_id: string; list_id: string | null; recommendations: FeedRow };
type ListRow = { id: string; user_id: string; item_type: string; name: string; emoji: string | null; visibility: Visibility };
type Profile = { id: string; username: string; display_name: string | null; avatar_url: string | null };

type Entry = {
  kind: "want" | "saved";
  id: string;
  userId: string;
  itemType: ItemType;
  title: string;
  image: string | null;
  href: string;
  params: any;
  listId: string | null;
};

const VISIBILITY_META: Record<Visibility, { label: string; icon: typeof Lock; hint: string }> = {
  draft: { label: "Draft", icon: Lock, hint: "Only you" },
  friends: { label: "Friends", icon: Users, hint: "Visible to your friends" },
  public: { label: "Public", icon: Globe2, hint: "Anyone on REX (friends can share on)" },
};

const WANT_SELECT = "id, user_id, item_id, list_id, items!inner(id, type, title, subtitle, image_url)";
const SAVED_SELECT =
  "id, user_id, list_id, recommendations!inner(id, rating, note, created_at, photo_url, photo_urls, user_id, item_id, items!inner(id, type, title, subtitle, image_url, genre), profiles!recommendations_user_id_fkey(username, display_name, avatar_url))";

function dedupe<T extends { id: string }>(rows: T[]) {
  const m = new Map<string, T>();
  for (const r of rows) m.set(r.id, r);
  return [...m.values()];
}

export function HitList({ userId }: { userId: string }) {
  const qc = useQueryClient();
  const [newListFor, setNewListFor] = useState<string | null>(null);
  const [newName, setNewName] = useState("");
  const [newVisibility, setNewVisibility] = useState<Visibility>("draft");
  const [collabList, setCollabList] = useState<ListRow | null>(null);
  const [filter, setFilter] = useState<string>("all");

  const { data: lists } = useQuery({
    queryKey: ["my-hitlist-lists", userId],
    queryFn: async () => {
      const [own, shared] = await Promise.all([
        supabase
          .from("hitlist_lists")
          .select("id, user_id, item_type, name, emoji, visibility")
          .eq("user_id", userId)
          .order("created_at", { ascending: true }),
        supabase
          .from("list_collaborators")
          .select("hitlist_lists!inner(id, user_id, item_type, name, emoji, visibility)")
          .eq("user_id", userId),
      ]);
      const sharedLists = ((shared.data ?? []) as any[]).map((r) => r.hitlist_lists);
      return dedupe([...((own.data ?? []) as any[]), ...sharedLists]) as ListRow[];
    },
  });

  const listIds = useMemo(() => (lists ?? []).map((l) => l.id), [lists]);

  const { data: collaborators } = useQuery({
    queryKey: ["list-collaborators", userId, listIds.join(",")],
    enabled: listIds.length > 0,
    queryFn: async () => {
      const { data } = await supabase
        .from("list_collaborators")
        .select("id, list_id, user_id, profiles:user_id(id, username, display_name, avatar_url)")
        .in("list_id", listIds);
      return ((data ?? []) as any[]).map((r) => ({
        id: r.id,
        list_id: r.list_id,
        user_id: r.user_id,
        profile: (r.profiles ?? null) as Profile | null,
      })) as Collaborator[];
    },
  });

  const { data: wants } = useQuery({
    queryKey: ["my-wants", userId, listIds.join(",")],
    queryFn: async () => {
      const mine = await supabase
        .from("wants")
        .select(WANT_SELECT)
        .eq("user_id", userId)
        .order("created_at", { ascending: false });
      let sharedRows: any[] = [];
      if (listIds.length > 0) {
        const shared = await supabase
          .from("wants")
          .select(WANT_SELECT)
          .in("list_id", listIds)
          .order("created_at", { ascending: false });
        sharedRows = shared.data ?? [];
      }
      return dedupe([...((mine.data ?? []) as any[]), ...sharedRows]) as unknown as WantRow[];
    },
  });

  const { data: saved } = useQuery({
    queryKey: ["my-saved-posts", userId, listIds.join(",")],
    queryFn: async () => {
      const mine = await supabase
        .from("saved_posts")
        .select(SAVED_SELECT)
        .eq("user_id", userId)
        .order("created_at", { ascending: false });
      let sharedRows: any[] = [];
      if (listIds.length > 0) {
        const shared = await supabase
          .from("saved_posts")
          .select(SAVED_SELECT)
          .in("list_id", listIds)
          .order("created_at", { ascending: false });
        sharedRows = shared.data ?? [];
      }
      return dedupe([...((mine.data ?? []) as any[]), ...sharedRows]) as unknown as SavedRow[];
    },
  });

  const ownerIds = useMemo(() => [...new Set((lists ?? []).map((l) => l.user_id))], [lists]);
  const contributorIds = useMemo(
    () => [...new Set([...(wants ?? []).map((w) => w.user_id), ...(saved ?? []).map((s) => s.user_id), ...ownerIds])],
    [wants, saved, ownerIds],
  );

  const { data: people } = useQuery({
    queryKey: ["list-people", contributorIds.join(",")],
    enabled: contributorIds.length > 0,
    queryFn: async () => {
      const { data } = await supabase
        .from("profiles")
        .select("id, username, display_name, avatar_url")
        .in("id", contributorIds);
      const m = new Map<string, Profile>();
      for (const p of (data ?? []) as Profile[]) m.set(p.id, p);
      return m;
    },
  });

  const entries: Entry[] = useMemo(() => {
    const out: Entry[] = [];
    for (const w of wants ?? []) {
      out.push({
        kind: "want",
        id: w.id,
        userId: w.user_id,
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
        userId: s.user_id,
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

  const allLists = useMemo(() => lists ?? [], [lists]);

  const collabsByList = useMemo(() => {
    const m = new Map<string, Collaborator[]>();
    for (const c of collaborators ?? []) {
      const arr = m.get(c.list_id) ?? [];
      arr.push(c);
      m.set(c.list_id, arr);
    }
    return m;
  }, [collaborators]);

  const matchesFilter = (e: Entry) => filter === "all" || e.itemType === filter;

  const allActiveCategories = CATEGORIES.filter((c) => (byCategory.get(c.type)?.length ?? 0) > 0);
  const activeCategories =
    filter === "all" ? allActiveCategories : allActiveCategories.filter((c) => c.type === filter);



  function invalidateEntries() {
    qc.invalidateQueries({ queryKey: ["my-wants", userId] });
    qc.invalidateQueries({ queryKey: ["my-saved-posts", userId] });
  }

  async function moveEntry(entry: Entry, newListId: string | null) {
    const table = entry.kind === "want" ? "wants" : "saved_posts";
    const { error } = await supabase.from(table).update({ list_id: newListId }).eq("id", entry.id);
    if (error) return toast.error(error.message);
    invalidateEntries();
  }

  async function removeEntry(entry: Entry) {
    const table = entry.kind === "want" ? "wants" : "saved_posts";
    const { error } = await supabase.from(table).delete().eq("id", entry.id);
    if (error) return toast.error(error.message);
    toast.success("Removed from My Collections");
    invalidateEntries();
  }

  async function createList() {
    if (!newListFor || !newName.trim()) return;
    const { error } = await supabase.from("hitlist_lists").insert({
      user_id: userId,
      item_type: newListFor,
      name: newName.trim(),
      visibility: newVisibility,
    });
    if (error) return toast.error(error.message);
    toast.success("Collection created");
    setNewListFor(null);
    setNewName("");
    setNewVisibility("draft");
    qc.invalidateQueries({ queryKey: ["my-hitlist-lists", userId] });
  }

  async function updateVisibility(list: ListRow, visibility: Visibility) {
    const { error } = await supabase.from("hitlist_lists").update({ visibility }).eq("id", list.id);
    if (error) return toast.error(error.message);
    toast.success(
      visibility === "draft"
        ? "Collection moved back to draft"
        : visibility === "friends"
        ? "Shared with friends"
        : "Published — anyone on REX can see it",
    );
    qc.invalidateQueries({ queryKey: ["my-hitlist-lists", userId] });
  }

  async function deleteList(list: ListRow) {
    const { error } = await supabase.from("hitlist_lists").delete().eq("id", list.id);
    if (error) return toast.error(error.message);
    toast.success("Collection deleted");
    qc.invalidateQueries({ queryKey: ["my-hitlist-lists", userId] });
    invalidateEntries();
  }

  const isEmpty = entries.length === 0 && (lists?.length ?? 0) === 0;

  function startNewList() {
    setNewListFor("any");
    setNewName("");
    setNewVisibility("draft");
  }

  return (
    <div className="space-y-6">
      {!isEmpty && (
        <div className="sticky top-0 z-10 -mx-1 space-y-2 bg-background/90 px-1 py-2 backdrop-blur">
          <div className="flex flex-wrap gap-1.5">
            <FilterChip label="All" active={filter === "all"} onClick={() => setFilter("all")} />
            {allActiveCategories.map((c) => (
              <FilterChip
                key={c.type}
                label={`${c.hitDefaultEmoji} ${c.plural}`}
                count={byCategory.get(c.type)?.length || undefined}
                active={filter === c.type}
                onClick={() => setFilter(c.type)}
              />
            ))}
            <Button
              size="sm"
              variant="outline"
              className="h-7 gap-1 rounded-full px-2.5 text-xs"
              onClick={startNewList}
            >
              <Plus className="h-3.5 w-3.5" /> New collection
            </Button>
          </div>
        </div>
      )}

      {isEmpty ? (
        <div className="rounded-2xl border border-dashed border-border p-5 text-center">
          <p className="text-sm text-muted-foreground">
            Nothing in your collection yet — tap the bookmark on any post, or hit "Want to…" on an item page.
          </p>
          <p className="mt-3 text-sm text-muted-foreground">Or start a collection from scratch:</p>
          <Button size="sm" className="mt-3 gap-1 rounded-full" onClick={startNewList}>
            <Plus className="h-4 w-4" /> New collection
          </Button>
        </div>
      ) : null}

      {allLists.length > 0 && (
        <div className="space-y-3">
          <h3 className="font-display text-lg">Your collections</h3>
          {allLists.map((list) => {
            const inList = entries.filter((e) => e.listId === list.id && matchesFilter(e));
            const VMeta = VISIBILITY_META[list.visibility];
            const VIcon = VMeta.icon;
            const isOwner = list.user_id === userId;
            return (
              <div key={list.id} className="rounded-2xl border border-border bg-card/40 p-3">
                <div className="mb-2 flex items-center justify-between gap-2">
                  <p className="min-w-0 truncate font-medium">
                    <span className="mr-1.5">{list.emoji ?? "✨"}</span>
                    {list.name} <span className="text-xs text-muted-foreground">({inList.length})</span>
                    {!isOwner ? (
                      <span className="ml-1.5 rounded-full bg-primary/10 px-1.5 py-0.5 text-[10px] font-medium text-primary">
                        Shared with you
                      </span>
                    ) : null}
                  </p>
                  <div className="flex items-center gap-1">
                    <CollaboratorStack
                      collaborators={collabsByList.get(list.id) ?? []}
                      owner={people?.get(list.user_id) ?? null}
                      onOpen={() => setCollabList(list)}
                    />
                    {isOwner ? (
                      <>
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
                            <DropdownMenuLabel>Who can see this collection</DropdownMenuLabel>
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
                            if (confirm(`Delete collection "${list.name}"? Items go back to default.`)) deleteList(list);
                          }}
                          className="rounded-full p-1.5 text-muted-foreground hover:bg-muted hover:text-destructive"
                          aria-label="Delete collection"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </button>
                      </>
                    ) : null}
                  </div>
                </div>
                {inList.length > 0 ? (
                  <EntryList
                    entries={inList}
                    lists={allLists}
                    currentUserId={userId}
                    people={people}
                    onMove={moveEntry}
                    onRemove={removeEntry}
                  />
                ) : (
                  <p className="text-xs text-muted-foreground">
                    Empty — anything you save can be moved in here, whatever the category.
                  </p>
                )}
              </div>
            );
          })}
        </div>
      )}

      {activeCategories.map((cat) => {
        const defaults = (byCategory.get(cat.type) ?? []).filter((e) => !e.listId && e.userId === userId);
        if (defaults.length === 0) return null;
        return (
          <div key={cat.type} className="space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="font-display text-lg">
                <span className="mr-2">{cat.hitDefaultEmoji}</span>
                {cat.hitDefaultLabel}{" "}
                <span className="text-sm text-muted-foreground">({defaults.length})</span>
              </h3>
            </div>

            <EntryList
              entries={defaults}
              lists={allLists}
              cat={cat}
              currentUserId={userId}
              people={people}
              onMove={moveEntry}
              onRemove={removeEntry}
            />
          </div>
        );
      })}


      {collabList ? (
        <CollaboratorsDialog
          open={!!collabList}
          onOpenChange={(o) => !o && setCollabList(null)}
          listId={collabList.id}
          listName={collabList.name}
          ownerId={collabList.user_id}
          owner={people?.get(collabList.user_id) ?? null}
          collaborators={collabsByList.get(collabList.id) ?? []}
          currentUserId={userId}
        />
      ) : null}

      <Dialog open={!!newListFor} onOpenChange={(o) => !o && setNewListFor(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              New collection
              {newListFor === "mixed"
                ? " — anything goes"
                : newListFor
                ? ` in ${categoryMeta(newListFor as ItemType).plural}`
                : ""}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <label className="mb-1.5 block text-xs font-medium">What goes in it</label>
              <div className="flex flex-wrap gap-1.5">
                <button
                  type="button"
                  onClick={() => setNewListFor("mixed")}
                  className={cn(
                    "rounded-full px-2.5 py-1 text-xs ring-1 transition",
                    newListFor === "mixed"
                      ? "bg-primary text-primary-foreground ring-primary"
                      : "bg-card text-muted-foreground ring-border hover:bg-muted",
                  )}
                >
                  ✨ Mix of everything
                </button>
                {CATEGORIES.map((c) => (
                  <button
                    key={c.type}
                    type="button"
                    onClick={() => setNewListFor(c.type)}
                    className={cn(
                      "rounded-full px-2.5 py-1 text-xs ring-1 transition",
                      newListFor === c.type
                        ? "bg-primary text-primary-foreground ring-primary"
                        : "bg-card text-muted-foreground ring-border hover:bg-muted",
                    )}
                  >
                    {c.hitDefaultEmoji} {c.plural}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="mb-1 block text-xs font-medium">Name</label>
              <Input
                autoFocus
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                placeholder="e.g. Tokyo collection"
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
              <p className="mt-1 text-[11px] text-muted-foreground">
                You can invite friends to add to any collection once it's created.
              </p>
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
  currentUserId,
  people,
  onMove,
  onRemove,
}: {
  entries: Entry[];
  lists: ListRow[];
  cat?: (typeof CATEGORIES)[number];
  currentUserId: string;
  people?: Map<string, Profile>;
  onMove: (entry: Entry, listId: string | null) => void;
  onRemove: (entry: Entry) => void;
}) {
  if (entries.length === 0) return null;
  return (
    <div className="space-y-2">
      {entries.map((e) => {
        const c = cat ?? categoryMeta(e.itemType);
        const Icon = c.icon;
        const mine = e.userId === currentUserId;
        const who = mine ? null : people?.get(e.userId) ?? null;
        return (
          <div
            key={`${e.kind}-${e.id}`}
            className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border"
          >
            <Link
              to={e.href as any}
              params={e.params}
              className="flex min-w-0 flex-1 items-center gap-3"
            >
              <div className={cn("flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-xl", c.tokenClass)}>
                {e.image ? (
                  <img src={e.image} alt="" className="h-full w-full object-cover" />
                ) : (
                  <Icon className="h-5 w-5" />
                )}
              </div>
              <div className="min-w-0 flex-1">
                <p className="truncate font-medium">{e.title}</p>
                <p className="flex items-center gap-1 truncate text-xs text-muted-foreground">
                  {who ? (
                    <>
                      <UserAvatar url={who.avatar_url} name={who.display_name || who.username} size="xs" className="h-4 w-4 text-[9px]" />
                      added by {who.display_name || who.username}
                    </>
                  ) : (
                    <>{!cat ? `${c.label} · ` : ""}{e.kind === "saved" ? "Saved post" : c.wantVerb}</>
                  )}
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
                {mine ? (
                  <>
                    <DropdownMenuLabel>Move to</DropdownMenuLabel>
                    <DropdownMenuItem onClick={() => onMove(e, null)}>
                      {c.hitDefaultEmoji} {c.hitDefaultLabel} (default)
                    </DropdownMenuItem>
                    {lists.map((l) => (
                      <DropdownMenuItem key={l.id} onClick={() => onMove(e, l.id)}>
                        {l.emoji ?? (l.item_type === "mixed" ? "✨" : c.hitDefaultEmoji)} {l.name}
                      </DropdownMenuItem>
                    ))}
                    <DropdownMenuSeparator />
                  </>
                ) : null}
                <DropdownMenuItem className="text-destructive" onClick={() => onRemove(e)}>
                  <Trash2 className="mr-2 h-4 w-4" /> Remove from collection
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        );
      })}
    </div>
  );
}

function FilterChip({
  label,
  count,
  active,
  onClick,
}: {
  label: string;
  count?: number;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "rounded-full px-3 py-1 text-xs font-medium ring-1 transition",
        active
          ? "bg-primary text-primary-foreground ring-primary"
          : "bg-card text-muted-foreground ring-border hover:bg-muted",
      )}
    >
      {label}
      {count ? <span className="ml-1 opacity-70">{count}</span> : null}
    </button>
  );
}

