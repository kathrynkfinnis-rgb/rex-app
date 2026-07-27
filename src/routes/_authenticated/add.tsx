import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
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
import { SearchPicker, type AnyHit } from "@/components/SearchPicker";
import type { SearchHit } from "@/lib/search.functions";
import { getPlacePhotoUrl } from "@/lib/places.functions";
import { useServerFn } from "@tanstack/react-start";

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
  const [picked, setPicked] = useState<AnyHit | null>(null);
  const [manualMode, setManualMode] = useState(false);

  const cat = type ? categoryMeta(type) : null;
  const needsSearch = type !== null;
  const showForm = !needsSearch || picked || manualMode;
  const photoFn = useServerFn(getPlacePhotoUrl);

  async function handlePick(hit: AnyHit) {
    setPicked(hit);
    setTitle(hit.title);
    setSubtitle(hit.external_source === "google_places" ? "" : hit.subtitle ?? "");
    if (hit.external_source === "google_places") {
      if (hit.address) setAddress(hit.address);
      if (typeof hit.lat === "number" && typeof hit.lng === "number") {
        setCoords({ lat: hit.lat, lng: hit.lng });
      }
      if (hit.photo_name) {
        try {
          const url = await photoFn({ data: { photoName: hit.photo_name, maxWidth: 800 } });
          if (url) {
            setPicked((prev) => (prev ? { ...prev, image_url: url } : prev));
          }
        } catch {
          // photo is optional — ignore
        }
      }
    }
  }

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

      let itemId: string | undefined;
      if (picked) {
        const { data: existing } = await supabase
          .from("items")
          .select("id")
          .eq("external_source", picked.external_source)
          .eq("external_id", picked.external_id)
          .maybeSingle();
        itemId = existing?.id;
      }
      if (!itemId) {
        const { data: item, error: itemErr } = await supabase
          .from("items")
          .insert({
            type,
            title: title.trim(),
            subtitle: subtitle.trim() || null,
            image_url: picked?.image_url ?? null,
            external_id: picked?.external_id ?? null,
            external_source: picked?.external_source ?? null,
            address: type === "place" ? address.trim() || null : null,
            lat: type === "place" ? coords?.lat ?? null : null,
            lng: type === "place" ? coords?.lng ?? null : null,
            genre: picked?.genre ?? null,
          })
          .select("id")
          .single();
        if (itemErr) throw itemErr;
        itemId = item.id;
      }

      const { error: recErr } = await supabase.from("recommendations").insert({
        user_id: uid,
        item_id: itemId!,
        rating,
        note: note.trim() || null,
      });
      if (recErr) throw recErr;

      toast.success("Added to your feed");
      navigate({ to: "/item/$id", params: { id: itemId! } });
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
        {needsSearch && !showForm && (
          <SearchPicker
            type={type}
            onPick={handlePick}
            onManual={() => setManualMode(true)}
            near={type === "place" ? coords : null}
          />
        )}

        {showForm && (
          <>
            {picked && (
              <div className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border">
                {picked.image_url ? (
                  <img src={picked.image_url} alt="" className="h-16 w-12 flex-none rounded-md object-cover ring-1 ring-border" />
                ) : (
                  <div className="h-16 w-12 flex-none rounded-md bg-muted" />
                )}
                <div className="min-w-0 flex-1">
                  <div className="truncate font-medium">{picked.title}</div>
                  {picked.subtitle && <div className="truncate text-sm text-muted-foreground">{picked.subtitle}</div>}
                </div>
                <button
                  type="button"
                  onClick={() => { setPicked(null); setTitle(""); setSubtitle(""); }}
                  className="text-xs text-muted-foreground underline"
                >
                  Change
                </button>
              </div>
            )}

            {(!picked || type === "place") && (
              <>
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
              </>
            )}

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
          </>
        )}
      </div>
    </div>
  );
}
