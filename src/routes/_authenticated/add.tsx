import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

import { CATEGORIES, type ItemType, categoryMeta, PLACE_SUBCATEGORIES, normalizePlaceSubcategory, subcategoriesFor, joinGenres } from "@/lib/categories";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import { ArrowLeft, MapPin, FileUp, Info } from "lucide-react";
import { CrownRatingInput } from "@/components/CrownRating";
import { cn } from "@/lib/utils";
import { SearchPicker, type AnyHit } from "@/components/SearchPicker";
import type { SearchHit } from "@/lib/search.functions";
import { getPlacePhotoUrl } from "@/lib/places.functions";
import { useServerFn } from "@tanstack/react-start";
import { RecipeEditor } from "@/components/RecipeEditor";
import { PhotoUploader } from "@/components/PhotoUploader";
import { TagsInput } from "@/components/TagsInput";
import { TripStopsBuilder, type DraftStop } from "@/components/TripStopsBuilder";

export const Route = createFileRoute("/_authenticated/add")({
  validateSearch: (search: Record<string, unknown>) => ({
    trip: typeof search.trip === "string" ? search.trip : undefined,
  }),
  head: () => ({
    meta: [
      { title: "Add a Rex — REX" },
      { name: "description", content: "Post a Rex for a place, trip, book, movie, show, or recipe." },
    ],
  }),
  component: AddPage,
});

function AddPage() {
  const navigate = useNavigate();
  const { trip: tripId } = Route.useSearch();
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
  const [placeSubs, setPlaceSubs] = useState<string[]>([]);
  const [justAdded, setJustAdded] = useState<{ itemId: string; recId: string; title: string; isTrip: boolean; inTrip: boolean; stopCount?: number } | null>(null);
  const [photos, setPhotos] = useState<string[]>([]);
  const [tags, setTags] = useState<string[]>([]);
  const [showTripInfo, setShowTripInfo] = useState(false);
  const [tripStops, setTripStops] = useState<DraftStop[]>([]);
  const { data: uid } = useQuery({
    queryKey: ["current-user-id"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    staleTime: 5 * 60 * 1000,
  });

  const cat = type ? categoryMeta(type) : null;
  const needsSearch = type !== null && type !== "recipe" && type !== "other" && type !== "trip";
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
    setPlaceSubs([]);
    setTags([]);
    setJustAdded(null);
    setPhotos([]);
    setTripStops([]);
  }


  async function handlePick(hit: AnyHit) {
    setPicked(hit);
    setTitle(hit.title);
    const isGooglePlace = hit.external_source === "google_places";
    const isTmEvent = hit.external_source === "ticketmaster_event";
    setSubtitle(isGooglePlace ? "" : hit.subtitle ?? "");
    if (isGooglePlace || isTmEvent) {
      if ("address" in hit && hit.address) setAddress(hit.address);
      if (isGooglePlace) {
        const guess = normalizePlaceSubcategory(hit.genre);
        if (guess) setPlaceSubs([guess]);
      }
      if ("lat" in hit && "lng" in hit && typeof hit.lat === "number" && typeof hit.lng === "number") {
        setCoords({ lat: hit.lat, lng: hit.lng });
      }
      if (isGooglePlace && "photo_name" in hit && hit.photo_name) {
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
            address: type === "place" || type === "event" ? address.trim() || null : null,
            lat: type === "place" || type === "event" ? coords?.lat ?? null : null,
            lng: type === "place" || type === "event" ? coords?.lng ?? null : null,
            genre: joinGenres(placeSubs) ?? (picked?.genre ?? null),
            ...(type === "recipe" && recipeText.trim() ? { recipe_text: recipeText } : {}),
          } as never)
          .select("id")
          .single();
        if (itemErr) throw itemErr;
        itemId = item.id;
      }

      const { data: rec, error: recErr } = await supabase
        .from("recommendations")
        .insert({
          user_id: uid,
          item_id: itemId!,
          rating,
          note: note.trim() || null,
          photo_url: photos[0] ?? null,
          photo_urls: photos,
          tags,
          trip_id: tripId ?? null,
        } as never)
        .select("id")
        .single();
      if (recErr) throw recErr;

      let savedStops = 0;
      if (type === "trip" && tripStops.length > 0) {
        for (const stop of tripStops) {
          let stopItemId: string | undefined;
          if (stop.external_source && stop.external_id) {
            const { data: existing } = await supabase
              .from("items")
              .select("id")
              .eq("external_source", stop.external_source)
              .eq("external_id", stop.external_id)
              .maybeSingle();
            stopItemId = existing?.id;
          }
          if (!stopItemId) {
            const { data: stopItem, error: stopItemErr } = await supabase
              .from("items")
              .insert({
                type: stop.type,
                title: stop.title,
                subtitle: stop.subtitle,
                image_url: stop.image_url,
                external_id: stop.external_id,
                external_source: stop.external_source,
                address: stop.address,
                lat: stop.lat,
                lng: stop.lng,
                genre: stop.genre,
              } as never)
              .select("id")
              .single();
            if (stopItemErr) throw stopItemErr;
            stopItemId = stopItem.id;
          }
          const { error: stopRecErr } = await supabase.from("recommendations").insert({
            user_id: uid,
            item_id: stopItemId!,
            rating: stop.rating,
            note: stop.note || null,
            photo_urls: [],
            tags: [],
            trip_id: rec.id,
            trip_section: stop.section,
          } as never);

          if (stopRecErr) throw stopRecErr;
          savedStops += 1;
        }
      }

      toast.success(
        tripId
          ? "Added to your trip"
          : savedStops > 0
            ? `Trip posted with ${savedStops} ${savedStops === 1 ? "stop" : "stops"}`
            : "Added to your feed",
      );
      setJustAdded({
        itemId: itemId!,
        recId: rec.id,
        title: title.trim(),
        isTrip: type === "trip",
        inTrip: Boolean(tripId),
        stopCount: savedStops,
      });
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
          {justAdded.isTrip ? "🧳" : "🦖"}
        </div>
        <div>
          <h1 className="font-display text-3xl">Nice one!</h1>
          <p className="mt-2 text-muted-foreground">
            {justAdded.isTrip
              ? justAdded.stopCount
                ? `"${justAdded.title}" is live with ${justAdded.stopCount} ${justAdded.stopCount === 1 ? "stop" : "stops"} — each one is a Rex of its own too.`
                : `"${justAdded.title}" is live — now add the places you loved on it.`
              : justAdded.inTrip
              ? `"${justAdded.title}" is now a Rex of its own and a stop on your trip.`
              : `"${justAdded.title}" is in your feed.`}
          </p>
        </div>
        <div className="flex w-full max-w-sm flex-col gap-2">
          {justAdded.isTrip ? (
            <>
              <Button
                onClick={() => navigate({ to: "/trip/$id", params: { id: justAdded.recId } })}
                className="h-14 w-full rounded-full text-base font-semibold shadow-lg shadow-primary/30"
              >
                {justAdded.stopCount ? "View trip" : "Add Rex to this trip"}
              </Button>
              <Button variant="ghost" onClick={() => navigate({ to: "/feed" })} className="h-12 w-full rounded-full">
                Back to feed
              </Button>
            </>
          ) : justAdded.inTrip ? (
            <>
              <Button
                onClick={resetForm}
                className="h-14 w-full rounded-full text-base font-semibold shadow-lg shadow-primary/30"
              >
                Add another Rex to this trip
              </Button>
              <Button
                variant="outline"
                onClick={() => navigate({ to: "/trip/$id", params: { id: tripId! } })}
                className="h-12 w-full rounded-full"
              >
                View trip
              </Button>
              <Button variant="ghost" onClick={() => navigate({ to: "/feed" })} className="h-12 w-full rounded-full">
                Back to feed
              </Button>
            </>
          ) : (
            <>
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
                View Rex
              </Button>
              <Button
                variant="ghost"
                onClick={() => navigate({ to: "/feed" })}
                className="h-12 w-full rounded-full"
              >
                Back to feed
              </Button>
            </>
          )}
        </div>
      </div>

    );
  }

  if (!type) {
    return (
      <div>
        <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
          <button
            onClick={() => (tripId ? navigate({ to: "/trip/$id", params: { id: tripId } }) : navigate({ to: "/feed" }))}
            className="flex items-center gap-2 text-sm text-muted-foreground"
          >
            <ArrowLeft className="h-4 w-4" /> {tripId ? "Back to trip" : "Back"}
          </button>
          <h1 className="mt-3 font-display text-3xl">
            {tripId ? "What are you adding to this trip?" : "What are you Rexing?"}
          </h1>
          {tripId && (
            <p className="mt-1 text-sm text-muted-foreground">
              Restaurants, museums, bars, hotels — each becomes its own Rex and a stop on the trip.
            </p>
          )}
        </header>
        <div className="grid grid-cols-2 gap-2 p-4 pb-2">
          {CATEGORIES.filter((c) => !(tripId && c.type === "trip")).map((c) => (
            <button
              key={c.type}
              onClick={() => setType(c.type)}
              className="relative flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border transition-transform active:scale-95"
            >
              <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-xl", c.tokenClass)}>
                <c.icon className="h-5 w-5" />
              </div>
              <span className="min-w-0 truncate font-display text-base">{c.plural}</span>
              {c.type === "trip" && (
                <span
                  role="button"
                  tabIndex={0}
                  aria-label="What's a trip?"
                  onClick={(e) => { e.stopPropagation(); setShowTripInfo((s) => !s); }}
                  onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); e.stopPropagation(); setShowTripInfo((s) => !s); } }}
                  className="absolute right-1.5 top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-muted text-muted-foreground hover:text-foreground"
                >
                  <Info className="h-3 w-3" />
                </span>
              )}
            </button>
          ))}
        </div>

        <div className="px-4 pb-2">
          {showTripInfo ? (
            <div className="relative rounded-2xl bg-primary/10 p-4 text-sm ring-1 ring-primary/30">
              <div className="absolute -top-1.5 right-8 h-3 w-3 rotate-45 bg-primary/10 ring-1 ring-primary/30" />
              <p className="font-display text-base">Place vs. Trip 🧳</p>
              <p className="mt-1 text-muted-foreground">
                A <strong className="text-foreground">Place</strong> is one spot — a restaurant, bar or hotel you'd
                recommend on its own.
              </p>
              <p className="mt-1.5 text-muted-foreground">
                A <strong className="text-foreground">Trip</strong> ties several places together — &ldquo;Lisbon, 3
                days&rdquo;. It shows in the feed as one card, and tapping it opens a mini-feed of every Rex on that
                trip.
              </p>
              <button
                type="button"
                onClick={() => setShowTripInfo(false)}
                className="mt-2 text-xs font-medium text-primary underline"
              >
                Got it
              </button>
            </div>
          ) : (
            <button
              type="button"
              onClick={() => setShowTripInfo(true)}
              className="flex items-center gap-1.5 text-xs text-muted-foreground underline"
            >
              <Info className="h-3.5 w-3.5" /> What's the difference between a Place and a Trip?
            </button>
          )}
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
              <p className="font-display text-lg">Import a collection</p>
              <p className="text-sm text-muted-foreground">Pull Rex from a Google Sheet or Word doc.</p>
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
        {tripId && (
          <div className="rounded-2xl bg-primary/10 p-3 text-sm ring-1 ring-primary/30">
            🧳 This Rex will be added as a stop on your trip.
          </div>
        )}
        {type === "trip" && (
          <div className="rounded-2xl bg-primary/10 p-4 text-sm ring-1 ring-primary/30">
            <p className="font-display text-base">What's a trip?</p>
            <p className="mt-1 text-muted-foreground">
              Name the trip (e.g. &ldquo;Lisbon, 3 days&rdquo;) and add the places you loved as stops below — friends
              see one trip card in the feed and can tap in for the full itinerary.
            </p>
          </div>
        )}

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

        {subcategoriesFor(type).length > 0 && (
          <div className="space-y-1.5">
            <Label>
              {type === "place" ? "Type of place" : `Type of ${cat!.label.toLowerCase()}`}
              <span className="ml-1 font-normal text-muted-foreground">(pick any that apply)</span>
            </Label>
            <div className="flex flex-wrap gap-2">
              {subcategoriesFor(type).map((s) => {
                const active = placeSubs.includes(s);
                return (
                  <button
                    key={s}
                    type="button"
                    onClick={() =>
                      setPlaceSubs((prev) => (prev.includes(s) ? prev.filter((p) => p !== s) : [...prev, s]))
                    }
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
        )}

        {type === "place" && (
          <>
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
          <Label htmlFor="note">Why are you Rexing it?</Label>
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

        {type === "trip" && <TripStopsBuilder value={tripStops} onChange={setTripStops} />}

        <div className="space-y-1.5">
          <Label>Tags</Label>
          <TagsInput
            value={tags}
            onChange={setTags}
            placeholder={type === "place" ? "e.g. private dining, date night, dog friendly" : "Add tags (press enter)"}
            suggestions={
              type === "place"
                ? ["private dining", "date night", "outdoor seating", "dog friendly", "kid friendly"]
                : type === "recipe"
                ? ["quick", "gluten free", "vegetarian", "meal prep"]
                : []
            }
          />
        </div>

        <Button
          type="button"
          onClick={handleSave}
          disabled={saving || !title.trim()}
          className="h-14 w-full rounded-full text-base font-semibold shadow-lg shadow-primary/30"
        >
          {saving
            ? "Saving…"
            : type === "trip"
              ? tripStops.length > 0
                ? `Post trip with ${tripStops.length} ${tripStops.length === 1 ? "stop" : "stops"}`
                : "Post trip"
              : "Post Rex"}
        </Button>
          </>
        )}
      </div>
    </div>
  );
}
