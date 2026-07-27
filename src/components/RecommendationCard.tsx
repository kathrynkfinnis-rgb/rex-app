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


export type FeedRow = {
  id: string;
  rating: number;
  note: string | null;
  created_at: string;
  photo_url: string | null;
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
          className="absolute right-2 top-2 z-10 flex h-8 w-8 items-center justify-center rounded-full bg-background/80 text-muted-foreground shadow-sm ring-1 ring-border backdrop-blur hover:text-foreground"
          aria-label="Edit post"
        >
          <Pencil className="h-4 w-4" />
        </button>
      )}
      <Link
        to="/item/$id"
        params={{ id: item.id }}
        className="block transition-shadow hover:shadow-md"
      >

        <div className="flex gap-4 p-4">
          <div className="flex h-20 w-20 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-muted">
            {item.image_url ? (
              <img src={item.image_url} alt="" className="h-full w-full object-cover" />
            ) : (
              <Icon className="h-8 w-8 text-muted-foreground" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <span className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider ${cat.tokenClass}`}>
                <Icon className="h-3 w-3" /> {cat.label}
              </span>
              {item.genre && (
                <span className="inline-flex items-center rounded-full bg-secondary/70 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider text-secondary-foreground">
                  {item.genre}
                </span>
              )}
              <CrownRatingDisplay value={rec.rating} size="xs" showNumber />
            </div>
            <h3 className="mt-1 truncate font-display text-xl leading-tight">{item.title}</h3>
            {item.subtitle && (
              <p className="truncate text-sm text-muted-foreground">{item.subtitle}</p>
            )}
          </div>
        </div>
        {rec.note && (
          <p className="px-4 pb-3 text-[15px] leading-snug text-foreground/90">
            &ldquo;{rec.note}&rdquo;
          </p>
        )}
      </Link>
      <div className="flex items-center justify-between border-t border-border px-4 py-2.5 text-xs text-muted-foreground">
        {creator ? (
          <span
            className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-semibold text-white"
            style={{ backgroundColor: creator.color }}
          >
            <span>{creator.emoji ?? "🎙️"}</span>
            {creator.name}
          </span>
        ) : author?.username ? (
          <Link
            to="/profile/$username"
            params={{ username: author.username }}
            className="flex items-center gap-2 rounded-full -ml-1 px-1 py-0.5 hover:bg-muted"
          >
            <UserAvatar url={author.avatar_url} name={author.display_name || author.username} size="xs" />
            <span className="font-medium text-foreground">
              {author.display_name || author.username}
            </span>
          </Link>
        ) : (
          <span className="font-medium text-foreground">Someone</span>
        )}
        <span>{formatDistanceToNow(new Date(rec.created_at), { addSuffix: true })}</span>
      </div>
      <div className="border-t border-border">
        <LikesComments recommendationId={rec.id} compact />
      </div>
    </article>
    {isOwner && (
      <EditRecommendationDialog
        open={editing}
        onOpenChange={setEditing}
        recommendation={{ id: rec.id, rating: rec.rating, note: rec.note }}
        item={{ id: item.id, type: item.type, genre: item.genre }}
      />
    )}
    </>
  );
}

