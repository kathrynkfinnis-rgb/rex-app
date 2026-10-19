// Oct 19 — "are you able to share your ranking with a friend?" → "a link to a
// page showing your ordered list."
//
// find-rex.com/k/<user>/<category>. Two path segments rather than one id,
// because a ranking is not a row: it is everything you have placed in a
// category, in order, so it is keyed by whose and which. That is also why it
// cannot use the short-code table, whose target is a single uuid.
//
// The whole ordered list is shown — Kathryn's call on 19 October. A ranking
// with gaps in it would confuse more than it protects: the numbers are the
// entire point, and 1, 2, 5, 9 reads as a bug rather than as discretion.
//
// Server-rendered and self-contained for the same reason r/ and w/ are: half
// the audience is WhatsApp fetching a link preview.

const SUPABASE_URL = "https://uhpzkbkwxcgqfxmlyktj.supabase.co";
const ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHprYmt3eGNncWZ4bWx5a3RqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4Mzk2NDMsImV4cCI6MjEwMTQxNTY0M30.IvQ8byDwHErLhuJI1Pg3bRcb4AKK4sb9Bm6cr_6sHbI";
const TESTFLIGHT = "https://testflight.apple.com/join/WBkDCpXV";

// Plural, because the heading is always "<name>'s <these>, in order".
const CATEGORY_PLURAL = {
  place: "places",
  event: "events",
  book: "books",
  movie: "films",
  tv: "TV",
  podcast: "podcasts",
  recipe: "recipes",
  trip: "trips",
  list: "lists",
  other: "things",
};

const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );

const isSafeImage = (url) => typeof url === "string" && /^https:\/\//.test(url);

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
<meta property="og:image" content="${esc(image || "https://find-rex.com/og-default.png")}">
<meta name="twitter:card" content="${image ? "summary_large_image" : "summary"}">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(description)}">
<meta name="twitter:image" content="${esc(image || "https://find-rex.com/og-default.png")}">
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
      "Cache-Control": "public, max-age=60, s-maxage=300",
    },
  });
}

function missing(url) {
  return page({
    title: "This ranking isn't available — REX",
    description: "It may have been emptied, or the link may be wrong.",
    url,
    status: 404,
    body: `<h1>This ranking isn't available</h1>
<p class="lede">It may have been emptied, or the link might be wrong. Ask whoever sent it for a fresh one.</p>`,
  });
}

export async function onRequestGet({ params, request }) {
  const url = new URL(request.url);
  const canonical = `${url.origin}/k/${params.user}/${params.category}`;

  if (!/^[0-9a-f-]{36}$/i.test(params.user)) return missing(canonical);
  // The app's own category values, nothing else — this reaches a SQL
  // parameter, and a narrow allowlist is cheaper than trusting it.
  if (!Object.prototype.hasOwnProperty.call(CATEGORY_PLURAL, params.category)) {
    return missing(canonical);
  }

  const rows = await rpc("get_shared_ranking", {
    _user: params.user,
    _category: params.category,
  });
  if (!Array.isArray(rows) || rows.length === 0) return missing(canonical);

  const first = rows[0];
  const who = first.owner_display_name || first.owner_username || "A friend";
  const plural = CATEGORY_PLURAL[params.category];
  const image = rows.map((r) => r.item_image_url).find(isSafeImage) || null;

  const title = `${who}'s ${plural}, in order`;
  const description =
    `${rows.length} ${plural} ranked by ${who} on REX — recommendations from people you actually trust.`;

  const items = rows
    .map((row, index) => {
      // The stored position is a float so rows can be slotted between two
      // others without renumbering; the reader wants 1, 2, 3.
      const rank = index + 1;
      const thumb = isSafeImage(row.item_image_url)
        ? `<img class="thumb" src="${esc(row.item_image_url)}" alt="">`
        : "";
      const sub = row.item_subtitle
        ? `<p class="muted">${esc(row.item_subtitle)}</p>`
        : "";
      return `<li class="ranked">
  <span class="rank">${rank}</span>
  ${thumb}
  <div class="meta"><p class="name">${esc(row.item_title)}</p>${sub}</div>
</li>`;
    })
    .join("");

  const body = `<div class="card rex">
  <p class="eyebrow">Ranked${first.owner_username ? ` · @${esc(first.owner_username)}` : ""}</p>
  <h1>${esc(title)}</h1>
  <ol class="ranking">${items}</ol>
</div>`;

  return page({ title, description, image, url: canonical, body });
}
