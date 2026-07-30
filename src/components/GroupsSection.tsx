import { useState } from "react";
import { Link } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Plus, Users, ChevronRight } from "lucide-react";
import { toast } from "sonner";

type GroupRow = { id: string; name: string; emoji: string | null; owner_id: string };

export function GroupsSection({ userId }: { userId: string }) {
  const qc = useQueryClient();
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");

  const { data: groups = [] } = useQuery({
    queryKey: ["groups", userId],
    queryFn: async () => {
      const { data: memberships } = await supabase
        .from("group_members")
        .select("group_id")
        .eq("user_id", userId);
      const ids = (memberships ?? []).map((m) => m.group_id);
      const filters = [`owner_id.eq.${userId}`];
      if (ids.length) filters.push(`id.in.(${ids.join(",")})`);
      const { data, error } = await supabase
        .from("groups")
        .select("id, name, emoji, owner_id")
        .or(filters.join(","))
        .order("created_at", { ascending: true });
      if (error) throw error;
      return (data ?? []) as GroupRow[];
    },
  });

  const { data: counts = {} } = useQuery({
    queryKey: ["group-member-counts", groups.map((g) => g.id).join(",")],
    enabled: groups.length > 0,
    queryFn: async () => {
      const { data } = await supabase
        .from("group_members")
        .select("group_id")
        .in("group_id", groups.map((g) => g.id));
      const out: Record<string, number> = {};
      for (const row of data ?? []) out[row.group_id] = (out[row.group_id] ?? 0) + 1;
      return out;
    },
  });

  async function createGroup() {
    const trimmed = name.trim();
    if (!trimmed) return;
    const { data, error } = await supabase
      .from("groups")
      .insert({ owner_id: userId, name: trimmed.slice(0, 60) })
      .select("id")
      .single();
    if (error || !data) return toast.error(error?.message ?? "Couldn't create the group");
    // owner is a member too
    await supabase.from("group_members").insert({ group_id: data.id, user_id: userId });
    toast.success("Group created — now add friends");
    setCreating(false);
    setName("");
    qc.invalidateQueries({ queryKey: ["groups", userId] });
    qc.invalidateQueries({ queryKey: ["my-groups"] });
  }

  return (
    <section className="px-5 pb-5">
      <div className="mb-2 flex items-center justify-between">
        <h2 className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">Groups</h2>
        <Button
          variant="ghost"
          size="sm"
          className="h-8 gap-1 rounded-full text-xs"
          onClick={() => setCreating(true)}
        >
          <Plus className="h-3.5 w-3.5" /> New group
        </Button>
      </div>

      {groups.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          Create a group — a book club, the Tokyo trip, your foodie mates — and share REX straight to it.
        </p>
      ) : (
        <div className="space-y-2">
          {groups.map((g) => (
            <Link
              key={g.id}
              to="/group/$id"
              params={{ id: g.id }}
              className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border transition-colors hover:bg-muted/60"
            >
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-secondary text-lg">
                {g.emoji ?? <Users className="h-5 w-5" />}
              </div>
              <div className="min-w-0 flex-1">
                <p className="truncate font-medium">{g.name}</p>
                <p className="text-xs text-muted-foreground">
                  {counts[g.id] ?? 1} member{(counts[g.id] ?? 1) === 1 ? "" : "s"}
                  {g.owner_id === userId ? " · you're the owner" : ""}
                </p>
              </div>
              <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
            </Link>
          ))}
        </div>
      )}

      <Dialog open={creating} onOpenChange={setCreating}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>New group</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <label className="mb-1 block text-xs font-medium">Name</label>
              <Input
                autoFocus
                value={name}
                onChange={(e) => setName(e.target.value)}
                maxLength={60}
                placeholder="e.g. Book club"
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setCreating(false)}>Cancel</Button>
            <Button onClick={createGroup} disabled={!name.trim()}>Create</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </section>
  );
}
