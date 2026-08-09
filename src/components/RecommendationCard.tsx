import { Link } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { cn } from "@/lib/utils";
import { LikesComments } from "@/components/LikesComments";
import { EditRecommendationDialog } from "@/components/EditRecommendationDialog";
import { categoryMeta, splitGenres, type ItemType } from "@/lib/categories";
import { supabase } from "@/integrations/supabase/client";
import { formatDistanceToNow } from "date-fns";
import { Pencil, Crown, Trash2 } from "lucide-react";
import { UserAvatar } from "@/components/UserAvatar";
import { SavePostButton } from "@/components/SavePostButton";
import { ShareButton } from "@/components/ShareButton";
import { ShareToGroupButton } from "@/components/ShareToGroupButton";
import { AlsoRecommendedBy } from "@/components/AlsoRecommendedBy";
import { TopRexxerCrown } from "@/components/TopRexxers";
import { PhotoCarousel } from "@/components/PhotoCarousel";



const SHARE_SITE = "https://pocket-app-pioneers.lovable.app";



export type FeedRow = {
  id: string;
  rating: number;
  note: string | null;
  created_at: string;
  photo_url: string | null;
  photo_urls?: string[] | null;
  tags?: string[] | null;
  user_id: string;
  item_id: string;
  trip_id?: string | null;
  items: {
    id: string;
    type: ItemType;
    title: string;
    subtitle: string | null;
    image_url: string | null;
    genre: string | null;
  } | null;
  profiles: {
    username: string;
    display_name: string | null;
    avatar_url: string | null;
  } | null;
  creators?: {
    slug: string;
    name: string;
    color: string;
    emoji: string | null;
  } | null;
};

export function RecommendationCard({ rec }: { rec: FeedRow }) {
  const item = rec.items;
  const author = rec.profiles;
  const creator = rec.creators;
  const [editing, setEditing] = useState(false);
  const { data: currentUserId } = useQuery({
    queryKey: ["current-user-id"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    staleTime: 5 * 60 * 1000,
  });
  const { data: tripStops } = useQuery({
    queryKey: ["trip-stop-count", rec.id],
    enabled: rec.items?.type === "trip",
    staleTime: 60_000,
    queryFn: async () => {
      const { count } = await supabase
        .from("recommendations")
        .select("id", { count: "exact", head: true })
        .eq("trip_id", rec.id);
      return count ?? 0;
    },
  });
  const qc = useQueryClient();
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [offset, setOffset] = useState(0);
  const start = useRef<{ x: number; y: number; base: number } | null>(null);
  const axis = useRef<"none" | "x" | "y">("none");
  const del = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from("recommendations").delete().eq("id", rec.id);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Rex deleted");
      qc.invalidateQueries();
      setConfirmDelete(false);
      setOffset(0);
    },
    onError: (e: any) => toast.error(e.message ?? "Couldn't delete"),
  });
  if (!item) return null;
  const cat = categoryMeta(item.type);
  const Icon = cat.icon;
  const isOwner = currentUserId && currentUserId === rec.user_id;
  const isTrip = item.type === "trip";
  const swipeHandlers = isOwner
    ? {
        onTouchStart: (e: React.TouchEvent) => {
          const t = e.touches[0];
          start.current = { x: t.clientX, y: t.clientY, base: offset };
          axis.current = "none";
        },
        onTouchMove: (e: React.TouchEvent) => {
          if (!start.current) return;
          const t = e.touches[0];
          const dx = t.clientX - start.current.x;
          const dy = t.clientY - start.current.y;
          if (axis.current === "none") {
            if (Math.abs(dx) > 10 && Math.abs(dx) > Math.abs(dy)) axis.current = "x";
            else if (Math.abs(dy) > 10) axis.current = "y";
          }
          if (axis.current !== "x") return;
          const next = Math.min(96, Math.max(0, start.current.base - dx));
          setOffset(next);
        },
        onTouchEnd: () => {
          if (axis.current === "x") setOffset(offset > 48 ? 88 : 0);
          start.current = null;
          axis.current = "none";
        },
      }
    : {};
  return (
    <>
    <div className="relative overflow-hidden rounded-2xl">
      {isOwner && (
        <button
          type="button"
          onClick={() => setConfirmDelete(true)}
          className="absolute inset-y-0 right-0 flex w-[88px] items-center justify-center bg-destructive text-destructive-foreground"
          aria-label="Delete Rex"
        >
          <Trash2 className="h-5 w-5" />
        </button>
      )}
    <article
      {...swipeHandlers}
      className="relative overflow-hidden rounded-2xl bg-card shadow-sm ring-1 ring-border touch-pan-y"
      style={{
        transform: `translateX(-${offset}px)`,
        transition: start.current ? "none" : "transform 200ms ease",
        ...(creator ? { borderLeft: `4px solid ${creator.color}` } : {}),
      }}
    >
      {isOwner && (
        <button
          type="button"
          onClick={(e) => {
            e.preventDefault();
            e.stopPropagation();
            setEditing(true);
          }}
          className="absolute right-1.5 top-1.5 z-10 flex h-7 w-7 items-center justify-center rounded-full bg-background/80 text-muted-foreground shadow-sm ring-1 ring-border backdrop-blur hover:text-foreground"
          aria-label="Edit post"
        >
          <Pencil className="h-3.5 w-3.5" />
        </button>
      )}
      <Link
        to={(isTrip ? "/trip/$id" : "/item/$id") as any}
        params={{ id: isTrip ? rec.id : item.id } as any}
        className="block transition-shadow hover:shadow-[0_2px_12px_rgba(0,0,0,0.04)]"
      >
        <div className={cn("flex gap-3 p-3", isOwner && "pr-9")}>

          <div className="flex h-14 w-14 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-muted">
            {item.image_url ? (
              <img src={item.image_url} alt="" className="h-full w-full object-cover" />
            ) : (
              <Icon className="h-6 w-6 text-muted-foreground" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-1.5 min-w-0">
              <span className={`inline-flex shrink-0 items-center gap-1 rounded-full px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wider ${cat.tokenClass}`}>
                <Icon className="h-2.5 w-2.5" /> {cat.label}
              </span>
              {splitGenres(item.genre).slice(0, 2).map((g) => (
                <span key={g} className="inline-flex shrink-0 items-center rounded-full bg-secondary/70 px-1.5 py-0.5 text-[9px] font-medium uppercase tracking-wider text-secondary-foreground truncate max-w-[80px]">
                  {g}
                </span>
              ))}
              <div className="ml-auto flex shrink-0 items-center gap-0.5 text-sm font-semibold tabular-nums">
                <Crown className="h-3.5 w-3.5 text-primary" />
                {rec.rating.toFixed(rec.rating % 1 === 0 ? 0 : 1)}<span className="text-muted-foreground font-normal">/10</span>
              </div>
            </div>
            <h3 className="mt-0.5 truncate font-display text-base leading-tight">{item.title}</h3>
            {isTrip && (
              <p className="text-xs font-medium text-primary">
                {tripStops ?? 0} {tripStops === 1 ? "stop" : "stops"} · tap to see the itinerary
              </p>
            )}
            {item.subtitle && (
              <p className="truncate text-xs text-muted-foreground">{item.subtitle}</p>
            )}
            {rec.note && (
              <p className="mt-1 line-clamp-2 text-sm leading-snug text-foreground/90">
                &ldquo;{rec.note}&rdquo;
              </p>
            )}
            {rec.tags && rec.tags.length > 0 && (
              <div className="mt-1 flex flex-wrap gap-1">
                {rec.tags.map((t) => (
                  <span key={t} className="rounded-full bg-primary/10 px-1.5 py-0.5 text-[10px] font-medium text-primary">
                    #{t}
                  </span>
                ))}
              </div>
            )}
          </div>
        </div>
      </Link>
      {(() => {
        const photos = (rec.photo_urls && rec.photo_urls.length
          ? rec.photo_urls
          : rec.photo_url
          ? [rec.photo_url]
          : []) as string[];
        if (!photos.length) return null;
        return <PhotoCarousel photos={photos} />;
      })()}

      <div className="flex items-center gap-2 border-t border-border px-3 py-1.5 text-xs text-muted-foreground">
        {creator ? (
          <span
            className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold text-white"
            style={{ backgroundColor: creator.color }}
          >
            <span>{creator.emoji ?? "🎙️"}</span>
            {creator.name}
          </span>
        ) : author?.username ? (
          <Link
            to="/profile/$username"
            params={{ username: author.username }}
            className="flex min-w-0 shrink items-center gap-1.5 rounded-full -ml-1 px-1 py-0.5 hover:bg-muted"
          >
            <UserAvatar url={author.avatar_url} name={author.display_name || author.username} size="xs" />
            <span className="truncate text-[13px] font-semibold text-foreground">
              {author.display_name || author.username}
            </span>
            <TopRexxerCrown userId={rec.user_id} />

          </Link>
        ) : (
          <span className="font-medium text-foreground">Someone</span>
        )}
        <span className="shrink-0 text-[10px] text-muted-foreground/70">{formatDistanceToNow(new Date(rec.created_at)).replace("about ", "").replace(" minutes", "m").replace(" minute", "m").replace(" hours", "h").replace(" hour", "h").replace(" days", "d").replace(" day", "d").replace(" months", "mo").replace(" month", "mo").replace(" years", "y").replace(" year", "y").replace("less than am", "now")}</span>

        <div className="ml-auto flex items-center">
          <LikesComments recommendationId={rec.id} compact />
          <SavePostButton recommendationId={rec.id} itemType={(rec.items?.type ?? "other") as any} itemTitle={rec.items?.title} />
          <ShareToGroupButton recommendationId={rec.id} />
          <ShareButton
            variant="icon"

            url={`${SHARE_SITE}/r/${rec.id}`}
            text={`${author?.display_name || author?.username || "A friend"} rates ${item.title} ${rec.rating}/10 👑 on REX 🦖`}
            label="Share on WhatsApp"
          />
        </div>

      </div>
      <AlsoRecommendedBy itemId={item.id} excludeUserId={rec.user_id} />
    </article>
    </div>

    {isOwner && (
      <EditRecommendationDialog
        open={editing}
        onOpenChange={setEditing}
        recommendation={{ id: rec.id, rating: rec.rating, note: rec.note, photo_url: rec.photo_url, photo_urls: rec.photo_urls ?? null, tags: rec.tags ?? null }}
        item={{ id: item.id, type: item.type, genre: item.genre, recipe_text: (item as any).recipe_text ?? null }}
      />
    )}

    <AlertDialog open={confirmDelete} onOpenChange={(v) => { setConfirmDelete(v); if (!v) setOffset(0); }}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Delete this Rex?</AlertDialogTitle>
          <AlertDialogDescription>This will permanently remove your Rex. This can't be undone.</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction
            onClick={(e) => { e.preventDefault(); del.mutate(); }}
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
          >
            {del.isPending ? "Deleting…" : "Delete"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
    </>
  );
}

