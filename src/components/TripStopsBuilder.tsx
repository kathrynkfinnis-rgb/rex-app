import { useState } from "react";
import { Plus, X, GripVertical } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { CrownRatingInput, CrownRatingDisplay } from "@/components/CrownRating";
import { SearchPicker, type AnyHit } from "@/components/SearchPicker";
import { CATEGORIES, categoryMeta, type ItemType } from "@/lib/categories";
import { cn } from "@/lib/utils";

export type DraftStop = {
  key: string;
  type: ItemType;
  title: string;
  subtitle: string | null;
  address: string | null;
  lat: number | null;
  lng: number | null;
  genre: string | null;
  image_url: string | null;
  external_id: string | null;
  external_source: string | null;
  rating: number;
  note: string;
  /** Optional heading this stop sits under, e.g. "Brunch" or "Museums". */
  section: string | null;
};

const STOP_TYPES: ItemType[] = CATEGORIES.map((c) => c.type).filter((t) => t !== "trip");

export const SECTION_SUGGESTIONS = [
  "Breakfast",
  "Brunch",
  "Lunch",
  "Dinner",
  "Coffee",
  "Drinks",
  "Museums",
  "Sights",
  "Shopping",
  "Stay",
  "Nightlife",
];

type Props = {
  value: DraftStop[];
  onChange: (stops: DraftStop[]) => void;
};


export function TripStopsBuilder({ value, onChange }: Props) {
  const [open, setOpen] = useState(false);
  const [type, setType] = useState<ItemType>("place");
  const [picked, setPicked] = useState<AnyHit | null>(null);
  const [manual, setManual] = useState(false);
  const [title, setTitle] = useState("");
  const [subtitle, setSubtitle] = useState("");
  const [rating, setRating] = useState(10);
  const [note, setNote] = useState("");

  const needsSearch = type !== "recipe" && type !== "other";
  const showForm = !needsSearch || picked || manual;

  function reset() {
    setPicked(null);
    setManual(false);
    setTitle("");
    setSubtitle("");
    setRating(10);
    setNote("");
    setType("place");
  }

  function pick(hit: AnyHit) {
    setPicked(hit);
    setTitle(hit.title);
    setSubtitle(hit.external_source === "google_places" ? "" : hit.subtitle ?? "");
  }

  function addStop() {
    if (!title.trim()) return;
    const hit = picked as (AnyHit & { address?: string; lat?: number; lng?: number }) | null;
    onChange([
      ...value,
      {
        key: crypto.randomUUID(),
        type,
        title: title.trim(),
        subtitle: subtitle.trim() || null,
        address: hit?.address ?? null,
        lat: typeof hit?.lat === "number" ? hit.lat : null,
        lng: typeof hit?.lng === "number" ? hit.lng : null,
        genre: hit?.genre ?? null,
        image_url: hit?.image_url ?? null,
        external_id: hit?.external_id ?? null,
        external_source: hit?.external_source ?? null,
        rating,
        note: note.trim(),
      },
    ]);
    reset();
    setOpen(false);
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <Label>Stops on this trip</Label>
        <span className="text-xs text-muted-foreground">
          {value.length} {value.length === 1 ? "stop" : "stops"}
        </span>
      </div>

      {value.length > 0 && (
        <ol className="space-y-2">
          {value.map((s, i) => {
            const meta = categoryMeta(s.type);
            const Icon = meta.icon;
            return (
              <li key={s.key} className="flex items-start gap-2 rounded-2xl bg-card p-3 ring-1 ring-border">
                <span className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary/15 text-[11px] font-bold text-primary">
                  {i + 1}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-widest text-muted-foreground">
                    <Icon className="h-3.5 w-3.5" /> {meta.label}
                  </div>
                  <div className="truncate font-medium">{s.title}</div>
                  {s.subtitle && <div className="truncate text-sm text-muted-foreground">{s.subtitle}</div>}
                  <div className="mt-1">
                    <CrownRatingDisplay value={s.rating} size="xs" showNumber />
                  </div>
                  {s.note && <p className="mt-1 text-sm text-muted-foreground">{s.note}</p>}
                </div>
                <button
                  type="button"
                  aria-label={`Remove ${s.title}`}
                  onClick={() => onChange(value.filter((v) => v.key !== s.key))}
                  className="rounded-full p-1 text-muted-foreground hover:text-foreground"
                >
                  <X className="h-4 w-4" />
                </button>
              </li>
            );
          })}
        </ol>
      )}

      {!open && (
        <Button
          type="button"
          variant="outline"
          onClick={() => setOpen(true)}
          className="h-12 w-full gap-2 rounded-xl"
        >
          <Plus className="h-4 w-4" /> Add a stop
        </Button>
      )}

      {open && (
        <div className="space-y-4 rounded-2xl bg-card p-4 ring-1 ring-border">
          <div className="flex items-center justify-between">
            <p className="font-display text-base">New stop</p>
            <button
              type="button"
              onClick={() => {
                reset();
                setOpen(false);
              }}
              className="text-xs text-muted-foreground underline"
            >
              Cancel
            </button>
          </div>

          <div className="flex flex-wrap gap-2">
            {STOP_TYPES.map((t) => {
              const meta = categoryMeta(t);
              return (
                <button
                  key={t}
                  type="button"
                  onClick={() => {
                    setType(t);
                    setPicked(null);
                    setManual(false);
                    setTitle("");
                    setSubtitle("");
                  }}
                  className={cn(
                    "rounded-full px-3 py-1.5 text-sm ring-1 transition-colors",
                    type === t
                      ? "bg-primary text-primary-foreground ring-primary"
                      : "bg-background text-foreground ring-border hover:bg-muted",
                  )}
                >
                  {meta.label}
                </button>
              );
            })}
          </div>

          {needsSearch && !showForm && (
            <SearchPicker type={type} onPick={pick} onManual={() => setManual(true)} />
          )}

          {showForm && (
            <>
              {picked ? (
                <div className="flex items-center gap-3 rounded-xl bg-background p-3 ring-1 ring-border">
                  <GripVertical className="h-4 w-4 shrink-0 text-muted-foreground" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-medium">{picked.title}</div>
                    {picked.subtitle && (
                      <div className="truncate text-sm text-muted-foreground">{picked.subtitle}</div>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      setPicked(null);
                      setTitle("");
                      setSubtitle("");
                    }}
                    className="text-xs text-muted-foreground underline"
                  >
                    Change
                  </button>
                </div>
              ) : (
                <>
                  <div className="space-y-1.5">
                    <Label htmlFor="stop-title">Title</Label>
                    <Input
                      id="stop-title"
                      value={title}
                      onChange={(e) => setTitle(e.target.value)}
                      placeholder="e.g. Time Out Market"
                      className="h-12 rounded-xl"
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label htmlFor="stop-subtitle">{categoryMeta(type).subtitleLabel}</Label>
                    <Input
                      id="stop-subtitle"
                      value={subtitle}
                      onChange={(e) => setSubtitle(e.target.value)}
                      placeholder={categoryMeta(type).subtitleLabel}
                      className="h-12 rounded-xl"
                    />
                  </div>
                </>
              )}

              <div className="space-y-2">
                <Label>Your rating</Label>
                <CrownRatingInput value={rating} onChange={setRating} />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="stop-note">Why are you Rexing it?</Label>
                <Textarea
                  id="stop-note"
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  rows={3}
                  placeholder="One line your friends will love…"
                  className="rounded-xl"
                />
              </div>

              <Button
                type="button"
                onClick={addStop}
                disabled={!title.trim()}
                className="h-12 w-full rounded-full font-semibold"
              >
                Add stop
              </Button>
            </>
          )}
        </div>
      )}

      <p className="text-xs text-muted-foreground">
        Each stop becomes its own Rex as well as part of the trip. You can always add more later.
      </p>
    </div>
  );
}
