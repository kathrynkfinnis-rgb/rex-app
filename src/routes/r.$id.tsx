import { createFileRoute, Link, notFound } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { CrownRatingDisplay } from "@/components/CrownRating";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { UserAvatar } from "@/components/UserAvatar";
import { ShareButton } from "@/components/ShareButton";

type SharedRec = {
  id: string;
  rating: number;
  note: string | null;
  created_at: string;
  photo_url: string | null;
  photo_urls: string[] | null;
  item_id: string;
  item_type: ItemType;
  item_title: string;
  item_subtitle: string | null;
  item_image_url: string | null;
  item_genre: string | null;
  author_username: string | null;
  author_display_name: string | null;
  author_avatar_url: string | null;
};

const SITE = "https://pocket-app-pioneers.lovable.app";

export const Route = createFileRoute("/r/$id")({
  loader: async ({ params }) => {
    const { data, error } = await supabase.rpc("get_shared_recommendation", { rec_id: params.id });
    if (error || !data || !Array.isArray(data) || data.length === 0) throw notFound();
    return { rec: data[0] as SharedRec };
  },
  head: ({ params, loaderData }) => {
    const rec = loaderData?.rec;
    if (!rec) {
      return {
        meta: [
          { title: "REX — a Rex from a friend" },
          { name: "description", content: "See what your friends are Rexing on REX." },
        ],
      };
    }
    const who = rec.author_display_name || rec.author_username || "A friend";
    const cat = categoryMeta(rec.item_type);
    const title = `${who} rates ${rec.item_title} ${rec.rating}/10 👑`;
    const desc = rec.note
      ? `"${rec.note.replace(/\s+/g, " ").slice(0, 155)}"`
      : `A ${cat.label.toLowerCase()} Rex on REX 🦖 — the little book of things your friends actually love.`;
    const image =
      (rec.photo_urls && rec.photo_urls[0]) || rec.photo_url || rec.item_image_url || undefined;
    const url = `${SITE}/r/${params.id}`;
    const meta: Array<Record<string, string>> = [
      { title },
      { name: "description", content: desc },
      { property: "og:title", content: title },
      { property: "og:description", content: desc },
      { property: "og:url", content: url },
      { property: "og:type", content: "article" },
      { property: "og:site_name", content: "REX 🦖" },
      { name: "twitter:card", content: image ? "summary_large_image" : "summary" },
      { name: "twitter:title", content: title },
      { name: "twitter:description", content: desc },
    ];
    if (image) {
      meta.push({ property: "og:image", content: image });
      meta.push({ name: "twitter:image", content: image });
    }
    return {
      meta,
      links: [{ rel: "canonical", href: url }],
    };
  },
  component: SharePage,
});

function SharePage() {
  const { rec } = Route.useLoaderData();
  const { id } = Route.useParams();
  const { data: session, isPending } = useQuery({
    queryKey: ["share-session"],
    queryFn: async () => (await supabase.auth.getSession()).data.session,
    staleTime: 60_000,
  });
  const signedIn = !!session;
  const cat = categoryMeta(rec.item_type);
  const Icon = cat.icon;
  const who = rec.author_display_name || rec.author_username || "A friend";
  const photo =
    (rec.photo_urls && rec.photo_urls[0]) || rec.photo_url || rec.item_image_url;
  const shareUrl = `${SITE}/r/${id}`;
  const shareText = `${who} rates ${rec.item_title} ${rec.rating}/10 👑 on REX 🦖`;

  return (
    <div className="min-h-dvh bg-background">
      <header className="border-b border-border bg-background/90 px-4 py-3 backdrop-blur">
        <Link to="/" className="inline-flex items-center gap-2 font-display text-lg font-black">
          <span>🦖</span> REX
        </Link>
      </header>

      <main className="mx-auto max-w-lg space-y-4 px-4 py-6">
        <div className="overflow-hidden rounded-3xl bg-card shadow-sm ring-1 ring-border">
          {photo && (
            <img src={photo} alt="" className="max-h-80 w-full object-cover" />
          )}
          <div className="space-y-3 p-5">
            <div className="flex flex-wrap items-center gap-2">
              <span className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wider ${cat.tokenClass}`}>
                <Icon className="h-3 w-3" /> {cat.label}
              </span>
              {rec.item_genre && (
                <span className="inline-flex items-center rounded-full bg-secondary/70 px-2 py-0.5 text-[11px] font-medium uppercase tracking-wider text-secondary-foreground">
                  {rec.item_genre}
                </span>
              )}
              <div className="ml-auto"><CrownRatingDisplay value={rec.rating} size="sm" showNumber /></div>
            </div>
            <div>
              <h1 className="font-display text-2xl leading-tight">{rec.item_title}</h1>
              {rec.item_subtitle && (
                <p className="mt-0.5 text-sm text-muted-foreground">{rec.item_subtitle}</p>
              )}
            </div>
            {rec.note && (
              <blockquote className="rounded-2xl bg-muted/50 p-4 text-[15px] leading-snug">
                &ldquo;{rec.note}&rdquo;
              </blockquote>
            )}
            <div className="flex items-center gap-2 pt-1">
              <UserAvatar url={rec.author_avatar_url} name={who} size="sm" />
              <div className="text-sm">
                <span className="font-medium">{who}</span>
                {rec.author_username && (
                  <span className="text-muted-foreground"> · @{rec.author_username}</span>
                )}
              </div>
            </div>
          </div>
        </div>

        {isPending ? null : signedIn ? (
          <Link
            to="/item/$id"
            params={{ id: rec.item_id }}
            className="block rounded-full bg-primary px-5 py-3 text-center font-semibold text-primary-foreground shadow-sm active:scale-[0.99]"
          >
            Open in REX 🦖
          </Link>
        ) : (
          <div className="rounded-3xl bg-primary/10 p-5 text-center ring-1 ring-primary/20">
            <div className="text-lg font-semibold">Get more Rex like this on REX 🦖</div>
            <p className="mt-1 text-sm text-muted-foreground">
              The little book of books, films, shows, restaurants & places your friends actually love.
            </p>
            <div className="mt-4 grid gap-2">
              <Link
                to="/auth"
                search={{ mode: "signup", ref: rec.author_username ?? undefined } as any}
                className="block rounded-full bg-primary px-5 py-3 text-center font-semibold text-primary-foreground shadow-sm active:scale-[0.99]"
              >
                Join REX {rec.author_username ? `& follow @${rec.author_username}` : "free"}
              </Link>
              <Link
                to="/auth"
                className="block rounded-full border border-border bg-background px-5 py-3 text-center text-sm font-medium"
              >
                I already have an account
              </Link>
            </div>
          </div>
        )}

        <div className="flex justify-center pt-1">
          <ShareButton url={shareUrl} text={shareText} label="Share this Rex" />
        </div>
      </main>
    </div>
  );
}
