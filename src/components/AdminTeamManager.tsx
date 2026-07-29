import { useState } from "react";
import { Link } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { Crown, Search, UserPlus, X, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { listAdmins, searchUsersForAdmin, grantAdmin, revokeAdmin } from "@/lib/admin.functions";

export function AdminTeamManager({ currentUserId }: { currentUserId?: string }) {
  const qc = useQueryClient();
  const [q, setQ] = useState("");
  const [submitted, setSubmitted] = useState("");

  const fetchAdmins = useServerFn(listAdmins);
  const searchFn = useServerFn(searchUsersForAdmin);
  const grantFn = useServerFn(grantAdmin);
  const revokeFn = useServerFn(revokeAdmin);

  const adminsQ = useQuery({ queryKey: ["admin-team"], queryFn: () => fetchAdmins({}) });

  const searchQ = useQuery({
    queryKey: ["admin-user-search", submitted],
    enabled: submitted.trim().length >= 2,
    queryFn: () => searchFn({ data: { query: submitted.trim() } }),
  });

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ["admin-team"] });
    qc.invalidateQueries({ queryKey: ["admin-user-search"] });
    qc.invalidateQueries({ queryKey: ["me-is-admin"] });
  };

  const grant = useMutation({
    mutationFn: (userId: string) => grantFn({ data: { userId } }),
    onSuccess: () => { toast.success("Admin access granted"); invalidate(); },
    onError: (e: any) => toast.error(e?.message ?? "Couldn't grant admin access"),
  });

  const revoke = useMutation({
    mutationFn: (userId: string) => revokeFn({ data: { userId } }),
    onSuccess: () => { toast.success("Admin access removed"); invalidate(); },
    onError: (e: any) => toast.error(e?.message ?? "Couldn't remove admin access"),
  });

  return (
    <div className="space-y-3">
      <div className="space-y-2">
        {(adminsQ.data ?? []).map((a) => (
          <div key={a.id} className="flex items-center gap-3 rounded-xl border border-border bg-card p-3">
            <Link to="/profile/$username" params={{ username: a.username }} className="flex min-w-0 flex-1 items-center gap-3">
              <Avatar url={a.avatar_url} name={a.display_name || a.username} />
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-semibold">{a.display_name || a.username}</div>
                <div className="truncate text-xs text-muted-foreground">@{a.username}</div>
              </div>
            </Link>
            {a.id === currentUserId ? (
              <span className="flex items-center gap-1 text-[11px] text-muted-foreground"><Crown className="h-3.5 w-3.5 text-primary" /> You</span>
            ) : (
              <button
                onClick={() => {
                  if (confirm(`Remove admin access for @${a.username}?`)) revoke.mutate(a.id);
                }}
                className="rounded-full p-1.5 text-muted-foreground hover:bg-muted hover:text-destructive"
                aria-label={`Remove admin access for ${a.username}`}
              >
                <X className="h-4 w-4" />
              </button>
            )}
          </div>
        ))}
        {adminsQ.isLoading && <div className="h-14 animate-pulse rounded-xl bg-muted" />}
        {adminsQ.data?.length === 0 && <p className="text-xs text-muted-foreground">No admins yet.</p>}
      </div>

      <div className="rounded-xl border border-border bg-card p-3">
        <p className="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          <UserPlus className="h-3.5 w-3.5" /> Add an admin
        </p>
        <form
          className="flex gap-2"
          onSubmit={(e) => { e.preventDefault(); setSubmitted(q); }}
        >
          <Input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search by username or name"
            maxLength={60}
            className="h-10 rounded-full"
          />
          <Button type="submit" size="icon" className="h-10 w-10 shrink-0 rounded-full" aria-label="Search users">
            {searchQ.isFetching ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
          </Button>
        </form>

        {submitted.trim().length >= 2 && (
          <div className="mt-3 space-y-2">
            {searchQ.data?.length === 0 && (
              <p className="text-xs text-muted-foreground">No users match “{submitted}”.</p>
            )}
            {(searchQ.data ?? []).map((p) => (
              <div key={p.id} className="flex items-center gap-3">
                <Avatar url={p.avatar_url} name={p.display_name || p.username} />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-medium">{p.display_name || p.username}</div>
                  <div className="truncate text-xs text-muted-foreground">@{p.username}</div>
                </div>
                {p.is_admin ? (
                  <span className="flex items-center gap-1 text-[11px] text-primary"><Crown className="h-3.5 w-3.5" /> Admin</span>
                ) : (
                  <Button
                    size="sm"
                    variant="outline"
                    className="h-8 rounded-full"
                    disabled={grant.isPending}
                    onClick={() => grant.mutate(p.id)}
                  >
                    Make admin
                  </Button>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
      <p className="text-[11px] text-muted-foreground">
        Admins can view this dashboard and manage other admins. You can't remove yourself or the last remaining admin.
      </p>
    </div>
  );
}

function Avatar({ url, name }: { url: string | null; name: string }) {
  return (
    <div
      className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary bg-cover bg-center text-xs font-semibold text-primary-foreground"
      style={url ? { backgroundImage: `url(${url})` } : undefined}
    >
      {!url && (name || "?").slice(0, 1).toUpperCase()}
    </div>
  );
}
