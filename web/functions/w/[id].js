// Oct 5 — "want to be able to send 'want to try' via WhatsApp."
//
// The share page for a want: find-rex.com/w/<id>. A want has no rating and no
// note — it is somebody saying they'd like to try something — so this says
// exactly that rather than dressing it up as a recommendation nobody made.
//
// Server-rendered and self-contained for the same reasons r/[id].js is: the
// audience for half of these requests is WhatsApp fetching a link preview,
// and two small files beat one clever build step for a site this size.

const SUPABASE_URL = "https://uhpzkbkwxcgqfxmlyktj.supabase.co";
const ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHprYmt3eGNncWZ4bWx5a3RqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4Mzk2NDMsImV4cCI6MjEwMTQxNTY0M30.IvQ8byDwHErLhuJI1Pg3bRcb4AKK4sb9Bm6cr_6sHbI";
const TESTFLIGHT = "https://testflight.apple.com/join/WBkDCpXV";

// The app's five-tier scale (RexRatingScale.swift): sub-6 Do not Rex, 6 Meh,
// 7-8 Rex, 9 Loved, 10 Obsessed. Kept in step with it by hand.
function tier(raw) {
  if (!(raw > 0)) return null;
  if (raw < 6) return { emoji: "⛔️", label: "Do not Rex" };
  if (raw < 7) return { emoji: "🤷‍♂️", label: "Meh" };
  if (raw < 9) return { emoji: "👌", label: "Rex" };
  if (raw < 10) return { emoji: "♥️", label: "Loved" };
  return { emoji: "💯", label: "Obsessed" };
}

const CATEGORY = {
  restaurant: "Restaurant",
  bar: "Bar",
  cafe: "Café",
  hotel: "Hotel",
  place: "Place",
  film: "Film",
  tv: "TV",
  book: "Book",
  podcast: "Podcast",
  music: "Music",
  activity: "Activity",
  product: "Product",
  trip: "Trip",
  list: "List",
};

const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );

const isSafeImage = (url) => typeof url === "string" && /^https:\/\//.test(url);

function photoOf(row) {
  const candidates = [(row.photo_urls || [])[0], row.photo_url, row.item_image_url];
  return candidates.find(isSafeImage) || null;
}

async function rpc(name, body) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: ANON_KEY,
      Authorization: `Bearer ${ANON_KEY}`,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) return null;
  return response.json();
}

function page({ title, description, image, url, body, status = 200 }) {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta property="og:site_name" content="REX">
<meta property="og:type" content="article">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${esc(url)}">
${image ? `<meta property="og:image" content="${esc(image)}">` : ""}
<meta name="twitter:card" content="${image ? "summary_large_image" : "summary"}">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(description)}">
${image ? `<meta name="twitter:image" content="${esc(image)}">` : ""}
<link rel="canonical" href="${esc(url)}">
<link rel="stylesheet" href="https://api.fontshare.com/v2/css?f[]=switzer@400,500,600,700&f[]=sentient@400,500,700&display=swap">
<link rel="stylesheet" href="/styles.css">
<link rel="icon" href="/favicon.png">
<link rel="apple-touch-icon" href="/icon-180.png">
</head>
<body>
<header class="site"><div class="wrap">
  <a class="brand" href="/"><img class="mark" src="/dinologo.png" alt=""><img class="word" src="/wordmark.png" alt="REX"></a>
  <nav class="site"><a href="/support.html">Support</a><a href="/privacy.html">Privacy</a></nav>
</div></header>
<main><div class="wrap">
${body}
<div class="card join">
  <h3>Recommendations from people you actually trust</h3>
  <p class="muted">REX keeps the places, books, films and trips your friends really recommend — in one app, in their own words.</p>
  <p><a class="btn" href="${TESTFLIGHT}">Get REX on iPhone</a></p>
</div>
</div></main>
<footer class="site"><div class="wrap">
  <p>REX is made by Three Lines Studio Ltd. <a href="mailto:support@find-rex.com">support@find-rex.com</a></p>
  <p><a href="/privacy.html">Privacy Policy</a> &middot; <a href="/terms.html">Terms of Service</a> &middot; <a href="/support.html">Support</a></p>
</div></footer>
</body>
</html>`;
  return new Response(html, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      // Short enough that an edit shows up quickly, long enough that a link
      // doing the rounds in a group chat doesn't hammer the database.
      "Cache-Control": "public, max-age=60, s-maxage=300",
    },
  });
}

function missing(url, what) {
  return page({
    title: `This ${what} isn't available — REX`,
    description: `This ${what} may have been deleted, or the link may be wrong.`,
    url,
    status: 404,
    body: `<h1>This ${what} isn't available</h1>
<p class="lede">It may have been deleted, or the link might be wrong. Ask whoever sent it for a fresh one.</p>`,
  });
}

export async function onRequestGet({ params, request }) {
  const url = new URL(request.url);
  const canonical = `${url.origin}/w/${params.id}`;

  if (!/^[0-9a-f-]{36}$/i.test(params.id)) return missing(canonical, "want");

  const rows = await rpc("get_shared_want", { want_id: params.id });
  const want = Array.isArray(rows) ? rows[0] : null;
  if (!want) return missing(canonical, "want");

  const who = want.author_display_name || want.author_username || "A friend";
  const image = photoOf(want);
  const category = CATEGORY[want.item_type] || "Rex";
  const title = `${who} wants to try ${want.item_title}`;
  const description = `A ${category.toLowerCase()} on someone's list on REX — recommendations from people you actually trust.`;

  const body = `<div class="card rex">
  ${image ? `<img class="hero" src="${esc(image)}" alt="">` : ""}
  <p class="eyebrow">${esc(category)}${want.item_genre ? ` · ${esc(want.item_genre)}` : ""}</p>
  <h1>${esc(want.item_title)}</h1>
  ${want.item_subtitle ? `<p class="lede">${esc(want.item_subtitle)}</p>` : ""}
  <p class="rating">Wants to try</p>
  <p class="byline">On ${esc(who)}'s list${want.author_username ? ` <span class="muted">@${esc(want.author_username)}</span>` : ""}</p>
</div>`;

  return page({ title, description, image, url: canonical, body });
}
