import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Users, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { toast } from "sonner";

export type GroupLite = { id: string; name: string; emoji: string | null };

export function useMyGroups(enabled = true) {
  return useQuery({
    queryKey: ["my-groups"],
    enabled,
    queryFn: async () => {
      const { data: auth } = await supabase.auth.getUser();
      const uid = auth.user?.id;
      if (!uid) return [] as GroupLite[];
      const { data: memberships } = await supabase
        .from("group_members")
        .select("group_id")
        .eq("user_id", uid);
      const ids = (memberships ?? []).map((m) => m.group_id);
      const { data } = await supabase
        .from("groups")
        .select("id, name, emoji, owner_id, created_at")
        .or([`owner_id.eq.${uid}`, ids.length ? `id.in.(${ids.join(",")})` : null].filter(Boolean).join(","))
        .order("created_at", { ascending: true });
      return (data ?? []) as unknown as (GroupLite & { owner_id: string })[];
    },
  });
}

/** Icon button that shares a recommendation into one of your groups. */
export function ShareToGroupButton({ recommendationId }: { recommendationId: string }) {
  const [open, setOpen] = useState(false);
  const [selected, setSelected] = useState<string[]>([]);
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const { data: groups = [] } = useMyGroups(open);

  function toggle(id: string) {
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));
  }

  async function share() {
    if (!selected.length) return;
    setSaving(true);
    try {
      const { data: auth } = await supabase.auth.getUser();
      const uid = auth.user?.id;
      if (!uid) return;
      const { error } = await supabase.from("group_shares").upsert(
        selected.map((group_id) => ({
          group_id,
          recommendation_id: recommendationId,
          user_id: uid,
          note: note.trim() || null,
        })),
        { onConflict: "group_id,recommendation_id", ignoreDuplicates: true },
      );
      if (error) throw error;
      toast.success(`Shared to ${selected.length} group${selected.length === 1 ? "" : "s"}`);
      setOpen(false);
      setSelected([]);
      setNote("");
    } catch (e: any) {
      toast.error(e?.message ?? "Couldn't share that");
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <button
        type="button"
        aria-label="Share to a group"
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          setOpen(true);
        }}
        className="inline-flex h-8 w-8 items-center justify-center rounded-full text-muted-foreground hover:text-foreground"
      >
        <Users className="h-4 w-4" />
      </button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent onClick={(e) => e.stopPropagation()}>
          <DialogHeader>
            <DialogTitle>Share to a group</DialogTitle>
          </DialogHeader>
          {groups.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              You're not in any groups yet — create one on the Friends tab.
            </p>
          ) : (
            <div className="space-y-3">
              <div className="space-y-1.5">
                {groups.map((g) => {
                  const active = selected.includes(g.id);
                  return (
                    <button
                      key={g.id}
                      type="button"
                      onClick={() => toggle(g.id)}
                      className={cn(
                        "flex w-full items-center gap-2 rounded-xl border p-2.5 text-left text-sm transition",
                        active ? "border-primary bg-primary/10" : "border-border hover:bg-muted",
                      )}
                    >
                      <span>{g.emoji ?? "👥"}</span>
                      <span className="min-w-0 flex-1 truncate font-medium">{g.name}</span>
                      {active && <Check className="h-4 w-4 text-primary" />}
                    </button>
                  );
                })}
              </div>
              <Textarea
                value={note}
                onChange={(e) => setNote(e.target.value)}
                rows={2}
                maxLength={500}
                placeholder="Add a message (optional)"
              />
            </div>
          )}
          <DialogFooter>
            <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={share} disabled={!selected.length || saving}>
              {saving ? "Sharing…" : "Share"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
