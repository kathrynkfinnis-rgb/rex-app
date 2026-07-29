import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

import { CATEGORIES, type ItemType, categoryMeta, PLACE_SUBCATEGORIES, normalizePlaceSubcategory, subcategoriesFor } from "@/lib/categories";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import { ArrowLeft, MapPin, FileUp } from "lucide-react";
import { CrownRatingInput } from "@/components/CrownRating";
import { cn } from "@/lib/utils";
import { SearchPicker, type AnyHit } from "@/components/SearchPicker";
import type { SearchHit } from "@/lib/search.functions";
import { getPlacePhotoUrl } from "@/lib/places.functions";
import { useServerFn } from "@tanstack/react-start";
import { RecipeEditor } from "@/components/RecipeEditor";
import { PhotoUploader } from "@/components/PhotoUploader";

export const Route = createFileRoute("/_authenticated/add")({
  head: () => ({
    meta: [
      { title: "Add a recommendation — REX" },
      { name: "description", content: "Recommend a place, book, movie, show, or recipe." },
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
  const [recipeText, setRecipeText] = useState("");
  const [rating, setRating] = useState(10);
  const [saving, setSaving] = useState(false);
  const [locating, setLocating] = useState(false);
  const [coords, setCoords] = useState<{ lat: number; lng: number } | null>(null);
  const [picked, setPicked] = useState<AnyHit | null>(null);
  const [manualMode, setManualMode] = useState(false);
  const [placeSub, setPlaceSub] = useState<string>("");
  const [justAdded, setJustAdded] = useState<{ itemId: string; title: string } | null>(null);
  const [photos, setPhotos] = useState<string[]>([]);
  const { data: uid } = useQuery({
    queryKey: ["current-user-id"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    staleTime: 5 * 60 * 1000,
  });

  const cat = type ? categoryMeta(type) : null;
  const needsSearch = type !== null && type !== "recipe" && type !== "event";
  const showForm = !needsSearch || picked || manualMode;
  const photoFn = useServerFn(getPlacePhotoUrl);

  function resetForm() {
    setType(null);
    setTitle("");
    setSubtitle("");
    setAddress("");
    setNote("");
    setRecipeText("");
    setRating(10);
    setCoords(null);
    setPicked(null);
    setManualMode(false);
    setPlaceSub("");
    setJustAdded(null);
    setPhotos([]);
  }


  async function handlePick(hit: AnyHit) {
    setPicked(hit);
    setTitle(hit.title);
    setSubtitle(hit.external_source === "google_places" ? "" : hit.subtitle ?? "");
    if (hit.external_source === "google_places") {
      if (hit.address) setAddress(hit.address);
      const guess = normalizePlaceSubcategory(hit.genre);
      if (guess) setPlaceSub(guess);
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
            genre: type === "place" ? (placeSub || null) : (picked?.genre ?? null),
            ...(type === "recipe" && recipeText.trim() ? { recipe_text: recipeText } : {}),
          } as never)
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
        photo_url: photos[0] ?? null,
        photo_urls: photos,
      } as never);
      if (recErr) throw recErr;

      toast.success("Added to your feed");
      setJustAdded({ itemId: itemId!, title: title.trim() });
    } catch (err) {

      toast.error(err instanceof Error ? err.message : "Couldn't save");
    } finally {
      setSaving(false);
    }
  }

  if (justAdded) {
    return (
      <div className="flex min-h-[70vh] flex-col items-center justify-center gap-6 p-6 text-center">
        <div className="flex h-20 w-20 items-center justify-center rounded-full bg-primary/15 text-4xl">
          🦖
        </div>
        <div>
          <h1 className="font-display text-3xl">Nice one!</h1>
          <p className="mt-2 text-muted-foreground">
            "{justAdded.title}" is in your feed.
          </p>
        </div>
        <div className="flex w-full max-w-sm flex-col gap-2">
          <Button
            onClick={resetForm}
            className="h-14 w-full rounded-full text-base font-semibold shadow-lg shadow-primary/30"
          >
            Add another
          </Button>
          <Button
            variant="outline"
            onClick={() => navigate({ to: "/item/$id", params: { id: justAdded.itemId } })}
            className="h-12 w-full rounded-full"
          >
            View recommendation
          </Button>
          <Button
            variant="ghost"
            onClick={() => navigate({ to: "/feed" })}
            className="h-12 w-full rounded-full"
          >
            Back to feed
          </Button>
        </div>
      </div>
    );
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
        <div className="grid grid-cols-2 gap-2 p-4">
          {CATEGORIES.map((c) => (
            <button
              key={c.type}
              onClick={() => setType(c.type)}
              className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border transition-transform active:scale-95"
            >
              <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-xl", c.tokenClass)}>
                <c.icon className="h-5 w-5" />
              </div>
              <span className="min-w-0 truncate font-display text-base">{c.plural}</span>
            </button>
          ))}
        </div>

        <div className="px-4 pb-4">
          <Link
            to="/import"
            className="flex items-center gap-3 rounded-2xl bg-card p-4 ring-1 ring-border transition-colors active:scale-[0.99]"
          >
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10 text-primary">
              <FileUp className="h-6 w-6" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="font-display text-lg">Import a list</p>
              <p className="text-sm text-muted-foreground">Pull recommendations from a Google Sheet or Word doc.</p>
            </div>
          </Link>
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
          <>
            <div className="space-y-1.5">
              <Label>Type of place</Label>
              <div className="flex flex-wrap gap-2">
                {PLACE_SUBCATEGORIES.map((s) => {
                  const active = placeSub === s;
                  return (
                    <button
                      key={s}
                      type="button"
                      onClick={() => setPlaceSub(active ? "" : s)}
                      className={cn(
                        "rounded-full px-3 py-1.5 text-sm ring-1 transition-colors",
                        active
                          ? "bg-primary text-primary-foreground ring-primary"
                          : "bg-card text-foreground ring-border hover:bg-muted",
                      )}
                    >
                      {s}
                    </button>
                  );
                })}
              </div>
            </div>
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
          </>
        )}

        {type === "recipe" && (
          <div className="rounded-2xl bg-card p-4 ring-1 ring-border">
            <RecipeEditor value={recipeText} onChange={setRecipeText} />
            <p className="mt-4 text-xs text-muted-foreground">
              Saved on the recipe so friends can cook it in-app.
            </p>
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

        {uid && (
          <div className="space-y-1.5">
            <Label>Photos</Label>
            <PhotoUploader userId={uid} value={photos} onChange={setPhotos} />
          </div>
        )}

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
