import { createFileRoute, Link, notFound } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { UserAvatar } from "@/components/UserAvatar";
import { ShareButton } from "@/components/ShareButton";
import { SITE } from "@/lib/site";

// Oct 5 — "want to be able to send 'want to try' via WhatsApp." The share
// icon was hidden on want cards because this page didn't exist. It mirrors
// r.$id, minus the rating and the review: a want is someone saying they'd
// like to try something, and the page says exactly that rather than dressing
// it up as a recommendation nobody made.
type SharedWant = {
  id: string;
  created_at: string;
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

export const Route = createFileRoute("/w/$id")({
  loader: async ({ params }) => {
    // Cast: the generated Supabase types predate this function.
    const { data, error } = await (supabase.rpc as any)("get_shared_want", {
      want_id: params.id,
    });
    if (error || !data || !Array.isArray(data) || data.length === 0) throw notFound();
    return { want: data[0] as SharedWant };
  },
  head: ({ params, loaderData }) => {
    const want = loaderData?.want;
    if (!want) {
      return {
        meta: [
          { title: "REX — something a friend wants to try" },
          { name: "description", content: "See what your friends are Rexing on REX." },
        ],
      };
    }
    const who = want.author_display_name || want.author_username || "A friend";
    const cat = categoryMeta(want.item_type);
    const title = `${who} wants to try ${want.item_title}`;
    const desc = `A ${cat.label.toLowerCase()} on someone's list on REX 🦖 — the little book of things your friends actually love.`;
    const url = `${SITE}/w/${params.id}`;
    const image = (want.photo_urls && want.photo_urls[0]) || want.item_image_url || undefined;
    const preview = image || `${SITE}/icon-512.png`;
    return {
      meta: [
        { title },
        { name: "description", content: desc },
        { property: "og:title", content: title },
        { property: "og:description", content: desc },
        { property: "og:url", content: url },
        { property: "og:type", content: "article" },
        { property: "og:site_name", content: "REX 🦖" },
        { property: "og:image", content: preview },
        { name: "twitter:card", content: image ? "summary_large_image" : "summary" },
        { name: "twitter:title", content: title },
        { name: "twitter:description", content: desc },
        { name: "twitter:image", content: preview },
      ],
      links: [{ rel: "canonical", href: url }],
    };
  },
  component: SharedWantPage,
});

function SharedWantPage() {
  const { want } = Route.useLoaderData();
  const { id } = Route.useParams();
  const { data: session, isPending } = useQuery({
    queryKey: ["share-session"],
    queryFn: async () => (await supabase.auth.getSession()).data.session,
    staleTime: 60_000,
  });
  const signedIn = !!session;
  const cat = categoryMeta(want.item_type);
  const Icon = cat.icon;
  const who = want.author_display_name || want.author_username || "A friend";
  const photo = (want.photo_urls && want.photo_urls[0]) || want.item_image_url;
  const shareUrl = `${SITE}/w/${id}`;

  return (
    <div className="min-h-dvh bg-background">
      <header className="border-b border-border bg-background/90 px-4 py-3 backdrop-blur">
        <Link to="/" className="inline-flex items-center gap-2 font-display text-lg font-black">
          <span>🦖</span> REX
        </Link>
      </header>

      <main className="mx-auto max-w-lg space-y-4 px-4 py-6">
        <div className="overflow-hidden rounded-3xl bg-card shadow-sm ring-1 ring-border">
          {photo && <img src={photo} alt="" className="max-h-80 w-full object-cover" />}
          <div className="space-y-3 p-5">
            <div className="flex flex-wrap items-center gap-2">
              <span
                className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wider ${cat.tokenClass}`}
              >
                <Icon className="h-3 w-3" /> {cat.label}
              </span>
              {want.item_genre && (
                <span className="inline-flex items-center rounded-full bg-secondary/70 px-2 py-0.5 text-[11px] font-medium uppercase tracking-wider text-secondary-foreground">
                  {want.item_genre}
                </span>
              )}
              {/* Where a Rex shows its rating. A want has none, and saying so
                  plainly is better than leaving the eye looking for one. */}
              <span className="ml-auto inline-flex items-center rounded-full bg-muted px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                Wants to try
              </span>
            </div>
            <div>
              <h1 className="font-display text-2xl leading-tight">{want.item_title}</h1>
              {want.item_subtitle && (
                <p className="mt-0.5 text-sm text-muted-foreground">{want.item_subtitle}</p>
              )}
            </div>
            <div className="flex items-center gap-2 pt-1">
              <UserAvatar url={want.author_avatar_url} name={who} size="sm" />
              <div className="text-sm">
                <span className="font-medium">{who}</span>
                <span className="text-muted-foreground"> wants to try this</span>
              </div>
            </div>
          </div>
        </div>

        {isPending ? null : signedIn ? (
          <Link
            to="/item/$id"
            params={{ id: want.item_id }}
            className="block rounded-full bg-primary px-5 py-3 text-center font-semibold text-primary-foreground shadow-sm active:scale-[0.99]"
          >
            Open in REX 🦖
          </Link>
        ) : (
          <div className="rounded-3xl bg-primary/10 p-5 text-center ring-1 ring-primary/20">
            <div className="text-lg font-semibold">See what else they're after on REX 🦖</div>
            <p className="mt-1 text-sm text-muted-foreground">
              The little book of books, films, shows, restaurants &amp; places your friends
              actually love.
            </p>
            <div className="mt-4 grid gap-2">
              <Link
                to="/auth"
                search={{ mode: "signup", ref: want.author_username ?? undefined } as any}
                className="block rounded-full bg-primary px-5 py-3 text-center font-semibold text-primary-foreground shadow-sm active:scale-[0.99]"
              >
                Join REX {want.author_username ? `& follow @${want.author_username}` : "free"}
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
          <ShareButton
            url={shareUrl}
            text={`${who} wants to try ${want.item_title} on REX 🦖`}
            label="Share this"
          />
        </div>
      </main>
    </div>
  );
}
