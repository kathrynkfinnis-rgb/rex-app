// Oct 12 — "can we be able to paste in a link to an insta or tiktok video and
// pull out a Rex (e.g. recipes)."
//
// What is actually reachable, checked against both platforms rather than
// assumed:
//
//   TikTok   — https://www.tiktok.com/oembed is public, needs no key, and its
//              `title` field is the post's full caption. For a recipe video the
//              caption usually IS the recipe.
//   Instagram— the post page serves og:title and og:description to a
//              server-side fetch, and og:description carries the caption. Its
//              own oEmbed now needs a Facebook app token, so that is used only
//              if one has been configured.
//
// What is NOT reachable, and the reason this function reads captions rather
// than videos: the spoken steps and the on-screen text live in the video file.
// Getting at those means downloading the video from a platform whose terms
// forbid it, then transcribing and OCRing it. So a caption-less post returns an
// honest "there was nothing to read here" rather than an invented recipe.
//
// Instagram caps og:description at 400 characters. A long method gets cut off
// mid-sentence, and the caller is told when that has probably happened so the
// person can paste the rest themselves — far better than silently saving three
// quarters of a recipe.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const EXTRACT_TOOL = {
  name: "extract_rex",
  description: "Return the recommendation described by this social post.",
  input_schema: {
    type: "object",
    required: ["category", "title"],
    properties: {
      category: {
        type: "string",
        enum: ["recipe", "place", "book", "movie", "tv", "podcast", "event", "other"],
        description:
          "What the post is recommending. 'recipe' for anything cooked, 'place' for a venue you could visit, 'other' when it is a product or does not fit.",
      },
      title: {
        type: "string",
        description:
          "What the thing is called — the dish, the restaurant, the book. Not the caption's first line, and never the account's name unless the account IS the subject.",
      },
      recipeText: {
        type: ["string", "null"],
        description:
          "Only for category 'recipe'. The recipe as plain text, ingredients then method, one per line, copied from the caption. Never invent a quantity or a step that is not written there. Null if the caption names a dish but does not give the recipe.",
      },
      note: {
        type: ["string", "null"],
        description:
          "One or two sentences on why it is worth trying, in the poster's own sense but your words. Null if the caption says nothing beyond the name.",
      },
      searchHint: {
        type: ["string", "null"],
        description:
          "Only for 'place'. The venue name plus its city or neighbourhood if the caption gives one, as you would type it into a maps search. Null otherwise.",
      },
      confident: {
        type: "boolean",
        description:
          "False when the caption is too thin to tell what is being recommended — hashtags only, or just an emoji. The caller will ask the person rather than guess.",
      },
    },
  },
} as const;

const PROMPT = `You read the caption of an Instagram or TikTok post and work out what it is recommending, so it can be saved to a recommendations app.

Captions are messy: hashtags, @mentions, emoji, line breaks used as decoration, and a lot of words that are not about the subject. Work from what is actually written.

Rules that matter:
- Copy recipes, do not write them. If the caption lists ingredients and steps, reproduce them faithfully including quantities. If it only names a dish, set recipeText to null — a plausible-looking invented recipe is the worst thing you could return here.
- The title is the thing, not the sentence. "The best carbonara you'll ever make 🍝" is a recipe titled "Carbonara".
- An account name is not a title unless the post is about that account's own venue.
- If the caption is just hashtags, or an emoji, or says nothing about a subject, set confident to false. Guessing from a username or a hashtag soup is not an answer.
- Captions are often cut off mid-sentence because of how they were fetched. Use what is there; do not try to complete it.`;

// Sept 21, security review — see extract-recipe-photo's note. verify_jwt admits
// any valid JWT for this project, including the public anon key that ships in
// the app binary. The signed role claim is what separates a signed-in person
// from anyone who read the key out of the bundle.
function callerRole(req: Request): string | null {
  const header = req.headers.get("authorization") ?? "";
  const token = header.replace(/^[Bb]earer\s+/, "");
  const payload = token.split(".")[1];
  if (!payload) return null;
  try {
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return (JSON.parse(json) as { role?: string }).role ?? null;
  } catch {
    return null;
  }
}

/// Only the two platforms this was written for, and only their own hostnames.
/// A URL is about to be fetched server-side, so an open redirect or an internal
/// address arriving here would be this function fetching it on the caller's
/// behalf. An allowlist of hosts is the whole defence and is worth keeping
/// narrow.
type Platform = "tiktok" | "instagram";

function platformOf(raw: string): { platform: Platform; url: URL } | null {
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    return null;
  }
  if (url.protocol !== "https:") return null;
  const host = url.hostname.toLowerCase().replace(/^www\./, "");
  if (host === "tiktok.com" || host.endsWith(".tiktok.com")) return { platform: "tiktok", url };
  if (host === "instagram.com" || host.endsWith(".instagram.com")) {
    return { platform: "instagram", url };
  }
  return null;
}

function decodeEntities(s: string): string {
  return s
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}

function metaContent(html: string, property: string): string | null {
  const pattern = new RegExp(
    `<meta[^>]+(?:property|name)=["']${property}["'][^>]*content=["']([^"']*)["']`,
    "i",
  );
  const alternate = new RegExp(
    `<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']${property}["']`,
    "i",
  );
  const found = html.match(pattern) ?? html.match(alternate);
  return found ? decodeEntities(found[1]) : null;
}

interface PostText {
  caption: string;
  author: string | null;
  thumbnail: string | null;
  /// Instagram's og:description stops at 400 characters. At exactly that
  /// length the caption has almost certainly been cut, and a recipe method is
  /// the most likely thing to be cut in half.
  truncated: boolean;
}

async function readTikTok(url: URL): Promise<PostText | null> {
  const endpoint = `https://www.tiktok.com/oembed?url=${encodeURIComponent(url.toString())}`;
  const res = await fetch(endpoint, { headers: { Accept: "application/json" } });
  if (!res.ok) return null;
  const json = await res.json().catch(() => null) as
    | { title?: string; author_name?: string; thumbnail_url?: string }
    | null;
  if (!json?.title) return null;
  return {
    caption: json.title,
    author: json.author_name ?? null,
    thumbnail: json.thumbnail_url ?? null,
    truncated: false,
  };
}

async function readInstagram(url: URL): Promise<PostText | null> {
  // Their own oEmbed first when a token exists — it returns the whole caption
  // rather than the 400-character og: version.
  const token = Deno.env.get("INSTAGRAM_OEMBED_TOKEN");
  if (token) {
    const endpoint = `https://graph.facebook.com/v18.0/instagram_oembed?url=${
      encodeURIComponent(url.toString())
    }&access_token=${encodeURIComponent(token)}&fields=title,author_name,thumbnail_url`;
    const res = await fetch(endpoint);
    if (res.ok) {
      const json = await res.json().catch(() => null) as
        | { title?: string; author_name?: string; thumbnail_url?: string }
        | null;
      if (json?.title) {
        return {
          caption: json.title,
          author: json.author_name ?? null,
          thumbnail: json.thumbnail_url ?? null,
          truncated: false,
        };
      }
    }
  }

  const res = await fetch(url.toString(), {
    headers: {
      // Instagram serves og: tags to a crawler and an app shell with none to a
      // browser. Identifying as what we are — something reading link metadata
      // — is what gets the caption.
      "User-Agent": "facebookexternalhit/1.1",
      "Accept-Language": "en",
    },
  });
  if (!res.ok) return null;
  const html = await res.text();
  const description = metaContent(html, "og:description");
  if (!description) return null;

  // "83 likes, 26 comments - ingaconarte on March 29, 2026: "the caption"."
  const quoted = description.match(/:\s*"([\s\S]*)"\s*\.?\s*$/);
  const caption = quoted ? quoted[1] : description;
  const author = description.match(/-\s*([A-Za-z0-9._]+)\s+on\s/)?.[1] ?? null;

  return {
    caption,
    author,
    thumbnail: metaContent(html, "og:image"),
    truncated: description.length >= 400,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), { status: 405 });
  }
  if (callerRole(req) !== "authenticated") {
    return new Response(JSON.stringify({ error: "Not allowed" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  let body: { url?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 });
  }

  const target = platformOf(body.url ?? "");
  if (!target) {
    return new Response(
      JSON.stringify({ error: "That isn't an Instagram or TikTok link." }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  let post: PostText | null = null;
  try {
    post = target.platform === "tiktok"
      ? await readTikTok(target.url)
      : await readInstagram(target.url);
  } catch {
    post = null;
  }

  if (!post || !post.caption.trim()) {
    return new Response(
      JSON.stringify({
        error:
          "Couldn't read anything from that post — it may be private, deleted, or have no caption.",
      }),
      { status: 422, headers: { "Content-Type": "application/json" } },
    );
  }

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) {
    return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY not configured" }), {
      status: 500,
    });
  }

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": key,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 2048,
      system: PROMPT,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "text",
              text: [
                `Platform: ${target.platform}`,
                post.author ? `Posted by: ${post.author}` : null,
                post.truncated ? "NOTE: this caption was cut off at 400 characters." : null,
                "",
                "Caption:",
                post.caption.slice(0, 8000),
              ].filter(Boolean).join("\n"),
            },
          ],
        },
      ],
      tools: [EXTRACT_TOOL],
      tool_choice: { type: "tool", name: "extract_rex" },
    }),
  });

  if (!res.ok) {
    const errBody = await res.text();
    return new Response(
      JSON.stringify({ error: `Couldn't read that post [${res.status}]: ${errBody.slice(0, 300)}` }),
      { status: 502, headers: { "Content-Type": "application/json" } },
    );
  }

  const json = await res.json();
  const toolUse = json.content?.find(
    (b: { type: string; name?: string }) => b.type === "tool_use" && b.name === "extract_rex",
  );
  const input = toolUse?.input ?? {};

  if (input.confident === false) {
    return new Response(
      JSON.stringify({
        error: "That post's caption doesn't say enough to work out what it's recommending.",
      }),
      { status: 422, headers: { "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({
      category: typeof input.category === "string" ? input.category : "other",
      title: typeof input.title === "string" ? input.title : "",
      recipeText: typeof input.recipeText === "string" ? input.recipeText : null,
      note: typeof input.note === "string" ? input.note : null,
      searchHint: typeof input.searchHint === "string" ? input.searchHint : null,
      thumbnail: post.thumbnail,
      author: post.author,
      sourceUrl: target.url.toString(),
      truncated: post.truncated,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
