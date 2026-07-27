import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { CATEGORIES, type ItemType, categoryMeta } from "@/lib/categories";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import { ArrowLeft, MapPin } from "lucide-react";
import { CrownRatingInput } from "@/components/CrownRating";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/add")({
  head: () => ({
    meta: [
      { title: "Add a recommendation — REX" },
      { name: "description", content: "Recommend a place, book, movie, or show." },
    ],
  }),
  component: AddPage,
});

function AddPage() {
  const navigate = useNavigate();
  const [type, setType] = useState<ItemType | null>(null);
  const [title, setTitle] = useState("");
  const [subtitle, setSubtitle] = useState("");
  const [address, setAddress] = useState("");
  const [note, setNote] = useState("");
  const [rating, setRating] = useState(10);
  const [saving, setSaving] = useState(false);
  const [locating, setLocating] = useState(false);
  const [coords, setCoords] = useState<{ lat: number; lng: number } | null>(null);

  const cat = type ? categoryMeta(type) : null;

  function useMyLocation() {
    if (!navigator.geolocation) {
      toast.error("Location isn't available on this device");
      return;
    }
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setCoords({ lat: pos.coords.latitude, lng: pos.coords.longitude });
        setLocating(false);
        toast.success("Location pinned to your spot");
      },
      () => {
        setLocating(false);
        toast.error("Couldn't get your location");
      },
      { timeout: 8000 },
    );
  }

  async function handleSave() {
    if (!type || !title.trim()) return;
    setSaving(true);
    try {
      const { data: userRes } = await supabase.auth.getUser();
      const uid = userRes.user?.id;
      if (!uid) throw new Error("Not signed in");

      const { data: item, error: itemErr } = await supabase
        .from("items")
        .insert({
          type,
          title: title.trim(),
          subtitle: subtitle.trim() || null,
          address: type === "place" ? address.trim() || null : null,
          lat: type === "place" ? coords?.lat ?? null : null,
          lng: type === "place" ? coords?.lng ?? null : null,
        })
        .select()
        .single();
      if (itemErr) throw itemErr;

      const { error: recErr } = await supabase.from("recommendations").insert({
        user_id: uid,
        item_id: item.id,
        rating,
        note: note.trim() || null,
      });
      if (recErr) throw recErr;

      toast.success("Added to your feed");
      navigate({ to: "/item/$id", params: { id: item.id } });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Couldn't save");
    } finally {
      setSaving(false);
    }
  }

  if (!type) {
    return (
      <div>
        <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
          <button
            onClick={() => navigate({ to: "/feed" })}
            className="flex items-center gap-2 text-sm text-muted-foreground"
          >
            <ArrowLeft className="h-4 w-4" /> Back
          </button>
          <h1 className="mt-3 font-display text-3xl">What are you recommending?</h1>
        </header>
        <div className="grid grid-cols-2 gap-3 p-4">
          {CATEGORIES.map((c) => (
            <button
              key={c.type}
              onClick={() => setType(c.type)}
              className="flex aspect-square flex-col items-center justify-center gap-3 rounded-3xl bg-card ring-1 ring-border transition-transform active:scale-95"
            >
              <div className={cn("flex h-14 w-14 items-center justify-center rounded-2xl", c.tokenClass)}>
                <c.icon className="h-7 w-7" />
              </div>
              <span className="font-display text-2xl">{c.plural}</span>
            </button>
          ))}
        </div>
      </div>
    );
  }

  const CatIcon = cat!.icon;
  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <button
          onClick={() => setType(null)}
          className="flex items-center gap-2 text-sm text-muted-foreground"
        >
          <ArrowLeft className="h-4 w-4" /> Change category
        </button>
        <div className="mt-3 flex items-center gap-3">
          <div className={cn("flex h-10 w-10 items-center justify-center rounded-xl", cat!.tokenClass)}>
            <CatIcon className="h-5 w-5" />
          </div>
          <h1 className="font-display text-3xl">Add a {cat!.label.toLowerCase()}</h1>
        </div>
      </header>

      <div className="space-y-5 p-5">
        <div className="space-y-1.5">
          <Label htmlFor="title">Title</Label>
          <Input
            id="title"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={type === "place" ? "e.g. Osteria Mozza" : type === "book" ? "e.g. The Overstory" : "Title"}
            className="h-12 rounded-xl"
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="subtitle">{cat!.subtitleLabel}</Label>
          <Input
            id="subtitle"
            value={subtitle}
            onChange={(e) => setSubtitle(e.target.value)}
            placeholder={cat!.subtitleLabel}
            className="h-12 rounded-xl"
          />
        </div>

        {type === "place" && (
          <div className="space-y-1.5">
            <Label htmlFor="address">Address</Label>
            <Input
              id="address"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder="Street, city"
              className="h-12 rounded-xl"
            />
            <Button
              type="button"
              variant="outline"
              onClick={useMyLocation}
              disabled={locating}
              className="mt-2 h-11 w-full gap-2 rounded-xl"
            >
              <MapPin className="h-4 w-4" />
              {coords ? "Location pinned ✓" : locating ? "Getting location…" : "Use my current location"}
            </Button>
          </div>
        )}

        <div className="space-y-2">
          <Label>Your rating</Label>
          <CrownRatingInput value={rating} onChange={setRating} />
        </div>


        <div className="space-y-1.5">
          <Label htmlFor="note">Why do you recommend it?</Label>
          <Textarea
            id="note"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="One or two lines your friends will love reading…"
            rows={4}
            className="rounded-xl"
          />
        </div>

        <Button
          type="button"
          onClick={handleSave}
          disabled={saving || !title.trim()}
          className="h-14 w-full rounded-full text-base font-semibold shadow-lg shadow-primary/30"
        >
          {saving ? "Saving…" : "Post recommendation"}
        </Button>
      </div>
    </div>
  );
}
