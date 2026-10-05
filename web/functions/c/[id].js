// Oct 5 — "I just tried to share a collection, and it's just the list of
// places truncated."
//
// The share page for a collection: find-rex.com/c/<id>. Only resolves for one
// whose owner has set it to "Anyone on REX" — get_shared_collection refuses
// anything else, so a link to a private collection reads as missing rather
// than confirming it exists.

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
  const canonical = `${url.origin}/c/${params.id}`;

  if (!/^[0-9a-f-]{36}$/i.test(params.id)) return missing(canonical, "collection");

  const [listRows, itemRows] = await Promise.all([
    rpc("get_shared_collection", { _list: params.id }),
    rpc("get_shared_collection_items", { _list: params.id }),
  ]);
  const list = Array.isArray(listRows) ? listRows[0] : null;
  if (!list) return missing(canonical, "collection");

  const items = Array.isArray(itemRows) ? itemRows : [];
  const who = list.owner_display_name || list.owner_username || "A friend";
  const count = Number(list.item_count) || items.length;
  const title = `${list.emoji ? list.emoji + " " : ""}${list.name} — a collection by ${who}`;
  const description = count
    ? `${count} ${count === 1 ? "thing" : "things"} ${who} rates, on REX.`
    : `A collection by ${who} on REX — recommendations from people you actually trust.`;
  const image = items.map(photoOf).find(Boolean) || null;

  // Grouped by the headings the owner arranged, in the order the function
  // returns them — the collection reads the way they built it.
  const sections = [];
  for (const row of items) {
    const heading = (row.section || "").trim();
    let group = sections.find((s) => s.heading === heading);
    if (!group) { group = { heading, rows: [] }; sections.push(group); }
    group.rows.push(row);
  }

  const entry = (row) => {
    const rating = tier(row.rating);
    const by = row.author_display_name || row.author_username || null;
    return `<li>
  <p class="entry-title">${esc(row.item_title)}${rating ? ` <span class="muted">${rating.emoji} ${esc(rating.label)}</span>` : ""}</p>
  ${row.item_subtitle ? `<p class="muted">${esc(row.item_subtitle)}</p>` : ""}
  ${row.item_address ? `<p class="muted">${esc(row.item_address)}</p>` : ""}
  ${row.note ? `<blockquote>${esc(row.note)}</blockquote>` : ""}
  ${by ? `<p class="muted">Rex'd by ${esc(by)}</p>` : ""}
</li>`;
  };

  const body = `<div class="card rex">
  <p class="eyebrow">Collection</p>
  <h1>${esc(list.emoji ? list.emoji + " " : "")}${esc(list.name)}</h1>
  <p class="lede">${count} ${count === 1 ? "thing" : "things"} · put together by ${esc(who)}${list.owner_username ? ` <span class="muted">@${esc(list.owner_username)}</span>` : ""}</p>
</div>
${sections.map((s) => `<div class="card">
  ${s.heading ? `<h2>${esc(s.heading)}</h2>` : ""}
  <ul class="entries">${s.rows.map(entry).join("")}</ul>
</div>`).join("")}`;

  return page({ title, description, image, url: canonical, body });
}
