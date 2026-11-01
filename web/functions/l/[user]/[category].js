// Oct 22 — "let's make the shareable wish list."
//
// find-rex.com/l/<user>/<category>. The second half of "buy my want to reads":
// the carts in the app let you buy from your own list, and this is the page
// you hand somebody else before a birthday.
//
// /l/ rather than /w/ because /w/<id> is already one want's own page, and two
// routes on the same letter at different depths is the kind of thing that
// reads fine today and traps whoever touches it next.
//
// Same shape as /k/ by design — keyed by whose and which, server-rendered,
// self-contained — because half the audience is WhatsApp fetching a link
// preview rather than a person with a browser.
//
// Every row carries a tagged Amazon link, which is the point of the page: it
// is the one place where somebody other than the owner is about to buy
// something. That also makes the commission disclosure mandatory here rather
// than advisable, so it is in the markup below and not behind anything.

const SUPABASE_URL = "https://uhpzkbkwxcgqfxmlyktj.supabase.co";
const ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHprYmt3eGNncWZ4bWx5a3RqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4Mzk2NDMsImV4cCI6MjEwMTQxNTY0M30.IvQ8byDwHErLhuJI1Pg3bRcb4AKK4sb9Bm6cr_6sHbI";
const TESTFLIGHT = "https://testflight.apple.com/join/WBkDCpXV";

// The UK store. The suffix is the store — -21 is amazon.co.uk, -20 is .com —
// and the app holds the same tag for the same reason. See RexOutboundLinks.
const AMAZON_TAG = "findrex-21";

// Only the four Amazon sells for. A shared list of places is a different
// feature and a buy link against one would be a lie.
const BUYABLE = {
  book: { plural: "books", verb: "Buy on Amazon", department: null },
  movie: { plural: "films", verb: "Rent or buy on Amazon", department: "instant-video" },
  tv: { plural: "TV", verb: "Rent or buy on Amazon", department: "instant-video" },
  other: { plural: "things", verb: "Find on Amazon", department: null },
};

const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );

const isSafeImage = (url) => typeof url === "string" && /^https:\/\//.test(url);

// Title and author for a book; title alone for a film, whose subtitle is the
// director and the year and is printed on nothing Amazon sells. Same rule as
// RexOutboundLink.amazonSearch — two places, one behaviour.
function amazonURL(row, category) {
  const config = BUYABLE[category];
  if (!config) return null;
  const author =
    category === "book" && row.item_subtitle
      ? ` ${String(row.item_subtitle).split("·")[0].trim()}`
      : "";
  const query = `${row.item_title}${author}`.trim();
  if (!query) return null;
  const params = new URLSearchParams({ k: query });
  if (config.department) params.set("i", config.department);
  params.set("tag", AMAZON_TAG);
  return `https://www.amazon.co.uk/s?${params.toString()}`;
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
    title: "This list isn't available — REX",
    description: "It may have been emptied, or the link may be wrong.",
    url,
    status: 404,
    body: `<h1>This list isn't available</h1>
<p class="lede">It may have been emptied, or the link might be wrong. Ask whoever sent it for a fresh one.</p>`,
  });
}

export async function onRequestGet({ params, request }) {
  const url = new URL(request.url);
  const canonical = `${url.origin}/l/${params.user}/${params.category}`;

  if (!/^[0-9a-f-]{36}$/i.test(params.user)) return missing(canonical);
  // Reaches a SQL parameter, so an allowlist rather than trust — and it is
  // the same four the function itself will return.
  if (!Object.prototype.hasOwnProperty.call(BUYABLE, params.category)) {
    return missing(canonical);
  }

  const rows = await rpc("get_shared_wishlist", {
    _user: params.user,
    _category: params.category,
  });
  // An empty list 404s rather than rendering nothing: a page saying "Kathryn
  // has no books" confirms to a stranger that Kathryn is here.
  if (!Array.isArray(rows) || rows.length === 0) return missing(canonical);

  const first = rows[0];
  const who = first.owner_display_name || first.owner_username || "A friend";
  const { plural, verb } = BUYABLE[params.category];
  const image = rows.map((r) => r.item_image_url).find(isSafeImage) || null;

  const title = `${who}'s ${plural} to get`;
  const description = `${rows.length} ${plural} ${who} wants, on REX. Buy one, or just see what they're after.`;

  const items = rows
    .map((row) => {
      const thumb = isSafeImage(row.item_image_url)
        ? `<img class="thumb" src="${esc(row.item_image_url)}" alt="">`
        : "";
      const sub = row.item_subtitle
        ? `<p class="muted">${esc(row.item_subtitle)}</p>`
        : "";
      const buy = amazonURL(row, params.category);
      // rel="sponsored nofollow" because it is a paid link and search engines
      // are entitled to know that. "noopener" because every outbound link
      // should have it.
      const action = buy
        ? `<a class="buy" href="${esc(buy)}" rel="sponsored nofollow noopener" target="_blank">${esc(verb)}</a>`
        : "";
      return `<li class="wanted">
  ${thumb}
  <div class="meta"><p class="name">${esc(row.item_title)}</p>${sub}</div>
  ${action}
</li>`;
    })
    .join("");

  const body = `<div class="card rex">
  <p class="eyebrow">Wants to try${first.owner_username ? ` · @${esc(first.owner_username)}` : ""}</p>
  <h1>${esc(title)}</h1>
  <ul class="wishlist">${items}</ul>
  <p class="muted disclosure">Buy links go to Amazon. REX may earn a commission on what you buy, at no cost to you — it never changes what anyone recommends or the order you see it in.</p>
</div>`;

  return page({ title, description, image, url: canonical, body });
}
