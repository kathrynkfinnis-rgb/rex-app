// Sept 17 — the share page for a trip: find-rex.com/t/<id>, the whole
// itinerary in order with every stop's Rex. Server-rendered for the same
// reason as /r/<id>: link previews don't run JavaScript. Helpers are repeated
// from functions/r/[id].js on purpose — two readable files, no build step.

const SUPABASE_URL = "https://uhpzkbkwxcgqfxmlyktj.supabase.co";
const ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHprYmt3eGNncWZ4bWx5a3RqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4Mzk2NDMsImV4cCI6MjEwMTQxNTY0M30.IvQ8byDwHErLhuJI1Pg3bRcb4AKK4sb9Bm6cr_6sHbI";
const TESTFLIGHT = "https://testflight.apple.com/join/WBkDCpXV";

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

// Every stop the app knows where to find, as one Google Maps route — the
// thing people actually want from someone else's itinerary.
function routeHref(stops) {
  const points = stops
    .filter((s) => s.item_lat != null && s.item_lng != null)
    .map((s) => `${s.item_lat},${s.item_lng}`);
  if (points.length === 0) return null;
  if (points.length === 1) {
    return `https://www.google.com/maps/search/?api=1&query=${points[0]}`;
  }
  return `https://www.google.com/maps/dir/${points.join("/")}`;
}

function stopHref(stop) {
  if (stop.item_lat != null && stop.item_lng != null) {
    return `https://www.google.com/maps/search/?api=1&query=${stop.item_lat},${stop.item_lng}`;
  }
  const query = [stop.item_title, stop.item_address].filter(Boolean).join(" ");
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
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
  <h3>Keep the whole trip</h3>
  <p class="muted">REX holds every stop your friends actually recommend — with their notes, on a map, ready for when you go.</p>
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

export async function onRequestGet({ params, request }) {
  const url = new URL(request.url);
  const canonical = `${url.origin}/t/${params.id}`;

  const notFound = () =>
    page({
      title: "This trip isn't available — REX",
      description: "This trip may have been deleted, or the link may be wrong.",
      url: canonical,
      status: 404,
      body: `<h1>This trip isn't available</h1>
<p class="lede">It may have been deleted, or the link might be wrong. Ask whoever sent it for a fresh one.</p>`,
    });

  if (!/^[0-9a-f-]{36}$/i.test(params.id)) return notFound();

  const [tripRows, stopRows] = await Promise.all([
    rpc("get_shared_trip", { _trip: params.id }),
    rpc("get_shared_trip_stops", { _trip: params.id }),
  ]);
  const trip = Array.isArray(tripRows) ? tripRows[0] : null;
  if (!trip) return notFound();
  const stops = Array.isArray(stopRows) ? stopRows : [];

  const who = trip.author_display_name || trip.author_username || "A friend";
  const image = photoOf(trip);
  const count = `${stops.length} ${stops.length === 1 ? "stop" : "stops"}`;
  const title = `${who}'s trip: ${trip.item_title}`;
  const description = trip.note
    ? `“${String(trip.note).replace(/\s+/g, " ").slice(0, 155)}”`
    : `${count} on REX — the itinerary, in order, with every recommendation.`;
  const route = routeHref(stops);

  const itinerary = stops
    .map((stop, index) => {
      const rating = tier(stop.rating);
      const category = CATEGORY[stop.item_type] || "";
      const photo = photoOf(stop);
      return `<li class="stop">
  <span class="stop-number">${index + 1}</span>
  <div class="stop-body">
    ${photo ? `<img class="stop-photo" src="${esc(photo)}" alt="">` : ""}
    <p class="eyebrow">${esc(category)}${stop.item_genre ? ` · ${esc(stop.item_genre)}` : ""}</p>
    <h3>${esc(stop.item_title)}${rating ? ` <span class="rating">${rating.emoji} ${esc(rating.label)}</span>` : ""}</h3>
    ${stop.item_subtitle ? `<p class="muted">${esc(stop.item_subtitle)}</p>` : ""}
    ${stop.note ? `<blockquote>${esc(stop.note)}</blockquote>` : ""}
    ${
      stop.item_lat != null || stop.item_address
        ? `<p><a class="maps" href="${esc(stopHref(stop))}" target="_blank" rel="noreferrer">Open in Maps</a></p>`
        : ""
    }
  </div>
</li>`;
    })
    .join("");

  const body = `<div class="card rex">
  ${image ? `<img class="hero" src="${esc(image)}" alt="">` : ""}
  <p class="eyebrow">Trip · ${esc(count)}</p>
  <h1>${esc(trip.item_title)}</h1>
  ${trip.item_subtitle ? `<p class="lede">${esc(trip.item_subtitle)}</p>` : ""}
  ${trip.note ? `<blockquote>${esc(trip.note)}</blockquote>` : ""}
  <p class="byline">Rex'd by ${esc(who)}${trip.author_username ? ` <span class="muted">@${esc(trip.author_username)}</span>` : ""}</p>
  ${route ? `<p><a class="btn secondary" href="${esc(route)}" target="_blank" rel="noreferrer">See the route on the map</a></p>` : ""}
</div>
<h2>Itinerary</h2>
${
  stops.length
    ? `<ol class="stops">${itinerary}</ol>`
    : `<p class="muted">No stops on this trip yet.</p>`
}`;

  return page({ title, description, image, url: canonical, body });
}
