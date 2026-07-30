import { useState } from "react";
import { createFileRoute, Link, useRouteContext } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { RecommendationCard, type FeedRow } from "@/components/RecommendationCard";
import { UserAvatar } from "@/components/UserAvatar";
import { Button } from "@/components/ui/button";
import { ChevronLeft, UserPlus, Trash2, LogOut, Users } from "lucide-react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/group/$id")({
  head: () => ({
    meta: [
      { title: "Group — REX" },
      { name: "description", content: "A private group where you and your friends share recommendations." },
      { property: "og:title", content: "Group — REX" },
      { property: "og:description", content: "A private group where you and your friends share recommendations." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: GroupPage,
});

type Profile = { id: string; username: string; display_name: string | null; avatar_url: string | null };

function GroupPage() {
  const { id } = Route.useParams();
  const { user } = useRouteContext({ from: "/_authenticated" });
  const qc = useQueryClient();
  const [adding, setAdding] = useState(false);

  const { data: group, isLoading } = useQuery({
    queryKey: ["group", id],
    queryFn: async () => {
      const { data } = await supabase.from("groups").select("id, name, emoji, owner_id").eq("id", id).maybeSingle();
      return data;
    },
  });

  const { data: members = [] } = useQuery({
    queryKey: ["group-members", id],
    queryFn: async () => {
      const { data } = await supabase.from("group_members").select("id, user_id").eq("group_id", id);
      const rows = data ?? [];
      if (!rows.length) return [] as { id: string; user_id: string; profile?: Profile }[];
      const { data: profs } = await supabase
        .from("profiles")
        .select("id, username, display_name, avatar_url")
        .in("id", rows.map((r) => r.user_id));
      const byId = new Map((profs ?? []).map((p) => [p.id, p as Profile]));
      return rows.map((r) => ({ ...r, profile: byId.get(r.user_id) }));
    },
  });

  const { data: shares = [] } = useQuery({
    queryKey: ["group-shares", id],
    queryFn: async () => {
      const { data } = await supabase
        .from("group_shares")
        .select(
          "id, note, created_at, user_id, recommendations!inner(id, rating, note, created_at, photo_url, photo_urls, tags, user_id, item_id, items!inner(id, type, title, subtitle, image_url, genre), profiles!recommendations_user_id_fkey(username, display_name, avatar_url))",
        )
        .eq("group_id", id)
        .order("created_at", { ascending: false });
      return (data ?? []) as unknown as { id: string; note: string | null; user_id: string; recommendations: FeedRow }[];
    },
  });

  const { data: friends = [] } = useQuery({
    queryKey: ["group-addable-friends", id, user.id],
    enabled: adding,
    queryFn: async () => {
      const { data } = await supabase
        .from("friendships")
        .select("requester_id, addressee_id")
        .eq("status", "accepted");
      const ids = Array.from(
        new Set((data ?? []).map((f) => (f.requester_id === user.id ? f.addressee_id : f.requester_id))),
      );
      if (!ids.length) return [] as Profile[];
      const { data: profs } = await supabase
        .from("profiles")
        .select("id, username, display_name, avatar_url")
        .in("id", ids);
      return (profs ?? []) as Profile[];
    },
  });

  const isOwner = group?.owner_id === user.id;
  const memberIds = new Set(members.map((m) => m.user_id));

  async function addMember(userId: string) {
    const { error } = await supabase.from("group_members").insert({ group_id: id, user_id: userId });
    if (error) return toast.error(error.message);
    toast.success("Added to the group");
    qc.invalidateQueries({ queryKey: ["group-members", id] });
  }

  async function removeMember(rowId: string, self: boolean) {
    const { error } = await supabase.from("group_members").delete().eq("id", rowId);
    if (error) return toast.error(error.message);
    toast.success(self ? "You left the group" : "Member removed");
    qc.invalidateQueries({ queryKey: ["group-members", id] });
    qc.invalidateQueries({ queryKey: ["my-groups"] });
  }

  async function deleteGroup() {
    const { error } = await supabase.from("groups").delete().eq("id", id);
    if (error) return toast.error(error.message);
    toast.success("Group deleted");
    qc.invalidateQueries({ queryKey: ["groups", user.id] });
    window.history.back();
  }

  if (!isLoading && !group) {
    return (
      <div className="px-5 pt-20">
        <p className="text-sm text-muted-foreground">This group doesn't exist, or you're not a member.</p>
        <Link to="/friends" className="mt-3 inline-block text-sm font-medium text-primary">Back to Friends</Link>
      </div>
    );
  }

  return (
    <div className="pb-24">
      <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <div className="flex items-center gap-2">
          <Link to="/friends" className="flex h-9 w-9 items-center justify-center rounded-full bg-card" aria-label="Back">
            <ChevronLeft className="h-5 w-5" />
          </Link>
          <h1 className="min-w-0 flex-1 truncate font-display text-2xl">
            <span className="mr-1.5">{group?.emoji ?? "👥"}</span>
            {group?.name ?? "Group"}
          </h1>
          {isOwner && (
            <button
              type="button"
              onClick={() => confirm("Delete this group for everyone?") && deleteGroup()}
              className="rounded-full p-2 text-muted-foreground hover:text-destructive"
              aria-label="Delete group"
            >
              <Trash2 className="h-4 w-4" />
            </button>
          )}
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          {members.map((m) => (
            <span key={m.id} className="inline-flex items-center gap-1.5 rounded-full bg-card py-1 pl-1 pr-2.5 text-xs ring-1 ring-border">
              <UserAvatar url={m.profile?.avatar_url} name={m.profile?.display_name || m.profile?.username} size="xs" />
              <span className="max-w-[100px] truncate">{m.profile?.display_name || m.profile?.username || "Member"}</span>
              {(isOwner || m.user_id === user.id) && (
                <button
                  type="button"
                  onClick={() => removeMember(m.id, m.user_id === user.id)}
                  className="text-muted-foreground hover:text-destructive"
                  aria-label={m.user_id === user.id ? "Leave group" : "Remove member"}
                >
                  <LogOut className="h-3 w-3" />
                </button>
              )}
            </span>
          ))}
          {isOwner && (
            <Button size="sm" variant="outline" className="h-8 gap-1 rounded-full text-xs" onClick={() => setAdding(true)}>
              <UserPlus className="h-3.5 w-3.5" /> Add friends
            </Button>
          )}
        </div>
      </header>

      <section className="space-y-3 p-4">
        {shares.length === 0 ? (
          <div className="rounded-2xl bg-card p-6 text-center ring-1 ring-border">
            <Users className="mx-auto mb-2 h-6 w-6 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">
              Nothing shared yet — tap the group icon on any recommendation to send it here.
            </p>
          </div>
        ) : (
          shares.map((s) => (
            <div key={s.id} className="space-y-1">
              {s.note && (
                <p className="px-1 text-xs italic text-muted-foreground">&ldquo;{s.note}&rdquo;</p>
              )}
              <RecommendationCard rec={s.recommendations} />
            </div>
          ))
        )}
      </section>

      <Dialog open={adding} onOpenChange={setAdding}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add friends to {group?.name}</DialogTitle>
          </DialogHeader>
          {friends.length === 0 ? (
            <p className="text-sm text-muted-foreground">No friends to add yet.</p>
          ) : (
            <ul className="max-h-80 space-y-2 overflow-y-auto">
              {friends.map((f) => (
                <li key={f.id} className="flex items-center justify-between gap-3 rounded-xl bg-card p-2.5 ring-1 ring-border">
                  <div className="flex min-w-0 items-center gap-2">
                    <UserAvatar url={f.avatar_url} name={f.display_name || f.username} size="sm" />
                    <span className="truncate text-sm font-medium">{f.display_name || f.username}</span>
                  </div>
                  <Button
                    size="sm"
                    className="rounded-full"
                    variant={memberIds.has(f.id) ? "outline" : "default"}
                    disabled={memberIds.has(f.id)}
                    onClick={() => addMember(f.id)}
                  >
                    {memberIds.has(f.id) ? "In group" : "Add"}
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
