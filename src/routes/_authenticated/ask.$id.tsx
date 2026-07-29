import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { ArrowLeft, Sparkles, Send, Trash2, Plus } from "lucide-react";
import { formatDistanceToNow } from "date-fns";
import { supabase } from "@/integrations/supabase/client";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { UserAvatar } from "@/components/UserAvatar";
import { SearchPicker, type AnyHit } from "@/components/SearchPicker";
import { cn } from "@/lib/utils";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/ask/$id")({
  head: () => ({
    meta: [
      { title: "Ask — REX" },
      { name: "description", content: "See what friends suggest." },
    ],
  }),
  component: AskDetailPage,
});

function AskDetailPage() {
  const { id } = Route.useParams();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [body, setBody] = useState("");
  const [posting, setPosting] = useState(false);
  const [suggestOpen, setSuggestOpen] = useState(false);
  const [suggested, setSuggested] = useState<{ id: string; title: string; subtitle: string | null; image_url: string | null; type: ItemType } | null>(null);

  const { data: me } = useQuery({
    queryKey: ["me"],
    queryFn: async () => (await supabase.auth.getUser()).data.user,
  });

  const { data, isLoading } = useQuery({
    queryKey: ["request", id],
    queryFn: async () => {
      const { data: req, error } = await supabase
        .from("requests")
        .select("id, user_id, type, title, note, created_at, profiles!requests_user_id_profiles_fkey(username, display_name, avatar_url)")
        .eq("id", id)
        .single();
      if (error) throw error;
      const { data: comments } = await supabase
        .from("request_comments")
        .select("id, body, created_at, user_id, suggested_item_id, profiles!request_comments_user_id_profiles_fkey(username, display_name, avatar_url), items(id, type, title, subtitle, image_url)")
        .eq("request_id", id)
        .order("created_at", { ascending: true });
      return { req, comments: comments ?? [] };
    },
  });

  async function handlePickSuggestion(hit: AnyHit) {
    const hitType: ItemType = (req?.type as ItemType | null) ?? ("place" as ItemType);
    // Reuse existing item if we've seen this external id before
    let itemId: string | undefined;
    if (hit.external_source && hit.external_id) {
      const { data: existing } = await supabase
        .from("items")
        .select("id")
        .eq("external_source", hit.external_source)
        .eq("external_id", hit.external_id)
        .maybeSingle();
      itemId = existing?.id;
    }
    if (!itemId) {
      const { data: item, error } = await supabase
        .from("items")
        .insert({
          type: hitType,
          title: hit.title,
          subtitle: hit.subtitle ?? null,
          image_url: hit.image_url ?? null,
          external_id: hit.external_id ?? null,
          external_source: hit.external_source ?? null,
          address: "address" in hit ? hit.address ?? null : null,
          lat: "lat" in hit ? hit.lat ?? null : null,
          lng: "lng" in hit ? hit.lng ?? null : null,
          genre: hit.genre ?? null,
        } as never)
        .select("id")
        .single();
      if (error) { toast.error("Couldn't attach suggestion"); return; }
      itemId = item.id;
    }
    setSuggested({
      id: itemId!,
      title: hit.title,
      subtitle: hit.subtitle ?? null,
      image_url: hit.image_url ?? null,
      type: hitType,
    });
    setSuggestOpen(false);
  }

  async function postComment() {
    if (!me) return;
    if (!body.trim() && !suggested) return;
    setPosting(true);
    try {
      const { error } = await supabase.from("request_comments").insert({
        request_id: id,
        user_id: me.id,
        body: body.trim() || (suggested ? `Try: ${suggested.title}` : ""),
        suggested_item_id: suggested?.id ?? null,
      });
      if (error) throw error;
      setBody("");
      setSuggested(null);
      qc.invalidateQueries({ queryKey: ["request", id] });
      qc.invalidateQueries({ queryKey: ["request-comments-count", id] });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Couldn't post");
    } finally {
      setPosting(false);
    }
  }

  async function deleteRequest() {
    if (!confirm("Delete this ask?")) return;
    const { error } = await supabase.from("requests").delete().eq("id", id);
    if (error) { toast.error(error.message); return; }
    toast.success("Deleted");
    navigate({ to: "/feed" });
  }

  async function deleteComment(cid: string) {
    const { error } = await supabase.from("request_comments").delete().eq("id", cid);
    if (error) { toast.error(error.message); return; }
    qc.invalidateQueries({ queryKey: ["request", id] });
    qc.invalidateQueries({ queryKey: ["request-comments-count", id] });
  }

  if (isLoading || !data) {
    return <div className="p-6"><div className="h-40 animate-pulse rounded-2xl bg-muted" /></div>;
  }
  const { req, comments } = data;
  const cat = req.type ? categoryMeta(req.type as ItemType) : null;
  const Icon = cat?.icon ?? Sparkles;
  const isOwner = me?.id === req.user_id;

  return (
    <div>
      <header className="border-b border-border bg-gradient-to-br from-accent/15 via-background to-background px-5 pb-5 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <button onClick={() => navigate({ to: "/feed" })} className="flex items-center gap-2 text-sm text-muted-foreground">
          <ArrowLeft className="h-4 w-4" /> Back
        </button>
        <div className="mt-3 flex items-center gap-2">
          <span className="inline-flex items-center gap-1 rounded-full bg-accent/20 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-widest text-accent-foreground">
            <Sparkles className="h-3 w-3" /> Asking
          </span>
          {cat && (
            <span className={cn("inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider", cat.tokenClass)}>
              <Icon className="h-3 w-3" /> {cat.label}
            </span>
          )}
        </div>
        <h1 className="mt-2 font-display text-3xl leading-tight">{req.title}</h1>
        {req.note && <p className="mt-2 text-sm text-muted-foreground">{req.note}</p>}
        <div className="mt-3 flex items-center gap-2 text-xs">
          <UserAvatar url={req.profiles?.avatar_url} name={req.profiles?.display_name || req.profiles?.username} size="sm" />
          <span className="font-medium">{req.profiles?.display_name || req.profiles?.username}</span>
          <span className="text-muted-foreground">· {formatDistanceToNow(new Date(req.created_at), { addSuffix: true })}</span>
          {isOwner && (
            <button onClick={deleteRequest} className="ml-auto flex items-center gap-1 text-muted-foreground hover:text-destructive">
              <Trash2 className="h-3.5 w-3.5" /> Delete
            </button>
          )}
        </div>
      </header>

      <section className="p-5">
        <h2 className="font-display text-2xl">Suggestions</h2>
        {comments.length === 0 && (
          <p className="mt-2 text-sm text-muted-foreground">No replies yet — be the first to chime in.</p>
        )}
        <div className="mt-3 space-y-3">
          {comments.map((c: any) => (
            <div key={c.id} className="rounded-2xl bg-card p-3 ring-1 ring-border">
              <div className="flex items-center gap-2">
                <UserAvatar url={c.profiles?.avatar_url} name={c.profiles?.display_name || c.profiles?.username} size="sm" />
                <span className="text-sm font-medium">{c.profiles?.display_name || c.profiles?.username}</span>
                <span className="text-[11px] text-muted-foreground">{formatDistanceToNow(new Date(c.created_at), { addSuffix: true })}</span>
                {me?.id === c.user_id && (
                  <button onClick={() => deleteComment(c.id)} className="ml-auto text-muted-foreground hover:text-destructive">
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                )}
              </div>
              {c.body && <p className="mt-2 whitespace-pre-wrap text-sm leading-snug">{c.body}</p>}
              {c.items && (
                <Link
                  to="/item/$id"
                  params={{ id: c.items.id }}
                  className="mt-2 flex items-center gap-3 rounded-xl bg-background p-2 ring-1 ring-border transition-colors hover:bg-muted/60"
                >
                  <div className="h-12 w-12 shrink-0 overflow-hidden rounded-lg bg-muted">
                    {c.items.image_url && <img src={c.items.image_url} alt="" className="h-full w-full object-cover" />}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">{c.items.title}</p>
                    {c.items.subtitle && <p className="truncate text-xs text-muted-foreground">{c.items.subtitle}</p>}
                  </div>
                </Link>
              )}
            </div>
          ))}
        </div>
      </section>

      <section className="sticky bottom-0 border-t border-border bg-background/95 p-4 pb-[calc(env(safe-area-inset-bottom)+1rem)] backdrop-blur">
        {suggested && (
          <div className="mb-2 flex items-center gap-2 rounded-xl bg-card p-2 ring-1 ring-border">
            <div className="h-10 w-10 shrink-0 overflow-hidden rounded-lg bg-muted">
              {suggested.image_url && <img src={suggested.image_url} alt="" className="h-full w-full object-cover" />}
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">{suggested.title}</p>
              {suggested.subtitle && <p className="truncate text-xs text-muted-foreground">{suggested.subtitle}</p>}
            </div>
            <button onClick={() => setSuggested(null)} className="text-xs text-muted-foreground underline">Remove</button>
          </div>
        )}
        {suggestOpen && req.type && req.type !== "recipe" && (
          <div className="mb-3">
            <SearchPicker type={req.type as ItemType} onPick={handlePickSuggestion} onManual={() => setSuggestOpen(false)} near={null} />
            <button onClick={() => setSuggestOpen(false)} className="mt-2 text-xs text-muted-foreground underline">Cancel search</button>
          </div>
        )}
        <div className="flex items-end gap-2">
          <Textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            rows={2}
            placeholder="Add a suggestion or comment…"
            className="min-h-[44px] flex-1 rounded-2xl"
          />
          <div className="flex flex-col gap-2">
            {req.type && req.type !== "recipe" && !suggestOpen && !suggested && (
              <Button type="button" variant="outline" size="icon" className="rounded-full" onClick={() => setSuggestOpen(true)} aria-label="Attach suggestion">
                <Plus className="h-4 w-4" />
              </Button>
            )}
            <Button
              type="button"
              size="icon"
              className="rounded-full"
              onClick={postComment}
              disabled={posting || (!body.trim() && !suggested)}
              aria-label="Post"
            >
              <Send className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </section>
    </div>
  );
}
