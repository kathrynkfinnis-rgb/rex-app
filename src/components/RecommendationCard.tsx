import { Link } from "@tanstack/react-router";
import { CrownRatingDisplay } from "@/components/CrownRating";
import { LikesComments } from "@/components/LikesComments";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { formatDistanceToNow } from "date-fns";

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
};

export function RecommendationCard({ rec }: { rec: FeedRow }) {
  const item = rec.items;
  const author = rec.profiles;
  if (!item) return null;
  const cat = categoryMeta(item.type);
  const Icon = cat.icon;
  return (
    <article className="overflow-hidden rounded-2xl bg-card shadow-sm ring-1 ring-border">
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
        <div className="flex items-center justify-between border-t border-border px-4 py-2.5 text-xs text-muted-foreground">
          <span className="flex items-center gap-2">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-secondary text-[11px] font-semibold text-secondary-foreground">
              {(author?.display_name || author?.username || "?").slice(0, 1).toUpperCase()}
            </span>
            <span className="font-medium text-foreground">
              {author?.display_name || author?.username || "Someone"}
            </span>
          </span>
          <span>{formatDistanceToNow(new Date(rec.created_at), { addSuffix: true })}</span>
        </div>
      </Link>
      <div className="border-t border-border">
        <LikesComments recommendationId={rec.id} compact />
      </div>
    </article>
  );
}
