// Oct 5 — "and can we truncate the link?"
//
// find-rex.com/s/<code> is the short form of every share link the app makes.
// It holds no content of its own: it resolves the code and redirects to the
// real page, so there is one copy of each page rather than two that drift.
//
// A 302 rather than anything cleverer, because the audience for half of these
// requests is WhatsApp fetching a link preview. It follows a redirect and
// reads the tags on the page it lands on; it would make nothing of a page
// that redirected itself once JavaScript ran.

const SUPABASE_URL = "https://uhpzkbkwxcgqfxmlyktj.supabase.co";
const ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHprYmt3eGNncWZ4bWx5a3RqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4Mzk2NDMsImV4cCI6MjEwMTQxNTY0M30.IvQ8byDwHErLhuJI1Pg3bRcb4AKK4sb9Bm6cr_6sHbI";

const PATH_FOR_KIND = { rec: "r", trip: "t", want: "w", list: "c" };

export async function onRequestGet({ params, request }) {
  const url = new URL(request.url);

  // The alphabet mint_share_code draws from, and nothing else — this keeps a
  // stray request from becoming a database call.
  if (!/^[23456789abcdefghjkmnpqrstuvwxyz]{4,16}$/i.test(params.code || "")) {
    return Response.redirect(`${url.origin}/`, 302);
  }

  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/resolve_share_code`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: ANON_KEY,
      Authorization: `Bearer ${ANON_KEY}`,
    },
    body: JSON.stringify({ _code: String(params.code).toLowerCase() }),
  });

  const rows = response.ok ? await response.json() : null;
  const row = Array.isArray(rows) ? rows[0] : null;
  const path = row && PATH_FOR_KIND[row.kind];

  // An unknown code goes to the front page rather than a 404: the likeliest
  // reason to be holding one is that somebody sent it, and the home page at
  // least says what REX is.
  if (!path || !row.target_id) return Response.redirect(`${url.origin}/`, 302);

  return Response.redirect(`${url.origin}/${path}/${row.target_id}`, 302);
}
