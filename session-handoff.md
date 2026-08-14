# Session handoff — REX native app

Written mid-session because the user asked to compact chat history. Everything
below is what a fresh session needs to pick this up cleanly.

## Where things stand

- **App Store**: build 11 shipped and live for both Founders (internal,
  auto-updates) and Public Testers (external review). Includes Sign in with
  Apple, the rebuilt Collections page, the 5-tier rating scale, and a run of
  TestFlight bug fixes.
- **Uncommitted build number**: still at 11 in the pbxproj — the fixes below
  (commit `93ede78`) have NOT been shipped as a new build yet. Bump to 12,
  archive, export, upload, attach to groups before ending any session where
  this matters.
- Repo: `~/rex-app` (kathrynkfinnis-rgb/rex-app). Native iOS lives in
  `ios/App/App/Native/`. Web app is Lovable-originated TanStack Start,
  `src/`.
- Simulator device: `23D36271-AB5B-4E4A-982B-69919F1BC9C1` ("iPhone 17").
  **The simulator frequently reattaches to a stale already-running process
  instead of a fresh launch** — if a fix doesn't seem to take effect, run
  `xcrun simctl terminate 23D36271-AB5B-4E4A-982B-69919F1BC9C1
  com.kathrynfinnis.rexapp` before the next `launch` call. This cost a lot of
  wasted debugging time this session — do it reflexively before any
  "why isn't my fix showing up" investigation.
- App Store Connect scripting: `/private/tmp/claude-501/-Users-kathryntravis/2c9711f2-8650-4fa4-919b-eeb1924ca4b2/scratchpad/asc.py`
  (JWT auth helper) periodically gets cleaned from the scratchpad between
  sessions — recreate it from this session's transcript if missing (it's
  short, just ES256-signs a JWT with the .p8 key at
  `~/private_keys/AuthKey_2UD853CL5X.p8` and wraps `urllib` calls). Ship
  scripts are named `shipN.py` in the same directory, templated off each
  other by swapping the version string.

## Active, unresolved bug: swipe-to-delete doesn't work in the simulator

**Symptom**: swiping right-to-left on a feed or profile card does nothing —
no delete action reveals. A test swipe with 11 graduated touch points (40ms
steps, 190pt of horizontal travel) scrolled the feed vertically instead,
meaning the ScrollView's own pan gesture is winning outright, not just
narrowly beating `SwipeToRemove`'s gesture.

**What's been ruled out:**
- `.draggable(rec.id)` on feed cards — removed entirely (it did nothing
  useful anyway, since Collections and Feed are never visible at once on a
  phone, so there was never a drop target). Didn't fix it.
- `.scrollPosition(id: $scrolledRowID)` (added this session on the feed's
  ScrollView) — temporarily removed, rebuilt, retested. Didn't fix it either
  (swipe still just scrolled the list).
- Stale simulator process — confirmed and force-terminated before the tests
  above, so this wasn't masking a working fix.
- `SwipeToRemove.swift` itself is unchanged from earlier in this same
  session, where it **was** verified working (screenshots exist in the
  transcript of the delete action revealing correctly on Feed and
  Collections cards). So either something about the surrounding context
  changed, or the working verification earlier was itself compromised by
  the same stale-process issue and never actually exercised the current
  code.

**Not yet tried:**
- Test on the CollectionsView / CollectionsSectionListView / WishListCategoryView
  swipe rows (all use the same `SwipeToRemove` component) — if those still
  work, the bug is specific to something about FeedView/ProfileView's
  ScrollView, not the component itself. This is the fastest next diagnostic
  step.
- Test with a real long, deliberate manual swipe using `computer` action
  (not `touch_path`) if available on this tool surface — `touch_path` may
  itself have a quirk in how it feeds synthetic events to the simulator's
  gesture recognizer pipeline. Worth trying a completely different input
  path to rule out the test harness itself.
- Check whether `.contentShape(Rectangle())` + `.onTapGesture` on
  `SwipeToRemove`'s content (both present) could be **exclusively** claiming
  the gesture ahead of the sibling `.gesture(DragGesture(...))` — SwiftUI
  resolves plain `.onTapGesture` vs `.gesture(DragGesture)` on the *same*
  view via its default exclusivity rules, and depending on modifier order
  this can go either way. Try `.simultaneousGesture` instead of `.gesture`
  for the DragGesture, or reorder so the tap gesture is added after (or via
  `.highPriorityGesture` for the drag).
- Actually the single highest-value next step: temporarily strip
  `SwipeToRemove`'s content down to *just* `content()` with no
  `.onTapGesture`/`.contentShape` at all, confirm swipe works bare, then add
  modifiers back one at a time to find which one steals the gesture. Given
  time spent this session, do this **before** anything else next time.
- Consider this might be simulator-only (synthetic touch events don't always
  reproduce real-finger gesture-recognizer races faithfully) — if the
  isolated-component test above still fails, it's worth asking Kathryn to
  test build 11 or the next build on her real device via TestFlight rather
  than continuing to chase it in the simulator blind.

**Do not** re-add `.draggable()` to feed cards as part of chasing this — it's
confirmed dead weight there and was previously suspected (wrongly, per the
test above) as the sole cause.

## Fixed and verified this session (committed, not yet shipped as a build)

Commit `93ede78`:
- Feed scroll position preserved across push/pop via `.scrollPosition(id:)`.
- Tapping the Feed tab while already on Feed scrolls to top (reuses the same
  mechanism, keyed to `"top"` id on the header).
- Photo upload downscaling (1600px Rex photos, 600px avatars) — was the
  actual cause of "feed photos are slow to load" reported this session,
  alongside a properly-sized `URLCache.shared` (was near-default/empty).
- ProfileView given its own `NavigationStack(path:)` (previously relied on
  MainTabView's unbound wrapping stack, which meant no programmatic push was
  possible — needed once SwipeToRemove's tap-callback pattern replaced the
  NavigationLink there).
- ProfileView: "add to collection" long-press + rexCount social-proof row
  added to match the feed (three separate TestFlight testers asked for
  this).

Earlier in the session (separate commits, already summarized in prior
handoffs / git log — see `git log --oneline` for the full run): Sign in with
Apple, Collections rebuilt to Kathryn's sketch (three shelves + drill-in
feeds), the 5-tier rating scale (Do not Rex / Meh / Rex / Loved / Obsessed)
replacing 1-10 crowns, anonymous posts, wants/blasts merged into the feed,
mass-import collapsing, sort filter (Most recent/Most liked), the
duplicate-catalogue-item bug, the Google-rating-column bug, tappable
profiles everywhere, and a long run of individually-diagnosed TestFlight
screenshot bugs (see task list #87–#97, all completed).

## Backlog queued this session, not yet started

These came in as a rapid-fire burst near the end of the session and haven't
been scoped or built yet:

1. **Map tab: list view + sort** (task #106, already logged) — toggle
   between map and a plain list of places, with the same Most
   recent/Most Rex'd sort pattern as the feed. Needs a per-place "most
   recent" timestamp that `fetchMapPlaces`/`MapPlace` doesn't currently
   carry — check the select.
2. **Share a collection via WhatsApp** — add a `ShareLink` to
   `CollectionDetailView` (and maybe the shelf tiles), same pattern already
   used in `RexCardActions.swift` for sharing a Rex. Should be quick —
   needs a share text/URL that makes sense for a collection (there's no
   public web view of a collection yet, so this might just share a text
   summary of what's in it rather than a link, unless a shareable web route
   for collections needs building too — worth clarifying with Kathryn
   whether she wants a real link or just a text share).
3. **"Lists" as a new Add-a-Rex category** — paste a large block of free
   text (e.g. copied from Notes or a Word doc), parse it into individual
   recommendation cards with embedded product/book/place links, let the
   user **review and confirm** each parsed card before it's posted, and
   **do not lose the original commentary** per item. This is the same LLM
   extraction pipeline already built for the web importer
   (`extractFromText` in `src/lib/import.functions.ts`, using the
   Anthropic API with forced tool-use) — but that's a TanStack Start server
   function, callable only via the web app's own RPC protocol, not
   something native can hit directly the way it hits plain Supabase REST.
   Two real options: (a) native opens the web importer in an in-app browser
   (precedent: this was already the agreed approach for trip-doc import
   earlier in the project) and the "Lists" category tile just deep-links
   there; or (b) build a native paste screen that calls the Anthropic API
   directly with a bundled/restricted key, then stages results in
   `import_staging` for review exactly like the web flow does, reusing
   `resolveStagingRow`/`approveStagingRow` semantics. (a) is far less work
   and consistent with prior decisions; recommend starting there unless
   Kathryn specifically wants it fully native.
4. **Filter by rating, as a second row below the category filter chips on
   the feed** — same horizontal-chip pattern as the existing category row,
   values presumably the five tiers (Do not Rex / Meh / Rex / Loved /
   Obsessed) now that the rating scale was rebuilt this session. Not yet
   scoped in detail.

None of these have any code started. Pick up in roughly this order unless
Kathryn says otherwise: swipe-to-delete bug first (it's a regression, higher
priority than new features), then WhatsApp share (smallest), then Map
list+sort, then rating filter row, then Lists category (biggest, needs a
product decision from Kathryn on native-vs-webview first).

## Full backlog

Run `TaskList` for the authoritative current state — 107 tasks tracked,
most completed. The ones still pending as of this handoff:
15, 16, 17, 18, 21, 22, 25, 26, 28, 30, 38, 45, 49, 59 (blocker, needs
Kathryn), 60, 63, 66, 73, 82, 96, 98, 99, 100 (on hold per Kathryn), 101,
102, 103, 104, 105 (ambiguous, needs Kathryn's example), 106, plus the four
new ones above once logged.

## Things that need Kathryn, not code

- **#59 blocker**: unrestricted Google server key for Places search.
- **#105**: "reconcile Trip vs Place definitions" — genuinely ambiguous,
  needs a concrete example of where they currently look/behave the same
  when they shouldn't, before anything can be built.
- **#84**: Lovable data audit — 1,009 Rex confirmed across the three users:
  Kathryn 558, Phoebe 333, Gemma 118. Waiting on her read of whether that
  matches what she'd expect.
- Whether WhatsApp share needs a real public link (requiring a web route for
  collections that doesn't exist yet) or just a text summary.
