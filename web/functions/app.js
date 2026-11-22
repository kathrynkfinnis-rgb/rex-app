// find-rex.com/app — one link to the App Store that is correct for whoever
// opens it.
//
// Nov 22 — "lots of users in the EU (Ireland and France) are not able to
// download the app, 'app not available'", and then "the link is still not
// working for the users in France" after the first attempt at fixing it.
//
// The history matters, because both previous links failed the same way for
// opposite reasons:
//
//   * Sharing from the App Store app on a UK phone produces
//     apps.apple.com/GB/app/... — pinned to the UK storefront, so a French
//     or Irish Apple ID opening it is told the app is not available in their
//     country. It is; the storefront in the link just isn't theirs.
//   * Replacing that with the country-less apps.apple.com/app/id... was
//     supposed to let Apple redirect per visitor. It does not reliably:
//     checked on 22 November, that URL resolved to the /us/ storefront, so
//     the fix swapped a GB problem for a US one and the reports continued.
//
// Apple's availability is not the issue and never was. The App Store Connect
// API reports 175 territories, every one AVAILABLE, released 5 November —
// France, Ireland, the US and the UK included.
//
// So the storefront is chosen here instead of hoped for. Cloudflare resolves
// the visitor's country on every request and puts it in CF-IPCountry; that
// is the storefront they can actually buy from, and Apple's URL scheme takes
// it as a lowercase two-letter path segment.
//
// Everything should point at this URL rather than at apps.apple.com
// directly: the website, the share pages, the app's own Invite. One place to
// be wrong, one place to fix.

const APP_ID = "6799256042";

// Codes Cloudflare uses when it cannot place the visitor: T1 is Tor, XX is
// unknown. Sending those to /xx/ would 404, so they get the country-less URL
// — no worse than what they had, and the only case where we are guessing.
const UNKNOWN = new Set(["XX", "T1", ""]);

export function onRequestGet({ request }) {
  const country = (request.headers.get("CF-IPCountry") || "").toUpperCase();
  const path = UNKNOWN.has(country) ? "" : `${country.toLowerCase()}/`;
  const target = `https://apps.apple.com/${path}app/id${APP_ID}`;

  return new Response(null, {
    status: 302,
    headers: {
      Location: target,
      // Never cached at the edge: the whole point is that two people get
      // different answers, and a shared cache entry would hand one person's
      // storefront to everyone behind the same colo.
      "Cache-Control": "no-store",
      Vary: "CF-IPCountry",
    },
  });
}
