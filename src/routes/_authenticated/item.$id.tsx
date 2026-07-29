import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import { ArrowLeft, MapPin, Check } from "lucide-react";
import { CrownRatingDisplay, CrownRatingInput } from "@/components/CrownRating";
import { ItemEnrichment } from "@/components/ItemEnrichment";
import { LikesComments } from "@/components/LikesComments";
import { UserAvatar } from "@/components/UserAvatar";
import { WantButton } from "@/components/WantButton";
import { cn } from "@/lib/utils";
import { formatDistanceToNow } from "date-fns";
import { parseRecipe } from "@/lib/recipe";

export const Route = createFileRoute("/_authenticated/item/$id")({
  head: () => ({
    meta: [
      { title: "Recommendation — REX" },
      { name: "description", content: "See friends' takes on this recommendation." },
    ],
  }),
  component: ItemPage,
});

function ItemPage() {
  const { id } = Route.useParams();
  const navigate = useNavigate();
  const qc = useQueryClient();

  const { data: userRes } = useQuery({
    queryKey: ["me"],
    queryFn: async () => (await supabase.auth.getUser()).data.user,
  });
  const uid = userRes?.id;

  const { data, isLoading } = useQuery({
    queryKey: ["item", id],
    queryFn: async () => {
      const { data: item, error } = await supabase
        .from("items")
        .select("*")
        .eq("id", id)
        .single();
      if (error) throw error;
      const { data: recs } = await supabase
        .from("recommendations")
        .select("id, rating, note, created_at, user_id, profiles!recommendations_user_id_fkey(username, display_name, avatar_url)")
        .eq("item_id", id)
        .order("created_at", { ascending: false });
      const { data: checks } = await supabase
        .from("check_ins")
        .select("id, note, created_at, user_id, profiles!check_ins_user_id_fkey(username, display_name)")
        .eq("item_id", id)
        .order("created_at", { ascending: false });
      return { item, recs: recs ?? [], checks: checks ?? [] };
    },
  });

  const [rating, setRating] = useState(10);
  const [note, setNote] = useState("");
  const [posting, setPosting] = useState(false);
  const [checking, setChecking] = useState(false);

  if (isLoading || !data) {
    return <div className="p-6"><div className="h-40 animate-pulse rounded-2xl bg-muted" /></div>;
  }
  const { item, recs, checks } = data;
  const cat = categoryMeta(item.type as ItemType);
  const myRec = recs.find((r: any) => r.user_id === uid);
  const avg = recs.length ? recs.reduce((s: number, r: any) => s + r.rating, 0) / recs.length : 0;

  async function postRec() {
    if (!uid) return;
    setPosting(true);
    try {
      const { error } = await supabase.from("recommendations").upsert(
        { user_id: uid, item_id: id, rating, note: note.trim() || null },
        { onConflict: "user_id,item_id" },
      );
      if (error) throw error;
      setNote("");
      toast.success(myRec ? "Updated" : "Added your take");
      qc.invalidateQueries({ queryKey: ["item", id] });
      qc.invalidateQueries({ queryKey: ["feed"] });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Couldn't save");
    } finally {
      setPosting(false);
    }
  }

  async function checkIn() {
    if (!uid) return;
    setChecking(true);
    try {
      const { error } = await supabase.from("check_ins").insert({ user_id: uid, item_id: id });
      if (error) throw error;
      toast.success(`${cat.actionVerb} — noted!`);
      qc.invalidateQueries({ queryKey: ["item", id] });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Couldn't check in");
    } finally {
      setChecking(false);
    }
  }

  const Icon = cat.icon;
  return (
    <div>
      <header className="relative border-b border-border bg-background px-5 pb-6 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <button
          onClick={() => navigate({ to: "/feed" })}
          className="flex items-center gap-2 text-sm text-muted-foreground"
        >
          <ArrowLeft className="h-4 w-4" /> Back
        </button>
        <div className="mt-4 flex items-start gap-4">
          <div className={cn("flex h-20 w-20 shrink-0 items-center justify-center overflow-hidden rounded-2xl", cat.tokenClass)}>
            {item.image_url ? <img src={item.image_url} alt="" className="h-full w-full object-cover" /> : <Icon className="h-9 w-9" />}
          </div>
          <div className="min-w-0 flex-1">
            <span className={cn("inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider", cat.tokenClass)}>
              <Icon className="h-3 w-3" /> {cat.label}
            </span>
            <h1 className="mt-1 font-display text-3xl leading-tight">{item.title}</h1>
            {item.subtitle && <p className="text-sm text-muted-foreground">{item.subtitle}</p>}
            {item.address && (
              <p className="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
                <MapPin className="h-3 w-3" /> {item.address}
              </p>
            )}
          </div>
        </div>
        {recs.length > 0 && (
          <div className="mt-4 flex items-center gap-2">
            <CrownRatingDisplay value={avg} size="md" />
            <span className="text-sm font-semibold tabular-nums">{avg.toFixed(1)}<span className="text-muted-foreground font-normal">/10</span></span>
            <span className="text-sm text-muted-foreground">· {recs.length} rec{recs.length === 1 ? "" : "s"}</span>
          </div>
        )}
        <div className="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-2">
          <Button
            type="button"
            onClick={checkIn}
            disabled={checking}
            variant="outline"
            className="h-11 w-full gap-2 rounded-full border-accent bg-accent/10 text-accent-foreground hover:bg-accent/20"
          >
            <Check className="h-4 w-4" /> {cat.actionVerb}
          </Button>
          <WantButton itemId={id} itemType={item.type as ItemType} />
        </div>
      </header>

      {item.type === "recipe" && (item as any).recipe_text && (
        <RecipeView text={(item as any).recipe_text as string} />
      )}



      <section className="p-5">
        <h2 className="font-display text-2xl">{myRec ? "Update your take" : "Your take"}</h2>
        <div className="mt-3">
          <CrownRatingInput value={rating} onChange={setRating} />
        </div>
        <Textarea
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="What did you love about it?"
          rows={3}
          className="mt-3 rounded-xl"
        />
        <Button onClick={postRec} disabled={posting} className="mt-3 h-12 w-full rounded-full">
          {posting ? "Saving…" : myRec ? "Update" : "Post"}
        </Button>
      </section>

      <ItemEnrichment itemId={id} />

      <section className="border-t border-border p-5">
        <h2 className="font-display text-2xl">What friends say</h2>
        {recs.length === 0 && <p className="mt-2 text-sm text-muted-foreground">No takes yet.</p>}
        <div className="mt-3 space-y-3">
          {recs.map((r: any) => (
            <div key={r.id} className="rounded-2xl bg-card p-4 ring-1 ring-border">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <UserAvatar url={r.profiles?.avatar_url} name={r.profiles?.display_name || r.profiles?.username} size="sm" />
                  <span className="font-medium">{r.profiles?.display_name || r.profiles?.username}</span>
                </div>
                <CrownRatingDisplay value={r.rating} size="xs" />

              </div>
              {r.note && <p className="mt-2 text-sm leading-snug">&ldquo;{r.note}&rdquo;</p>}
              <p className="mt-1 text-[11px] text-muted-foreground">{formatDistanceToNow(new Date(r.created_at), { addSuffix: true })}</p>
              <div className="mt-2 border-t border-border pt-2">
                <LikesComments recommendationId={r.id} />
              </div>
            </div>
          ))}
        </div>

        {checks.length > 0 && (
          <>
            <h3 className="mt-6 text-sm font-semibold uppercase tracking-wider text-muted-foreground">Check-ins</h3>
            <ul className="mt-2 space-y-1.5 text-sm">
              {checks.map((c: any) => (
                <li key={c.id} className="flex items-center gap-2 text-muted-foreground">
                  <Check className="h-3.5 w-3.5 text-accent" />
                  <span className="font-medium text-foreground">{c.profiles?.display_name || c.profiles?.username}</span>
                  <span>{formatDistanceToNow(new Date(c.created_at), { addSuffix: true })}</span>
                </li>
              ))}
            </ul>
          </>
        )}
      </section>
    </div>
  );
}

function RecipeView({ text }: { text: string }) {
  const { ingredients, method, legacy } = parseRecipe(text);
  if (legacy) {
    return (
      <section className="border-b border-border p-5">
        <h2 className="font-display text-2xl">Recipe</h2>
        <pre className="mt-3 whitespace-pre-wrap rounded-2xl bg-card p-4 font-sans text-sm leading-relaxed ring-1 ring-border">
          {legacy}
        </pre>
      </section>
    );
  }
  if (!ingredients.length && !method.length) return null;
  return (
    <section className="space-y-6 border-b border-border p-5">
      <h2 className="font-display text-2xl">Recipe</h2>
      {ingredients.length > 0 && (
        <div className="rounded-2xl bg-card p-4 ring-1 ring-border">
          <h3 className="font-display text-lg">Ingredients</h3>
          <ul className="mt-3 space-y-1.5">
            {ingredients.map((ing, i) => (
              <li key={i} className="flex items-start gap-2 text-sm leading-relaxed">
                <span className="mt-2 h-1.5 w-1.5 flex-none rounded-full bg-primary/70" />
                <span>{ing}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
      {method.length > 0 && (
        <div className="rounded-2xl bg-card p-4 ring-1 ring-border">
          <h3 className="font-display text-lg">Method</h3>
          <ol className="mt-3 space-y-3">
            {method.map((step, i) => (
              <li key={i} className="flex items-start gap-3 text-sm leading-relaxed">
                <span className="mt-0.5 flex h-6 w-6 flex-none items-center justify-center rounded-full bg-primary/15 text-xs font-semibold text-primary">
                  {i + 1}
                </span>
                <span>{step}</span>
              </li>
            ))}
          </ol>
        </div>
      )}
    </section>
  );
}

