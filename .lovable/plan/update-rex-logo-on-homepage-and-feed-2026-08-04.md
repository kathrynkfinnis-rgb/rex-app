# Update REX logo on homepage and feed

## Current state
- `src/routes/index.tsx` (homepage) renders the logo via `rexLogo.url` from `@/assets/rex-wordmark.png.asset.json` at `h-14`.
- `src/routes/_authenticated/feed.tsx` renders the same asset at `h-12` next to the page title.
- The user has uploaded a new dark-green serif "REX" wordmark to use instead.

## Plan
1. Generate a Lovable Asset pointer from the uploaded image (`ChatGPT_Image_Aug_4_2026_12_17_09_PM.png`) and write it to `src/assets/rex-wordmark.png.asset.json`, replacing the existing pointer so all current imports automatically use the new logo.
2. Review the rendered logo on the homepage and feed; adjust height/width/container classes if the new wordmark's aspect ratio makes it too large, small, or misaligned.
3. Verify both screens in the preview to confirm the new logo loads cleanly and respects the pistachio background/card colors.

## Out of scope
- PWA manifest icons and favicon are not part of this change unless the user asks.
- No other branding or copy changes.
