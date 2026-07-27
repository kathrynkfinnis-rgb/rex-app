import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import { UserPlus, Check, X, Search, Share2, Users } from "lucide-react";

export const Route = createFileRoute("/_authenticated/friends")({
  head: () => ({
    meta: [
      { title: "Friends — REX" },
      { name: "description", content: "Manage your friends on REX." },
    ],
  }),
  component: FriendsPage,
});

function FriendsPage() {
  const qc = useQueryClient();
  const [search, setSearch] = useState("");
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [searching, setSearching] = useState(false);

  const { data: me } = useQuery({
    queryKey: ["me-user"],
    queryFn: async () => (await supabase.auth.getUser()).data.user,
  });

  const { data: friendships } = useQuery({
    queryKey: ["friendships"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("friendships")
        .select("id, requester_id, addressee_id, status, requester:profiles!friendships_requester_id_fkey(username, display_name), addressee:profiles!friendships_addressee_id_fkey(username, display_name)");
      if (error) throw error;
      return data ?? [];
    },
    enabled: !!me,
  });

  const { data: myProfile } = useQuery({
    queryKey: ["me-profile-username", me?.id],
    queryFn: async () => {
      if (!me) return null;
      const { data } = await supabase.from("profiles").select("username, display_name").eq("id", me.id).single();
      return data;
    },
    enabled: !!me,
  });

  const { data: suggestions } = useQuery({
    queryKey: ["suggested-friends"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("suggested_friends", { _limit: 10 });
      if (error) throw error;
      return data ?? [];
    },
    enabled: !!me,
  });

  const uid = me?.id;
  const incoming = (friendships ?? []).filter((f: any) => f.addressee_id === uid && f.status === "pending");
  const outgoing = (friendships ?? []).filter((f: any) => f.requester_id === uid && f.status === "pending");
  const accepted = (friendships ?? []).filter((f: any) => f.status === "accepted");

  async function shareInvite() {
    const username = myProfile?.username;
    const url = typeof window !== "undefined"
      ? `${window.location.origin}/auth?mode=signup${username ? `&ref=${encodeURIComponent(username)}` : ""}`
      : "";
    const text = username
      ? `Add me on REX 🦖 — I'm @${username}. Follow my recommendations for books, films, TV & places.`
      : `Join me on REX 🦖 — recommendations for books, films, TV & places from friends you trust.`;
    try {
      if (navigator.share) {
        await navigator.share({ title: "Join me on REX", text, url });
      } else {
        await navigator.clipboard.writeText(`${text} ${url}`);
        toast.success("Invite link copied");
      }
    } catch {
      /* user cancelled */
    }
  }

  async function doSearch() {
    if (!search.trim()) return;
    setSearching(true);
    const { data } = await supabase
      .from("profiles")
      .select("id, username, display_name")
      .ilike("username", `%${search.trim().toLowerCase()}%`)
      .neq("id", uid ?? "")
      .limit(10);
    setSearchResults(data ?? []);
    setSearching(false);
  }

  async function sendRequest(addresseeId: string) {
    if (!uid) return;
    const { error } = await supabase.from("friendships").insert({
      requester_id: uid,
      addressee_id: addresseeId,
      status: "pending",
    });
    if (error) toast.error(error.message);
    else {
      toast.success("Request sent");
      qc.invalidateQueries({ queryKey: ["friendships"] });
    }
  }

  async function respond(id: string, accept: boolean) {
    if (accept) {
      const { error } = await supabase.from("friendships").update({ status: "accepted" }).eq("id", id);
      if (error) toast.error(error.message);
      else toast.success("You're now friends");
    } else {
      const { error } = await supabase.from("friendships").delete().eq("id", id);
      if (error) toast.error(error.message);
    }
    qc.invalidateQueries({ queryKey: ["friendships"] });
    qc.invalidateQueries({ queryKey: ["feed"] });
  }

  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <h1 className="font-display text-3xl">Friends</h1>
        <p className="mt-1 text-sm text-muted-foreground">Add the friends whose taste you trust.</p>
      </header>

      <div className="p-5">
        <div className="flex gap-2">
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by username"
            className="h-12 rounded-xl"
            onKeyDown={(e) => e.key === "Enter" && doSearch()}
          />
          <Button onClick={doSearch} disabled={searching} className="h-12 rounded-xl">
            <Search className="h-4 w-4" />
          </Button>
        </div>
        {searchResults.length > 0 && (
          <ul className="mt-3 space-y-2">
            {searchResults.map((p) => {
              const already = (friendships ?? []).some(
                (f: any) => f.requester_id === p.id || f.addressee_id === p.id,
              );
              return (
                <li key={p.id} className="flex items-center justify-between rounded-2xl bg-card p-3 ring-1 ring-border">
                  <div>
                    <p className="font-medium">{p.display_name || p.username}</p>
                    <p className="text-xs text-muted-foreground">@{p.username}</p>
                  </div>
                  <Button
                    size="sm"
                    onClick={() => sendRequest(p.id)}
                    disabled={already}
                    variant={already ? "outline" : "default"}
                    className="rounded-full"
                  >
                    {already ? "Sent" : <><UserPlus className="mr-1 h-3.5 w-3.5" /> Add</>}
                  </Button>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      {incoming.length > 0 && (
        <Section title="Requests for you">
          {incoming.map((f: any) => (
            <div key={f.id} className="flex items-center justify-between rounded-2xl bg-card p-3 ring-1 ring-border">
              <div>
                <p className="font-medium">{f.requester?.display_name || f.requester?.username}</p>
                <p className="text-xs text-muted-foreground">@{f.requester?.username}</p>
              </div>
              <div className="flex gap-1.5">
                <Button size="icon" onClick={() => respond(f.id, true)} className="h-9 w-9 rounded-full">
                  <Check className="h-4 w-4" />
                </Button>
                <Button size="icon" variant="outline" onClick={() => respond(f.id, false)} className="h-9 w-9 rounded-full">
                  <X className="h-4 w-4" />
                </Button>
              </div>
            </div>
          ))}
        </Section>
      )}

      {outgoing.length > 0 && (
        <Section title="Pending">
          {outgoing.map((f: any) => (
            <div key={f.id} className="flex items-center justify-between rounded-2xl bg-card p-3 ring-1 ring-border">
              <div>
                <p className="font-medium">{f.addressee?.display_name || f.addressee?.username}</p>
                <p className="text-xs text-muted-foreground">@{f.addressee?.username}</p>
              </div>
              <span className="text-xs text-muted-foreground">Waiting…</span>
            </div>
          ))}
        </Section>
      )}

      <Section title={`Your friends${accepted.length ? ` (${accepted.length})` : ""}`}>
        {accepted.length === 0 ? (
          <p className="text-sm text-muted-foreground">No friends yet. Search above to add someone.</p>
        ) : (
          accepted.map((f: any) => {
            const other = f.requester_id === uid ? f.addressee : f.requester;
            return (
              <div key={f.id} className="flex items-center justify-between rounded-2xl bg-card p-3 ring-1 ring-border">
                <div className="flex items-center gap-3">
                  <div className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary text-sm font-semibold">
                    {(other?.display_name || other?.username || "?").slice(0, 1).toUpperCase()}
                  </div>
                  <div>
                    <p className="font-medium">{other?.display_name || other?.username}</p>
                    <p className="text-xs text-muted-foreground">@{other?.username}</p>
                  </div>
                </div>
              </div>
            );
          })
        )}
      </Section>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="px-5 pb-5">
      <h2 className="mb-2 text-xs font-semibold uppercase tracking-widest text-muted-foreground">{title}</h2>
      <div className="space-y-2">{children}</div>
    </section>
  );
}
