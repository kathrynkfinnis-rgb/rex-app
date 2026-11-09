# Rex

The iOS app, the website at find-rex.com, and the Supabase schema behind both.

| Where | What |
| --- | --- |
| `ios/App` | The native SwiftUI app. `App/Native` is the app; the Capacitor shell around it is a leftover from the Lovable era and shrinking. |
| `android/` | The native Jetpack Compose app. Same database, same RLS. |
| `web/` | find-rex.com — a static Cloudflare Pages site plus the Pages Functions that render every share link. **This is what is deployed.** |
| `supabase/migrations` | Every schema change, in order. Run by hand in the SQL editor. |
| `supabase/functions` | Edge functions. These do **not** ride along with an app build — deploy them separately. |
| `.github/workflows` | CI: the website, the edge functions, Android and iOS, each built on its own. |

`src/` held the older TanStack app and was removed on 7 November. It had not
been served at find-rex.com since September, and its vite config still pointed
at the old Lovable Cloud project rather than Rex's database.

## The name

**Rex.** Not REX, not Find Rex. Settled 9 November and swept through the whole
repo in one commit — 333 occurrences across 79 files. `CFBundleDisplayName` had
said `Rex` since the beginning; everything else has now caught up.

Two deliberate exceptions, both typography rather than spelling:

* the wordmark art is set in capitals, because that is the lockup the
  designer drew;
* `"ACROSS REX"` in `BrowseWithoutAccountView` is an uppercase eyebrow, sitting
  in the same slot as `shelf.source_label.uppercased()`.

The App Store listing is still **Find Rex**, which only a new version can
change. Already-applied migrations were left alone on purpose: some of them
name RLS policies (`"Admins manage REX's recommendations update"`), and a
policy name is an identifier that exists in the live database. Renaming it in
a file that has already run would mean the next run of that file drops nothing
and creates a second policy alongside the first.

## The brand mark

The dino-with-crown lands in ten files, and `brand/regenerate.py` is what keeps
them in step. Change a master in `brand/source/`, run it, commit everything it
touched:

```
python3 brand/regenerate.py
```

| Where | Files |
| --- | --- |
| iOS | `ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png` (1024×1024 — this is also the App Store listing icon, so it needs a new build and a review) |
| Android | `android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png` (432×432), plus the two `mipmap-anydpi-v26/ic_launcher*.xml` wrappers, which reference drawables and so never change |
| Website | `web/og-default.png` (1200×1200 — the image on every shared link with no photo of its own), `icon-512.png`, `icon-192.png`, `icon-180.png`, `apple-touch-icon.png`, `favicon.png`, `wordmark.png`, `dinologo.png` |

Miss `og-default.png` and every link shared from the app keeps the old logo in
its WhatsApp preview, long after both app icons have changed.

Two things the script knows that are easy to get wrong by hand:

* **The Android foreground is not the iOS icon.** Android masks the outer ring
  away and guarantees only the inner 66 of 108dp, so the dino is held to 61% of
  a 432×432 transparent canvas. The file before November was 253×264 — not
  square, and too small for the grid.
* **`ic_launcher_background` in `android/app/src/main/res/values/colors.xml`
  must equal the cream inside the artwork**, `#F9FAEA`. It was `#F7F4ED` until
  November, a different cream, which showed as a seam under a circular mask.

The November 2026 delivery is green `#70A361` on cream `#F9FAEA`. Neither is in
`Theme.swift`, whose primary is still the much darker `#173626` — the mark and
the interface are not currently the same green.

## Deploying

The website, from **inside** `web/`, signed in to the Cloudflare account that owns `rex-web`:

```
cd web && npx wrangler pages deploy . --project-name=rex-web --branch main
```

Look for `Compiled Worker successfully` and `Uploading Functions bundle`. Without
both lines the share pages did not go up.

Nov 8 — the deploy on that date printed:

```
Using redirected Wrangler configuration.
 - Configuration being used: "../.output/server/wrangler.json"
```

and still uploaded the Functions bundle, so it worked. But the note this
replaces said that redirect only happened from the repo root, and it does not:
`.wrangler/deploy/config.json` holds `{"configPath":"../../.output/server/wrangler.json"}`,
so it is read from inside `web/` too. Both are untracked, gitignored leftovers
of the TanStack app that was removed on the 7th, and `.output` can no longer be
regenerated because the thing that built it is gone. Clearing them removes the
redirect for good:

```
rm -rf .output .wrangler/deploy
```

Check the two lines above are still printed after doing it.

An edge function:

```
npx supabase functions deploy <name>
```

## History

Was a Lovable project until October 2026, and disconnected from it on the 7th.
Nothing syncs anywhere on push any more; `origin` is GitHub and only GitHub.
