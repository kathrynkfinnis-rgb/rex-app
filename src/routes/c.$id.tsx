import { createFileRoute, Link, notFound } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { CrownRatingDisplay } from "@/components/CrownRating";
import { splitGenres, type ItemType } from "@/lib/categories";
import { UserAvatar } from "@/components/UserAvatar";
import { ShareButton } from "@/components/ShareButton";
import { MapPin } from "lucide-react";
import { SITE } from "@/lib/site";

/**
 * Oct 5 — "I just tried to share a collection, and it's just the list of
 * places truncated."
 *
 * A Rex and a trip have had public pages since July; a collection never did,
 * so the app pasted the first twelve titles into the message with "...and 9
 * more". Nothing to open and nothing for a stranger to join from — which
 * matters more now that a share is meant to be the way in.
 *
 * Only a collection its owner has set to "Anyone on REX" resolves here. The
 * RPCs enforce that, and a draft or friends-only collection 404s exactly as a
 * made-up id would, rather than confirming it exists.
 */

type SharedCollection = {
  id: string;
  name: string;
  emoji: string | null;
  item_type: string | null;
  created_at: string;
  owner_username: string | null;
  owner_display_name: string | null;
  owner_avatar_url: string | null;
  item_count: number;
};

type SharedCollectionItem = {
  recommendation_id: string;
  rating: number;
  note: string | null;
  item_id: string;
  item_type: ItemType;
  item_title: string;
  item_subtitle: string | null;
  item_image_url: string | null;
  item_genre: string | null;
  item_address: string | null;
  author_username: string | null;
  author_display_name: string | null;
  section: string | null;
  sort_order: number | null;
};

/** The headings the owner arranged it under, in their order, with anything
 *  unfiled first — the same reading order the app's own collection page uses. */
function grouped(items: SharedCollectionItem[]) {
  const order: Array<string | null> = [];
  const bySection = new Map<string | null, SharedCollectionItem[]>();
  for (const item of items) {
    const key = item.section?.trim() || null;
    if (!bySection.has(key)) {
      bySection.set(key, []);
      order.push(key);
    }
    bySection.get(key)!.push(item);
  }
  return order.map((section) => ({ section, items: bySection.get(section)! }));
}

export const Route = createFileRoute("/c/$id")({
  loader: async ({ params }) => {
    // The RPC names are cast because src/integrations/supabase/types.ts is
    // generated from the database and won't list these two until it is
    // regenerated after the migration runs. The calls themselves are correct.
    const rpc = supabase.rpc.bind(supabase) as unknown as (
      fn: string,
      args: Record<string, unknown>,
    ) => Promise<{ data: unknown; error: unknown }>;
    const [listRes, itemsRes] = await Promise.all([
      rpc("get_shared_collection", { _list: params.id }),
      rpc("get_shared_collection_items", { _list: params.id }),
    ]);
    const collection = (listRes.data as SharedCollection[] | null)?.[0];
    if (listRes.error || !collection) throw notFound();
    return { collection, items: ((itemsRes.data ?? []) as SharedCollectionItem[]) };
  },
  head: ({ params, loaderData }) => {
    const collection = loaderData?.collection;
    if (!collection) {
      return {
        meta: [
          { title: "A collection on REX 🦖" },
          { name: "description", content: "See what your friends are Rexing on REX." },
        ],
      };
    }
    const who = collection.owner_display_name || collection.owner_username || "A friend";
    const count = loaderData?.items.length ?? 0;
    const title = `${collection.emoji ? `${collection.emoji} ` : ""}${collection.name} — ${who} on REX`;
    const desc = `${count} ${count === 1 ? "thing" : "things"} worth knowing about, collected by ${who} on REX 🦖.`;
    const image = loaderData?.items.find((i) => i.item_image_url)?.item_image_url || undefined;
    const url = `${SITE}/c/${params.id}`;
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
    // Oct 5 — a preview with no image falls back to a bare link icon in
    // WhatsApp, which is where most of these are shared. The REX mark is a
    // better answer than nothing, and it is the same mark the app uses.
    const preview = image || `${SITE}/icon-512.png`;
    meta.push({ property: "og:image", content: preview });
    meta.push({ name: "twitter:image", content: preview });
    return { meta, links: [{ rel: "canonical", href: url }] };
  },
  component: SharedCollectionPage,
});

function SharedCollectionPage() {
  const { collection, items } = Route.useLoaderData() as {
    collection: SharedCollection;
    items: SharedCollectionItem[];
  };
  const { id } = Route.useParams();
  const { data: session, isPending } = useQuery({
    queryKey: ["share-session"],
    queryFn: async () => (await supabase.auth.getSession()).data.session,
    staleTime: 60_000,
  });
  const signedIn = !!session;
  const who = collection.owner_display_name || collection.owner_username || "A friend";
  const shareUrl = `${SITE}/c/${id}`;
  const sections = grouped(items);

  return (
    <div className="min-h-dvh bg-background">
      <header className="border-b border-border bg-background/90 px-4 py-3 backdrop-blur">
        <Link to="/" className="inline-flex items-center gap-2 font-display text-lg font-black">
          <span>🦖</span> REX
        </Link>
      </header>

      <main className="mx-auto flex w-full max-w-xl flex-col gap-5 px-4 py-6">
        <div className="flex items-start gap-3">
          {collection.emoji && <div className="text-3xl leading-none">{collection.emoji}</div>}
          <div className="min-w-0 flex-1">
            <h1 className="font-display text-2xl font-black leading-tight">{collection.name}</h1>
            <div className="mt-2 flex items-center gap-2">
              <UserAvatar
                url={collection.owner_avatar_url}
                name={who}
                className="h-7 w-7"
              />
              <span className="text-sm text-muted-foreground">
                {who} · {items.length} {items.length === 1 ? "thing" : "things"}
              </span>
            </div>
          </div>
        </div>

        {items.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nothing in this collection yet.</p>
        ) : (
          sections.map(({ section, items: group }) => (
            <section key={section ?? "__unfiled"} className="flex flex-col gap-2">
              {section && (
                <h2 className="pt-1 font-display text-lg font-bold leading-tight">{section}</h2>
              )}
              <ul className="flex flex-col gap-2">
                {group.map((item) => (
                  <li key={item.recommendation_id}>
                    <div className="overflow-hidden rounded-2xl bg-card ring-1 ring-border">
                      <div className="flex gap-3 p-3">
                        {item.item_image_url && (
                          <img
                            src={item.item_image_url}
                            alt=""
                            className="h-20 w-16 shrink-0 rounded-xl object-cover"
                          />
                        )}
                        <div className="min-w-0 flex-1">
                          <div className="flex items-start gap-2">
                            <h3 className="min-w-0 flex-1 font-semibold leading-tight">
                              {item.item_title}
                            </h3>
                            {item.rating > 0 && (
                              <CrownRatingDisplay value={item.rating} size="xs" showNumber />
                            )}
                          </div>
                          {item.item_subtitle && (
                            <p className="truncate text-xs text-muted-foreground">
                              {item.item_subtitle}
                            </p>
                          )}
                          {item.item_address && (
                            <p className="mt-0.5 flex items-center gap-1 truncate text-xs text-muted-foreground">
                              <MapPin className="h-3 w-3 shrink-0" />
                              {item.item_address}
                            </p>
                          )}
                          {item.item_genre && (
                            <p className="mt-0.5 truncate text-xs text-muted-foreground">
                              {splitGenres(item.item_genre).join(", ")}
                            </p>
                          )}
                          {item.note && (
                            <p className="mt-1 text-sm leading-snug">&ldquo;{item.note}&rdquo;</p>
                          )}
                          {item.author_display_name || item.author_username ? (
                            <p className="mt-1 text-xs text-muted-foreground">
                              Rex&rsquo;d by {item.author_display_name || item.author_username}
                            </p>
                          ) : null}
                        </div>
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            </section>
          ))
        )}

        {isPending ? null : signedIn ? (
          <Link
            to="/"
            className="block rounded-full bg-primary px-5 py-3 text-center font-semibold text-primary-foreground shadow-sm active:scale-[0.99]"
          >
            Open REX 🦖
          </Link>
        ) : (
          <div className="rounded-3xl bg-primary/10 p-5 text-center ring-1 ring-primary/20">
            <div className="text-lg font-semibold">See more on REX 🦖</div>
            <p className="mt-1 text-sm text-muted-foreground">
              Recommendations from people you actually know, not strangers.
            </p>
            <Link
              to="/auth"
              search={{ mode: "signup", ref: collection.owner_username ?? undefined } as any}
              className="mt-4 block rounded-full bg-primary px-5 py-3 text-center font-semibold text-primary-foreground shadow-sm active:scale-[0.99]"
            >
              Join REX free
            </Link>
          </div>
        )}

        <div className="flex justify-center pt-1">
          <ShareButton
            url={shareUrl}
            text={`${collection.name} — ${who}'s collection on REX 🦖`}
            label="Share this collection"
          />
        </div>
      </main>
    </div>
  );
}
