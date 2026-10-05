# find-rex.com

The public website: a landing page, support, the legal pages, and the share
pages behind every link the app produces. Built in September 2026 to take REX
off Lovable — plain HTML and CSS, no framework and no build step.

## What's here

| Path | What it is |
| --- | --- |
| `index.html` | Landing page |
| `support.html` | Help, reporting, deletion, sign-in problems |
| `privacy.html`, `terms.html` | **Generated — do not edit by hand** |
| `functions/r/[id].js` | `/r/<id>` — a shared Rex, server-rendered |
| `functions/t/[id].js` | `/t/<id>` — a shared trip and its itinerary |
| `functions/c/[id].js` | `/c/<id>` — a shared collection |
| `functions/w/[id].js` | `/w/<id>` — a shared want-to-try |
| `functions/s/[code].js` | `/s/<code>` — a short link, redirects to one of the above |
| `.well-known/apple-app-site-association` | Universal Links: which paths open the app |
| `styles.css` | Everything, one file |

## The legal pages

They're generated from the app's own copy so the two can't drift:

```
python3 web/build-legal.py
```

Edit `ios/App/App/Native/LegalContentView.swift`, re-run that, commit both.

## The share pages

They're Cloudflare Pages Functions rather than static files because their main
audience is WhatsApp, iMessage and Slack fetching a link preview — and those
don't run JavaScript, so the title, description and image have to be in the
HTML that comes back. They read the same public database functions the old
Lovable pages did (`get_shared_recommendation`, `get_shared_trip`,
`get_shared_trip_stops`, `get_shared_collection`, `get_shared_want`,
`resolve_share_code`), using Supabase's public anon key.

`.well-known/apple-app-site-association` is what makes a find-rex.com link open
the app rather than Safari on a phone that has it. Apple fetches it directly
and refuses it unless it comes back as `application/json`, which `_headers`
sets — it has no file extension, which is Apple's spec rather than a mistake.

## Deploying

```
npx wrangler pages deploy web --project-name=rex-web
```

## Checking it locally

Pages Functions don't run under a plain static server. Either use
`npx wrangler pages dev web`, or the small Node stand-in used while building
this (serves the static files and routes `/r/` and `/t/` through the function
modules).
