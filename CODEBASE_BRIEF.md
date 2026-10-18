# REX — codebase brief for an external reviewer

Written 17 October 2026. Read-only orientation; nothing here changes code.

**Two things I was not told and have assumed.** The request template came with
the reviewer's background and the goal of the review left blank. I have written
this for a generalist senior engineer and weighted section 7 towards security,
data integrity and operational cost, because those are where this codebase has
actually hurt recently. If the reviewer is a specialist, or you want a narrower
focus, say so and I will re-weight.

Where I am inferring rather than reading, I say so.

---

## 1. What it is

REX is a recommendations app: you log places, trips, books, films and so on,
rate them, and see what your friends thought of the same things. The product
claim is that a friend's opinion beats a stranger's star rating, which is why
the social graph — not the catalogue — is the core of it.

It is a native SwiftUI iPhone app, currently in TestFlight with roughly twenty
users across two groups (Founders, internal; Testers, external). Version 1.0 is
approved on the App Store but not yet released. The company is Three Lines
Studio Ltd.

## 2. Architecture at a glance

There is no application server. The iOS app talks straight to Supabase over
PostgREST, authenticated as the signed-in user, and **every access-control
decision is a row-level-security policy in Postgres**. Edge functions exist only
for work that needs a secret the app must not hold (AI model keys, APNs).

```
┌──────────────┐     PostgREST (anon key + user JWT)   ┌──────────────────┐
│  iOS app     │ ─────────────────────────────────────▶│ Supabase         │
│  SwiftUI     │                                        │  Postgres + RLS │
│  ios/App/App │ ──── Storage (signed URLs) ───────────▶│  Storage         │
│   /Native    │                                        │  Auth (GoTrue)   │
└──────┬───────┘                                        └────────┬─────────┘
       │                                                          │
       │ direct HTTPS, key in Info.plist                          │ invoked
       ▼                                                          ▼
┌──────────────────────────┐                        ┌──────────────────────┐
│ Google Places / Geocoding│                        │ Edge functions (8)   │
│ TMDB, iTunes, Google Books│                       │ ask-rex, send-push,  │
└──────────────────────────┘                        │ extract-*, organise  │
                                                     └──────────┬───────────┘
                                                                │
                                                     ┌──────────▼───────────┐
                                                     │ Anthropic, Gemini,   │
                                                     │ APNs                 │
                                                     └──────────────────────┘

Static site + share-link rendering: web/ on Cloudflare Pages (domain in AGENTS.md)
```

The thing to internalise: **the client is trusted to be well-behaved, and the
database is the only thing that enforces anything.**

## 3. Tech stack

- **iOS**: Swift 5 / SwiftUI, MapKit, min iOS 18. One Xcode target, no SPM
  dependencies of note. A Capacitor shell remains from the app's Lovable origins
  but no WebContent process spawns at runtime — it is dead weight in the IPA.
- **Backend**: Supabase (Postgres, RLS, Auth, Storage), 127 SQL migrations.
- **Edge functions**: Deno/TypeScript, 8 of them.
- **Web**: static HTML/CSS + Cloudflare Pages Functions in `web/`.
- **Legacy**: `src/` holds an older TanStack/React app. Per `AGENTS.md` it is
  **not** deployed. I have not verified that independently.

## 4. Codebase map

| Path | What |
| --- | --- |
| `ios/App/App/Native/` | The entire app. 101 Swift files, ~47k lines. |
| `ios/App/App/Native/RexAPI.swift` | **~8,000 lines.** All network access, all model decoding. The single most important file. |
| `ios/App/App/Native/RexSearch.swift` | All third-party catalogue search (Google Places, TMDB, iTunes, Books) plus spend guards. |
| `ios/App/App/Native/Models.swift` | Wire types. |
| `ios/App/App/Native/Theme.swift` | Design tokens and shared components. |
| `supabase/migrations/` | 127 files, chronological. The schema's only source of truth. |
| `supabase/functions/` | Edge functions; `_shared/ai-budget.ts` holds the AI rate limiting. |
| `web/` | Deployed static site, admin page, share-link functions. |
| `src/` | Legacy React app. Believed dead. |
| `SECURITY_REVIEW.md` | Full security review from 16 Oct; most findings fixed. |
| `AGENTS.md` | Deploy commands and repo conventions. Read this second. |

Root-level `supabase-migration-*.sql` files are strays predating the
`migrations/` directory.

## 5. How to run it locally

1. Open `ios/App/App.xcodeproj` in Xcode, select a simulator, build and run.
   There is no package resolution step.
2. The app points at the live Supabase project. **There is no local or staging
   backend** — running the app locally reads and writes production data.
3. The website: `web/` is static; open `index.html` or deploy per `AGENTS.md`.
4. Edge functions deploy separately from the app — an app build never carries
   them.

**Awkward bits worth knowing:**

- **There are no tests.** One Xcode target, type application, no test target, no
  CI, no `.github/`. Nothing is automatically verified.
- **Migrations are applied by hand** in the Supabase SQL editor. There is no
  `supabase db push` in the workflow.
- Google place search will not work in a debug build: `RexSearch.googleKey`
  deliberately returns empty unless a separate development key is configured
  (`GMSApiKeyDebug` in `Info.plist`). See section 7.

## 6. Key flows

| Flow | Where to look |
| --- | --- |
| Sign-up / session | `RexAPI.swift` (auth), `RexKeychain.swift` (token storage) |
| Post a Rex (the core action) | `AddRexView.swift` — ~2,900 lines, several branches: single item, trip with stops, list with items |
| Place search and catalogue dedup | `RexSearch.swift`, `RexAPI.createItem` |
| Map | `MapView.swift`, `AppleMapView.swift` |
| Share links (public, unauthenticated) | `supabase/migrations/*share*`, `web/functions/` |

## 7. Areas of potential risk

Ranked. This is where I would spend his time.

**1. RLS is the entire security model — and the repo has disagreed with the live
database.** `supabase/migrations/`. During the 16 Oct review I twice found live
policies that did not match the files, because migrations are applied by hand.
*Ask:* does the live policy set match the repo? Is there any mechanism that
would catch drift? A reviewer should read `pg_policies` from the live database
rather than trusting the migration files.

**2. No tests, anywhere.** 47k lines of Swift, 127 migrations, zero automated
verification. *Ask:* what would a minimum viable test suite cover first? My
instinct is the RLS policies, since they are the security boundary and are
currently verified only by someone remembering to check.

**3. Third-party API keys ship inside the app, with no server-side choke
point.** `ios/App/App/Info.plist`, used by `RexSearch.swift`. Google calls go
phone → Google directly. **This caused a real incident on 16 October**: a
full-catalogue loop in the map's coordinate self-heal ran up ~£111 of Geocoding
charges in one evening. Fixed in several layers (see git log for 17 Oct), but
the architecture still has no central place to rate-limit per user or rotate a
key without a release. *Ask:* should Google go behind an edge function?

**4. `RexAPI.swift` is ~8,000 lines.** Every network call and every decode in
one file. *Ask:* where are the seams? What breaks if two people work on it?

**5. Share links are capability URLs backed by `SECURITY DEFINER` functions.**
`supabase/migrations/20261016120000_*.sql`. These bypass RLS by design. Until
16 Oct they leaked anonymous authors' names and unpublished drafts. *Ask:* are
the remaining definer functions consistent about what they expose?

**6. Prompt-injection surface on the AI features.** `supabase/functions/ask-rex`,
`extract-*`. User-supplied notes and pasted links reach a model. Budget ceilings
exist (`_shared/ai-budget.ts`); injection handling is, as far as I can see,
unaddressed. Listed as open in `SECURITY_REVIEW.md`.

**7. Client-side spend and rate limits are only as current as the user's
build.** `RexSearch.GoogleBudget`. Guards added on 17 Oct protect only people
who update. *Ask:* what belongs server-side instead?

**8. Photo URLs and storage.** Signed URLs with five-year expiry; noted but not
fixed in `SECURITY_REVIEW.md`.

**9. Capacitor leftovers.** Frameworks ship in the IPA; no bridge runs. Dead
weight, and a reviewer may read it as live.

**10. Duplicate catalogue rows.** `merge_items` consolidated 84 duplicates on 15
Oct; more remain, and search now surfaces them. See `RexAPI.searchCatalogueItems`.

## 8. Known gaps and decisions

- **No staging environment.** Development runs against production data. This is
  the root cause of the 16 Oct cost incident and I would raise it first.
- **Migrations by hand** — deliberate, per `AGENTS.md`, but the drift risk is real.
- **Capability-URL share links** — a considered trade-off, documented in the
  migration comments.
- **`src/` is believed dead** but still in the repo.
- Root-level stray `supabase-migration-*.sql` files.

## 9. Questions for the team

1. Is there a staging Supabase project, or is production the only environment?
2. Has anyone diffed live RLS policies against `supabase/migrations/`?
3. Is `src/` genuinely dead, and can it be deleted?
4. What is the intended launch timeline? It changes how much of section 7 is
   urgent versus merely wise.
5. Who else will work in this codebase? That decides how much the 8,000-line
   file matters.

## 10. Suggested review order

1. `AGENTS.md` — repo conventions, 5 minutes.
2. `SECURITY_REVIEW.md` — what has already been looked at, so he does not
   repeat it.
3. Live RLS policies versus `supabase/migrations/` — highest value, least likely
   to have been done.
4. `RexAPI.swift`, skimming for structure rather than reading.
5. `AddRexView.swift` save paths — the most branching logic in the app, and
   where two real bugs were found this week.
6. `RexSearch.swift` — third-party integration and the new spend guards.
7. Edge functions, particularly `ask-rex`.
