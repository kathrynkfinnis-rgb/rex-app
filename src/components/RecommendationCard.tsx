import { Link } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { CrownRatingDisplay } from "@/components/CrownRating";
import { LikesComments } from "@/components/LikesComments";
import { EditRecommendationDialog } from "@/components/EditRecommendationDialog";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { supabase } from "@/integrations/supabase/client";
import { formatDistanceToNow } from "date-fns";
import { Pencil } from "lucide-react";
import { UserAvatar } from "@/components/UserAvatar";
import { SavePostButton } from "@/components/SavePostButton";
import { ShareButton } from "@/components/ShareButton";

const SHARE_SITE = "https://pocket-app-pioneers.lovable.app";



export type FeedRow = {
  id: string;
  rating: number;
  note: string | null;
  created_at: string;
  photo_url: string | null;
  photo_urls?: string[] | null;
  user_id: string;
  item_id: string;
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
  if (!item) return null;
  const cat = categoryMeta(item.type);
  const Icon = cat.icon;
  const isOwner = currentUserId && currentUserId === rec.user_id;
  return (
    <>
    <article
      className="relative overflow-hidden rounded-2xl bg-card shadow-sm ring-1 ring-border"

      style={creator ? { borderLeft: `4px solid ${creator.color}` } : undefined}
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
        to="/item/$id"
        params={{ id: item.id }}
        className="block transition-shadow hover:shadow-md"
      >
        <div className="flex gap-3 p-3">
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
              {item.genre && (
                <span className="inline-flex shrink-0 items-center rounded-full bg-secondary/70 px-1.5 py-0.5 text-[9px] font-medium uppercase tracking-wider text-secondary-foreground truncate max-w-[80px]">
                  {item.genre}
                </span>
              )}
              <div className="ml-auto shrink-0"><CrownRatingDisplay value={rec.rating} size="xs" showNumber /></div>
            </div>
            <h3 className="mt-0.5 truncate font-display text-base leading-tight">{item.title}</h3>
            {item.subtitle && (
              <p className="truncate text-xs text-muted-foreground">{item.subtitle}</p>
            )}
            {rec.note && (
              <p className="mt-1 line-clamp-2 text-sm leading-snug text-foreground/90">
                &ldquo;{rec.note}&rdquo;
              </p>
            )}
          </div>
        </div>
        {(() => {
          const photos = (rec.photo_urls && rec.photo_urls.length
            ? rec.photo_urls
            : rec.photo_url
            ? [rec.photo_url]
            : []) as string[];
          if (!photos.length) return null;
          if (photos.length === 1) {
            return (
              <img
                src={photos[0]}
                alt=""
                className="max-h-56 w-full object-cover"
              />
            );
          }
          return (
            <div className="grid grid-cols-2 gap-0.5">
              {photos.slice(0, 4).map((url, i) => (
                <div key={url} className="relative aspect-[4/3] overflow-hidden bg-muted">
                  <img src={url} alt="" className="h-full w-full object-cover" />
                  {i === 3 && photos.length > 4 && (
                    <div className="absolute inset-0 flex items-center justify-center bg-black/50 text-lg font-semibold text-white">
                      +{photos.length - 4}
                    </div>
                  )}
                </div>
              ))}
            </div>
          );
        })()}
      </Link>
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
            className="flex min-w-0 items-center gap-1.5 rounded-full -ml-1 px-1 py-0.5 hover:bg-muted"
          >
            <UserAvatar url={author.avatar_url} name={author.display_name || author.username} size="xs" />
            <span className="truncate font-medium text-foreground">
              {author.display_name || author.username}
            </span>
          </Link>
        ) : (
          <span className="font-medium text-foreground">Someone</span>
        )}
        <span className="shrink-0">· {formatDistanceToNow(new Date(rec.created_at), { addSuffix: true }).replace("about ", "")}</span>
        <div className="ml-auto flex items-center">
          <LikesComments recommendationId={rec.id} compact />
          <SavePostButton recommendationId={rec.id} />
        </div>
      </div>

    </article>
    {isOwner && (
      <EditRecommendationDialog
        open={editing}
        onOpenChange={setEditing}
        recommendation={{ id: rec.id, rating: rec.rating, note: rec.note, photo_url: rec.photo_url, photo_urls: rec.photo_urls ?? null }}
        item={{ id: item.id, type: item.type, genre: item.genre, recipe_text: (item as any).recipe_text ?? null }}
      />
    )}
    </>
  );
}

