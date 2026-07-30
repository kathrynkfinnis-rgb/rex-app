import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { ArrowLeft, Sparkles } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { CATEGORIES, type ItemType } from "@/lib/categories";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/ask/")({
  head: () => ({
    meta: [
      { title: "Ask friends — REX" },
      { name: "description", content: "Ask your friends for a Rex." },
    ],
  }),
  component: AskPage,
});

function AskPage() {
  const navigate = useNavigate();
  const [type, setType] = useState<ItemType | null>(null);
  const [title, setTitle] = useState("");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);

  async function handlePost() {
    if (!title.trim()) return;
    setSaving(true);
    try {
      const { data: userRes } = await supabase.auth.getUser();
      const uid = userRes.user?.id;
      if (!uid) throw new Error("Not signed in");
      const { data, error } = await supabase
        .from("requests")
        .insert({ user_id: uid, type, title: title.trim(), note: note.trim() || null })
        .select("id")
        .single();
      if (error) throw error;
      toast.success("Sent to your friends");
      navigate({ to: "/ask/$id", params: { id: data.id } });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Couldn't post");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <button onClick={() => navigate({ to: "/feed" })} className="flex items-center gap-2 text-sm text-muted-foreground">
          <ArrowLeft className="h-4 w-4" /> Back
        </button>
        <div className="mt-3 flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-accent/20 text-accent-foreground">
            <Sparkles className="h-5 w-5" />
          </div>
          <h1 className="font-display text-3xl">Ask friends</h1>
        </div>
        <p className="mt-2 text-sm text-muted-foreground">
          Put out a blast for a Rex — friends will see it in their feed and can chime in.
        </p>
      </header>

      <div className="space-y-5 p-5">
        <div className="space-y-1.5">
          <Label>Category (optional)</Label>
          <div className="flex flex-wrap gap-2">
            {CATEGORIES.map((c) => {
              const active = type === c.type;
              const Icon = c.icon;
              return (
                <button
                  key={c.type}
                  type="button"
                  onClick={() => setType(active ? null : c.type)}
                  className={cn(
                    "flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm ring-1 transition-colors",
                    active ? "bg-primary text-primary-foreground ring-primary" : "bg-card text-foreground ring-border hover:bg-muted",
                  )}
                >
                  <Icon className="h-3.5 w-3.5" />
                  {c.label}
                </button>
              );
            })}
          </div>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="title">What are you looking for?</Label>
          <Input
            id="title"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="e.g. Great ramen spot in Tokyo"
            className="h-12 rounded-xl"
          />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="note">More detail (optional)</Label>
          <Textarea
            id="note"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            rows={4}
            placeholder="Add any context — budget, vibe, dates, who it's for…"
            className="rounded-xl"
          />
        </div>

        <Button
          type="button"
          onClick={handlePost}
          disabled={saving || !title.trim()}
          className="h-14 w-full rounded-full text-base font-semibold shadow-lg shadow-primary/30"
        >
          {saving ? "Posting…" : "Post ask"}
        </Button>
      </div>
    </div>
  );
}
