
# Full user test of REX

I'll drive the live preview with a headless browser (Playwright) using your managed auth session, walk every main flow like a real user, capture screenshots + console/network errors at each step, then hand back a prioritised report. No code changes — this is a read-only audit. If you want fixes after, I'll do those as a follow-up.

## Flows I'll cover

1. **Auth & first load** — landing → sign in → redirect to feed. Check session persistence on reload.
2. **Feed** — loads, category filters (Places / Books / Movies / TV), creator-coloured cards, likes + comments, empty state.
3. **Add recommendation** — search-as-you-type for a book (OpenLibrary), a film (TMDB), a place (Google), pick, rate with crowns 1–10, add note, submit, confirm it lands in feed + item page.
4. **Item detail** — enrichment card (facts, reviews), external link previews (Goodreads / IMDb / Google), likes/comments.
5. **Map** — loads, pins render for place recs, tapping a pin opens the item.
6. **Creators** — list renders, follow/unfollow persists, followed creator's picks appear in feed with coloured border.
7. **Friends** — username search, suggested friends (mutuals), share invite link (clipboard fallback), send/accept request.
8. **Import** — paste a short mixed list, run extraction, review queue, Match + Add + Skip. Also try a Google Sheet URL and a small `.docx`.
9. **Goodreads import** — upload a small sample CSV, confirm rows stage + resolve.
10. **Profile (/me)** — avatar, my recs, sign out.
11. **PWA basics** — manifest loads, theme colour, icons, mobile viewport (393×690) layout sanity, safe-area insets, bottom nav symmetry.
12. **Cross-cutting** — console errors, failed network requests, 404s, slow queries, obvious a11y issues (alt text, labels, tap targets), broken links.

## What I'll deliver

A single report grouped by severity:

- **Blocking bugs** — anything that stops a flow (with repro steps, screenshot, console/network evidence).
- **Broken-but-recoverable** — errors the app swallows or wrong data shown.
- **UX issues** — confusing states, missing empty/loading/error states, layout glitches on mobile.
- **Polish** — copy, spacing, iconography, a11y nits.
- **Suggested improvements** — small, concrete changes ranked by impact vs. effort.

## Caveats

- I'll use your injected Supabase session (no credentials handled by me).
- I won't send real invites, won't spam friends, won't post to real external services beyond read-only search/enrichment calls the app already makes.
- Any test recs I create I'll list at the end so you can delete them (or I can, in a follow-up build turn).
- Import tests use tiny sample inputs to keep AI-extraction credit spend minimal (a few cents).

Approve this and I'll run the audit and come back with the report.
