# REX

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
at the old Lovable Cloud project rather than REX's database.

## The brand mark

The dino-with-crown exists as eleven files and nothing keeps them in step, so
changing the logo means changing all of them in one commit:

| Where | Files |
| --- | --- |
| iOS | `ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png` (1024×1024 — this is also the App Store listing icon, so it needs a new build and a review) |
| Android | `android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png`, plus the two `mipmap-anydpi-v26/ic_launcher*.xml` wrappers |
| Website | `web/og-default.png` (1200×1200 — the image on every shared link with no photo of its own), `icon-512.png`, `icon-192.png`, `icon-180.png`, `apple-touch-icon.png`, `favicon.png`, `wordmark.png`, `dinologo.png` |

Miss `og-default.png` and every link shared from the app keeps the old logo in
its WhatsApp preview, long after both app icons have changed.

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
