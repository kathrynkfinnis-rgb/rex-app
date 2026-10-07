# REX

The iOS app, the website at find-rex.com, and the Supabase schema behind both.

| Where | What |
| --- | --- |
| `ios/App` | The native SwiftUI app. `App/Native` is the app; the Capacitor shell around it is a leftover from the Lovable era and shrinking. |
| `web/` | find-rex.com — a static Cloudflare Pages site plus the Pages Functions that render every share link. **This is what is deployed**, not the TanStack app in `src/`. |
| `src/` | The older React app. Not served at find-rex.com. |
| `supabase/migrations` | Every schema change, in order. Run by hand in the SQL editor. |
| `supabase/functions` | Edge functions. These do **not** ride along with an app build — deploy them separately. |

## Deploying

The website, from **inside** `web/`, signed in to the Cloudflare account that owns `rex-web`:

```
cd web && npx wrangler pages deploy . --project-name=rex-web --branch main
```

Look for `Compiled Worker successfully` and `Uploading Functions bundle`. Without
both lines the share pages did not go up — which is what happens if you run it
from the repo root, where wrangler picks up `.output/server/wrangler.json` and
silently skips `functions/`.

An edge function:

```
npx supabase functions deploy <name>
```

## History

Was a Lovable project until October 2026, and disconnected from it on the 7th.
Nothing syncs anywhere on push any more; `origin` is GitHub and only GitHub.
