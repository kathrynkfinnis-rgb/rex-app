import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { supabase } from "@/integrations/supabase/client";
import { searchProfiles, suggestedFriends } from "@/lib/friends.functions";
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
        .select("id, requester_id, addressee_id, status");
      if (error) throw error;
      const rows = data ?? [];
      const ids = Array.from(new Set(rows.flatMap((r: any) => [r.requester_id, r.addressee_id])));
      let profilesById: Record<string, { username: string; display_name: string | null }> = {};
      if (ids.length) {
        const { data: profs } = await supabase
          .from("profiles")
          .select("id, username, display_name")
          .in("id", ids);
        for (const p of profs ?? []) profilesById[(p as any).id] = p as any;
      }
      return rows.map((r: any) => ({
        ...r,
        requester: profilesById[r.requester_id],
        addressee: profilesById[r.addressee_id],
      }));
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

  const suggestedFn = useServerFn(suggestedFriends);
  const searchFn = useServerFn(searchProfiles);

  const { data: suggestions } = useQuery({
    queryKey: ["suggested-friends"],
    queryFn: async () => {
      return await suggestedFn({ data: { limit: 10 } });
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
    const full = `${text} ${url}`;

    // Try native share (often blocked inside iframes/previews without allow="web-share")
    if (typeof navigator !== "undefined" && (navigator as any).share) {
      try {
        await (navigator as any).share({ title: "Join me on REX", text, url });
        return;
      } catch (err: any) {
        if (err?.name === "AbortError") return; // user cancelled the sheet
        // otherwise fall through to clipboard
      }
    }

    // Clipboard fallback
    try {
      await navigator.clipboard.writeText(full);
      toast.success("Invite link copied to clipboard");
      return;
    } catch {
      // Legacy execCommand fallback (works in more iframe contexts)
      try {
        const ta = document.createElement("textarea");
        ta.value = full;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.focus();
        ta.select();
        const ok = document.execCommand("copy");
        document.body.removeChild(ta);
        if (ok) {
          toast.success("Invite link copied to clipboard");
          return;
        }
      } catch {}
      toast.error(`Couldn't copy automatically. Link: ${url}`, { duration: 12000 });
    }
  }

  async function doSearch() {
    if (!search.trim()) return;
    setSearching(true);
    try {
      const data = await searchFn({ data: { query: search.trim(), limit: 10 } });
      setSearchResults((data ?? []) as any[]);
    } finally {
      setSearching(false);
    }
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

        <Button
          onClick={shareInvite}
          variant="outline"
          className="mt-4 h-12 w-full gap-2 rounded-full"
        >
          <Share2 className="h-4 w-4" /> Share invite link
        </Button>
      </div>

      {suggestions && suggestions.length > 0 && (
        <Section title="People you may know">
          {suggestions.map((p: any) => {
            const already = (friendships ?? []).some(
              (f: any) => f.requester_id === p.id || f.addressee_id === p.id,
            );
            return (
              <div key={p.id} className="flex items-center justify-between rounded-2xl bg-card p-3 ring-1 ring-border">
                <div className="flex items-center gap-3 min-w-0">
                  <div className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary text-sm font-semibold">
                    {(p.display_name || p.username || "?").slice(0, 1).toUpperCase()}
                  </div>
                  <div className="min-w-0">
                    <p className="truncate font-medium">{p.display_name || p.username}</p>
                    <p className="flex items-center gap-1 truncate text-xs text-muted-foreground">
                      <Users className="h-3 w-3" />
                      {p.mutual_count} mutual{p.mutual_count === 1 ? "" : "s"} · @{p.username}
                    </p>
                  </div>
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
              </div>
            );
          })}
        </Section>
      )}

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
