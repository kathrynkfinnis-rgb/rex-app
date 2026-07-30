import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { UserAvatar } from "@/components/UserAvatar";
import { UserPlus, X } from "lucide-react";
import { toast } from "sonner";

type Profile = { id: string; username: string; display_name: string | null; avatar_url: string | null };
export type Collaborator = { id: string; user_id: string; list_id: string; profile: Profile | null };

export function CollaboratorStack({
  collaborators,
  owner,
  onOpen,
}: {
  collaborators: Collaborator[];
  owner: Profile | null;
  onOpen: () => void;
}) {
  const people = [owner, ...collaborators.map((c) => c.profile)].filter(Boolean) as Profile[];
  return (
    <button
      type="button"
      onClick={onOpen}
      className="flex items-center gap-1 rounded-full px-1.5 py-1 hover:bg-muted"
      aria-label="Manage collaborators"
    >
      <div className="flex -space-x-2">
        {people.slice(0, 3).map((p) => (
          <UserAvatar key={p.id} url={p.avatar_url} name={p.display_name || p.username} size="xs" className="ring-2 ring-card" />
        ))}
      </div>
      {people.length > 3 ? <span className="text-[11px] text-muted-foreground">+{people.length - 3}</span> : null}
      <UserPlus className="h-3.5 w-3.5 text-muted-foreground" />
    </button>
  );
}

export function CollaboratorsDialog({
  listId,
  listName,
  ownerId,
  owner,
  collaborators,
  currentUserId,
  open,
  onOpenChange,
}: {
  listId: string;
  listName: string;
  ownerId: string;
  owner: Profile | null;
  collaborators: Collaborator[];
  currentUserId: string;
  open: boolean;
  onOpenChange: (o: boolean) => void;
}) {
  const qc = useQueryClient();
  const [q, setQ] = useState("");
  const isOwner = ownerId === currentUserId;

  const { data: friends } = useQuery({
    queryKey: ["accepted-friends", currentUserId],
    enabled: open && isOwner,
    queryFn: async () => {
      const { data } = await supabase
        .from("friendships")
        .select("requester_id, addressee_id")
        .eq("status", "accepted")
        .or(`requester_id.eq.${currentUserId},addressee_id.eq.${currentUserId}`);
      const ids = (data ?? []).map((f) => (f.requester_id === currentUserId ? f.addressee_id : f.requester_id));
      if (ids.length === 0) return [] as Profile[];
      const { data: profiles } = await supabase
        .from("profiles")
        .select("id, username, display_name, avatar_url")
        .in("id", ids);
      return (profiles ?? []) as Profile[];
    },
  });

  const existing = useMemo(() => new Set(collaborators.map((c) => c.user_id)), [collaborators]);
  const candidates = (friends ?? []).filter(
    (f) =>
      !existing.has(f.id) &&
      f.id !== ownerId &&
      (q.trim() === "" ||
        f.username.toLowerCase().includes(q.trim().toLowerCase()) ||
        (f.display_name ?? "").toLowerCase().includes(q.trim().toLowerCase())),
  );

  function refresh() {
    qc.invalidateQueries({ queryKey: ["list-collaborators"] });
    qc.invalidateQueries({ queryKey: ["my-hitlist-lists"] });
  }

  async function add(userId: string) {
    const { error } = await supabase
      .from("list_collaborators")
      .insert({ list_id: listId, user_id: userId, added_by: currentUserId });
    if (error) return toast.error(error.message);
    toast.success("Added to the collection");
    refresh();
  }

  async function remove(rowId: string, self: boolean) {
    const { error } = await supabase.from("list_collaborators").delete().eq("id", rowId);
    if (error) return toast.error(error.message);
    toast.success(self ? "You left the collection" : "Removed");
    refresh();
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Who's on "{listName}"</DialogTitle>
        </DialogHeader>

        <div className="space-y-2">
          {owner ? (
            <div className="flex items-center gap-3 rounded-xl bg-muted/50 p-2">
              <UserAvatar url={owner.avatar_url} name={owner.display_name || owner.username} size="sm" />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{owner.display_name || owner.username}</p>
                <p className="text-xs text-muted-foreground">Owner</p>
              </div>
            </div>
          ) : null}

          {collaborators.map((c) => (
            <div key={c.id} className="flex items-center gap-3 rounded-xl p-2 ring-1 ring-border">
              <UserAvatar url={c.profile?.avatar_url} name={c.profile?.display_name || c.profile?.username} size="sm" />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{c.profile?.display_name || c.profile?.username}</p>
                <p className="text-xs text-muted-foreground">Can add to this collection</p>
              </div>
              {isOwner || c.user_id === currentUserId ? (
                <button
                  type="button"
                  onClick={() => remove(c.id, c.user_id === currentUserId)}
                  className="rounded-full p-1.5 text-muted-foreground hover:bg-muted hover:text-destructive"
                  aria-label="Remove collaborator"
                >
                  <X className="h-4 w-4" />
                </button>
              ) : null}
            </div>
          ))}
        </div>

        {isOwner ? (
          <div className="space-y-2">
            <label className="block text-xs font-medium">Invite a friend</label>
            <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search your friends" />
            <div className="max-h-52 space-y-1 overflow-y-auto">
              {candidates.length === 0 ? (
                <p className="text-xs text-muted-foreground">
                  {(friends?.length ?? 0) === 0 ? "Add some friends first, then invite them here." : "No matches."}
                </p>
              ) : (
                candidates.map((f) => (
                  <div key={f.id} className="flex items-center gap-3 rounded-xl p-2 hover:bg-muted">
                    <UserAvatar url={f.avatar_url} name={f.display_name || f.username} size="sm" />
                    <p className="min-w-0 flex-1 truncate text-sm">{f.display_name || f.username}</p>
                    <Button size="sm" variant="secondary" className="h-8 rounded-full text-xs" onClick={() => add(f.id)}>
                      Add
                    </Button>
                  </div>
                ))
              )}
            </div>
          </div>
        ) : (
          <p className="text-xs text-muted-foreground">You're a contributor — anything you add here is shared with everyone above.</p>
        )}
      </DialogContent>
    </Dialog>
  );
}
