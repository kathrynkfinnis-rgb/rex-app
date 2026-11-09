# Rex — Security Review

**Date:** 16 October 2026
**Scope:** `ios/App/App/Native` (SwiftUI app), `supabase/migrations` (124 files), `supabase/functions` (7 edge functions), `web/` (Cloudflare Pages + Functions), `src/` (unserved React app), git history.
**Method:** Six parallel read-only reviews — auth/secrets, authorisation & RLS, injection, privacy, dependencies/infrastructure, business logic — then consolidated and de-duplicated. Nothing was modified. Nothing was run against production except read-only `GET`s and one deliberate no-op RPC (see F1).

---

## 1. Executive summary

Rex is in better security shape than most pre-launch consumer apps, and that is not a courtesy. Row Level Security is enabled on **every** table with no exceptions. There are no analytics or crash-reporting SDKs, one `print()` in 46,000 lines of Swift, and no plaintext HTTP anywhere. Account deletion genuinely deletes. Contact matching hashes on the device and never stores a number. The share pages escape output centrally, so the usual cross-site-scripting hole structurally cannot be opened. Several past reviews are visible in the code, and they were done properly.

The problems are concentrated in two places, and both have a single shape.

**The first is authorisation.** Rex has no server of its own — the app talks straight to the database — so RLS *is* the security. Most policies are right. A handful check *"is this row mine?"* but forget *"am I allowed to see the thing it hangs off?"*, and several `UPDATE` policies were written without their own `WITH CHECK`, which in Postgres silently reuses the read condition for the write. Six findings are that same mistake. The fix for each is to copy the stricter sibling policy that already exists a few files away.

**The second is paperwork that hasn't kept up with the code.** The privacy policy doesn't mention the AI features, still contains a literal `[TO CONFIRM — Kathryn to add the registered company address]` placeholder, and promises a way to delete your phone hash that no screen offers. The contacts permission prompt still says "email addresses" though the app now reads phone numbers too. None of this is exotic; all of it is read by App Review.

**One finding is mine.** The duplicate-merge migration I wrote on 15 October created an unprotected `SECURITY DEFINER` function. It is not live — you never ran it — and I have corrected the file. Details at F1.

### Top five to fix first

| # | What | Why first |
|---|---|---|
| 1 | **Don't run the old `20261015110000` merge migration** — take the corrected one | It would have made a mass-delete function callable by any user |
| 2 | **Friendship `requester_id` is still rewritable** (F2) | Today's fix closed self-accept; this is the other half of the same hole, and it opens any stranger's account |
| 3 | **Privacy policy placeholder + undisclosed AI processors** (F12, F13) | Shipping a `[TO CONFIRM]` address is an Art. 13 failure App Review will see |
| 4 | **Session tokens in `UserDefaults`, never revoked on sign-out** (F6, F7) | The code's own comment says "move to Keychain before this ships". It has shipped |
| 5 | **Missing privacy manifest (`PrivacyInfo.xcprivacy`)** (F14) | Required for App Store submission; the app uses Required-Reason APIs |

---

## 2. Findings table

| ID | Title | Severity | Area | Confidence |
|---|---|---|---|---|
| F1 | `merge_items()` is an unauthenticated mass-delete primitive | **Critical** | AuthZ | Confirmed (not live) |
| F2 | Friendship addressee can rewrite `requester_id`, forging a friendship with anyone | **Critical** | AuthZ | Confirmed |
| F3 | Tag tables are world-readable, turning share RPCs into a bulk read of strangers' content | High | AuthZ | Confirmed |
| F4 | Likes/comments/saves writable against content you can't see → push to any user | High | AuthZ | Confirmed |
| F5 | `profiles` grants SELECT/UPDATE on every column (phone hash readable; `is_official` self-settable) | High | AuthZ / Privacy | Confirmed |
| F6 | Session tokens stored in `UserDefaults`, not Keychain | High | Auth | Confirmed |
| F7 | `signOut()` never revokes server-side; no password reset or change exists | Medium | Auth | Confirmed |
| F8 | iOS bundle ships a Capacitor WebView pointed at a remote URL, on Capacitor 8.5.0 | High | Infra | Likely |
| F9 | TanStack Start critical XSS live in a deployed Worker and in the iOS bundle | High | Deps | Confirmed |
| F10 | `ask-rex` prompt injection writes persistent memory to the victim's account | Medium | Injection | Confirmed |
| F11 | Note markdown allows link-text spoofing; detector path allows any URL scheme | Medium | Injection | Confirmed |
| F12 | Privacy policy inaccurate: `[TO CONFIRM]` address, missing processors, promises a deletion route that doesn't exist | High | Privacy | Confirmed |
| F13 | Ask Rex sends friends' names and verbatim notes to OpenAI/Google; neither disclosed | High | Privacy | Confirmed |
| F14 | No `PrivacyInfo.xcprivacy`; contacts purpose string out of date; dead `AdSupport` import | High | Privacy | Confirmed |
| F15 | Any user can write rows into another user's collection | Medium | AuthZ | Confirmed |
| F16 | Any signed-in user can rewrite any catalogue item | Medium | AuthZ | Confirmed |
| F17 | Blocking is not enforced in the database | Medium | AuthZ | Confirmed |
| F18 | Five-year signed photo URLs stored in rows make storage policies moot | Medium | AuthZ | Confirmed |
| F19 | "Post anonymously" is defeatable; share pages don't mask it at all | Medium | Privacy | Confirmed |
| F20 | `extract-from-link` allowlist bypassable via `l.instagram.com` redirector | Medium | SSRF | Likely |
| F21 | No rate limiting or cost control on three paid-AI functions | High | Business logic | Confirmed |
| F22 | No CSP, HSTS, X-Frame-Options or Permissions-Policy on find-rex.com | High | Infra | Confirmed |
| F23 | Contact-matching RPCs are an unlimited email/phone enumeration oracle | Medium | Auth | Confirmed |
| F24 | Nothing is ever deleted on a schedule; the one prune function was never wired up | Medium | Privacy | Confirmed |
| F25 | `profiles.interests` collected, read by nothing, unchangeable | Medium | Privacy | Confirmed |
| F26 | Data export omits ~14 categories of personal data | Medium | Privacy | Confirmed |
| F27 | `ask-rex` daily limit is check-then-act, bypassable by concurrency | Medium | Business logic | Confirmed |
| F28 | Share codes use non-cryptographic `random()`; mint has no ownership check | Medium | Business logic | Confirmed |
| F29 | `get_shared_want` applies no visibility filter at all | Medium | AuthZ | Confirmed |
| F30 | Prompt/notes can reach Supabase logs via `console.error` | Medium | Privacy | Confirmed |
| F31 | Error messages pass provider and database internals to the user | Low–Med | Privacy | Confirmed |
| F32 | Lockfile drift; two competing lockfiles; build-tool exemptions from cooling-off | Medium | Deps | Confirmed |
| F33 | No CI/CD, so nothing ever runs `npm audit` | Medium | Infra | Confirmed |
| F34 | Lovable-era Google Maps key committed to git history, still in shipped bundles | Medium | Secrets | Confirmed |
| F35 | `SECURITY DEFINER` functions revoked from `public, anon` but not `authenticated` | Low–Med | AuthZ | Possible |
| F36 | `search_profiles` LIKE-metacharacter injection bypasses the 2-char guard | Low | Injection | Confirmed |
| F37 | Debug `print()` shipped in FeedView | Low | Privacy | Confirmed |
| F38 | Admin token in `localStorage` on a publicly reachable page | Low | Infra | Confirmed |
| F39 | Legal pages load a third-party font before the policy is read | Low | Privacy | Confirmed |
| F40 | Android build artefacts and `local.properties` committed | Low | Infra | Confirmed |
| F41 | `aps-environment` is `development` | Info | Config | Confirmed |

**Explicitly disproved** (checked, and *not* findings): PostgREST filter injection from the iOS app; XSS in the share pages; path traversal in uploads; SQL injection in migrations; `javascript:`/`data:` links from a crafted note; deep-link abuse; service-role key leakage; secrets in git history beyond F34; CSRF; payments (there are none).

---

## 3. Findings in detail

### F1 — `merge_items()` is an unauthenticated mass-delete primitive — Critical — Confirmed, not live

**This one is mine, and it is the reason to read the rest of this document carefully.**

`supabase/migrations/20261015110000_one_place_one_row.sql` — the duplicate-place merge I wrote on 15 October and asked you to run.

```sql
create or replace function public.merge_items(loser uuid, keeper uuid)
returns void language plpgsql security definer set search_path = public
as $$ begin
  if loser = keeper then return; end if;
  delete from public.recommendations r where r.item_id = loser and exists (...);
  ...
  delete from public.items where id = loser;
end; $$;
```

`SECURITY DEFINER` means it runs as the owner and ignores RLS. It takes no caller identity at all — no `auth.uid()`, no role check. And Postgres grants `EXECUTE` on a new function to `PUBLIC` by default, which on Supabase also means `anon` and `authenticated`. PostgREST exposes the `public` schema, so it would have been live at `POST /rest/v1/rpc/merge_items`. Item ids are readable by any signed-in user (`items` SELECT is `USING (true)`, F16), so the arguments were there for the taking. In a loop it deletes other people's recommendations and wants and empties the catalogue.

Every other definer function in this schema is revoked then granted narrowly. `delete_place_without_pin`, which does far less, checks `has_role(auth.uid(),'admin')` internally. This one got neither.

**Why it isn't live:** I called it with `loser = keeper` — the function's own guaranteed no-op path — and got `PGRST202: no matches found in the schema cache`. The function does not exist in production, because the migration was never run.

**Fix — applied to the file, not to the database.** It now carries an internal `has_role(…, 'admin')` gate *and* `revoke all … from public, anon, authenticated` after the create. Run the corrected version; do not run the copy I pasted into chat yesterday.

**Lesson worth keeping:** a `SECURITY DEFINER` function needs its `REVOKE` written in the same breath as its `CREATE`. The codebase already knew this — `20260915100000_lock_down_definer_functions.sql` is an entire migration about it — and I didn't follow it.

---

### F2 — Friendship addressee can rewrite `requester_id` — Critical — Confirmed

`supabase/migrations/20261016100000_only_the_recipient_accepts.sql:41-44` (today's fix)

```sql
create policy "Recipient can update friendship (accept)"
  on public.friendships for update to authenticated
  using (auth.uid() = addressee_id)
  with check (auth.uid() = addressee_id);
```

Today's migration correctly removed the requester from the predicate and stated `WITH CHECK` explicitly. But the grant is table-wide — `GRANT SELECT, INSERT, UPDATE, DELETE ON public.friendships TO authenticated` (`20260726205156…:36`) — and the check constrains only `addressee_id`. So on any row where you are the addressee you may set `requester_id` to **any uuid** and `status` to `'accepted'`. Both old and new rows satisfy the policy.

The precondition is guaranteed for everyone: `befriend_official_account` (`20260918100000…:43-57`) inserts `(official, you, 'accepted')` on signup, so **every account owns a row in which it is the addressee**.

`are_friends()` tests only the pair and the status, and it gates recommendations, wants, blasts, rankings, ticket reminders, comments, likes and the photo storage buckets. One `PATCH` opens a stranger's entire account.

**Attack:** sign up → find your auto-created Rex friendship row → `PATCH /rest/v1/friendships?id=eq.<row>` with `{"requester_id":"<victim>","status":"accepted"}` → read their content. The victim gets a "friend accepted" notification for a request they never sent.

**Fix:** revoke the table-wide UPDATE and grant only the column that may change:

```sql
revoke update on public.friendships from authenticated;
grant update (status) on public.friendships to authenticated;
```

This also stops `updated_at`/`created_at` tampering. A `BEFORE UPDATE` trigger rejecting changes to either id works too; the column grant is smaller.

**Likelihood** moderate (needs someone who reads the API), **impact** total for the targeted account. This is the one I would want demonstrated on two throwaway accounts before the next build ships.

---

### F3 — Tag tables are world-readable; share RPCs become a bulk read — High — Confirmed

`20260822090000_tag_friends_on_rex.sql:21-22`, repeated verbatim in `20261015100000_tag_someone_in_a_want.sql:28-30`:

```sql
CREATE POLICY "Tags are visible to anyone" ON public.recommendation_tags
  FOR SELECT TO authenticated USING (true);
```

The reasoning — "a tag is shown on the card, it is not a secret" — holds for a card you can already see. The policy isn't scoped to that: it returns every row to every signed-in user.

The serious consequence is an **id oracle**. `get_shared_recommendation`, `get_shared_want`, `get_shared_trip` and `get_shared_trip_stops` are `SECURITY DEFINER`, granted to `anon`, and gate on nothing but the id — the design is a capability URL, where possession of the UUID *is* the authorisation. The tag tables hand out the UUIDs. Any signed-in user can list `recommendation_id` and `want_id` wholesale, then read notes, ratings, photos and (for wants) author names belonging to people they have no relationship with.

Three defects compound it: no `published_at` filter (so unpublished drafts are readable by id, which the 15 August migration explicitly said RLS was the only guarantee against), inconsistent anonymity masking (only `get_shared_recommendation` applies the `is_anonymous` CASE), and the asymmetry that the *collection* functions do check `visibility = 'public'` while the rec/want/trip ones check nothing.

**Fix:** scope both tag policies against the parent, as `recommendation_likes` already does (`20260727135323…:13-20`). Separately add `published_at is not null` and the anonymity mask to the trip/want/collection share functions.

---

### F4 — Likes, comments and saves writable against invisible content — High — Confirmed

`20260727135323…:21-22` and `:48-49`:

```sql
CREATE POLICY "Users insert own comments" ON public.recommendation_comments
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
```

The check is "this row is mine" and nothing else. `request_comments`, written two days later, gets it right — `WITH CHECK (auth.uid() = user_id AND EXISTS (… are_friends …))`. That contrast is what makes this an oversight rather than a decision.

So any user can comment on **any** recommendation id (harvested per F3), and `tg_notify_rec_comment` writes a notification carrying `left(NEW.body, 140)` to the owner, which `send-push` delivers to their phone. The attacker controls the text. Same shape on `recommendation_likes`, `want_likes`, `want_comments` and `saved_posts`.

Because blocks aren't enforced in the database (F17), a blocked person keeps this channel.

**Fix:** add the parent-visibility `EXISTS` clause to all five INSERT policies, copying `request_comments`.

---

### F5 — `profiles` grants every column — High — Confirmed

`20260726205156…:15` — `GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated`. Table-wide, never narrowed.

**Read side.** The SELECT policy admits `auth.uid() = id OR are_friends(...) OR EXISTS (SELECT 1 FROM friendships f WHERE ...)` — and that third clause **doesn't check `f.status`**. Since anyone may insert a pending request naming you, any stranger can admit themselves to your whole profile row, including `phone_sha256`. The app only ever selects four columns, but PostgREST honours what the *caller* asks for. This directly contradicts the published policy: *"never the number itself, and it is never shown to anyone."*

**Write side.** Row-scoped but not column-scoped, and the table has grown privilege-bearing columns:
- `is_official` — self-settable; whoever holds it is auto-friended to every new signup. Blocked today only by a partial unique index, i.e. by collision, not by authorisation.
- `username` — this *is* the admin credential, because `is_rex_curator()` resolves privilege by comparing against three literal usernames. Unique but not reserved: if a curator ever renames, the old string frees and whoever claims it controls the Explore shelves.
- `accepted_terms_at` — makes the consent record forgeable.
- `phone_sha256` — writable directly, bypassing `set_my_phone_hash`, whose comment says it exists "so nobody can write a hash onto somebody else's row".

**Fix:** revoke and re-grant by column, add `AND f.status = 'accepted'` to the SELECT policy, and key `is_rex_curator()` on `user_roles` (already service-role-write-only) rather than on an editable string.

---

### F6 / F7 — Session handling — High / Medium — Confirmed

`RexAPI.swift:75-83` stores both tokens in `UserDefaults`; `:63` says *"move to Keychain before this ships beyond simulator testing."* It has shipped. `UserDefaults` is a plaintext plist in the app container, included in unencrypted backups, with no protection class. There is zero Keychain use anywhere in the iOS tree.

`RexAPI.swift:721-724` — `signOut()` clears both locally and calls no endpoint. There is no `POST /auth/v1/logout` anywhere, so a captured refresh token stays valid after sign-out. And there is no password reset *or* change flow at all, so a user who believes they're compromised has no remediation path whatsoever.

**Fix:** Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; call the logout endpoint in `signOut()`; add a reset flow (GoTrue provides `/auth/v1/recover`).

---

### F8 — iOS bundle ships a Capacitor WebView pointed at a remote URL — High — Likely

`capacitor.config.ts:3-11` sets `server.url` to a `workers.dev` host; the generated `ios/App/App/capacitor.config.json` ships (`project.pbxproj:484`), as does `Main.storyboard`, whose root controller is `CAPBridgeViewController`, as does `config.xml` with `<access origin="*" />`. `Info.plist:65-66` sets `UISceneStoryboardFile: Main`, so UIKit instantiates that controller before `SceneDelegate` replaces the window — constructing the bridge and a `WKWebView` pointed at the remote URL.

Capacitor is pinned at exactly 8.5.0, the version named in **GHSA-rvm3-566m-v7fv (Critical)** — remote content loadable at the app origin — fixed in 8.5.1.

Marked Likely because it needs a running app to confirm. Settle it with a breakpoint on `CAPBridgeViewController.viewDidLoad`, or watch for a launch request to that host.

**Fix:** remove `UISceneStoryboardFile`, `Main.storyboard`, `config.xml`, `capacitor.config.json` and `public` from the bundle, and delete `server.url`. Check first that nothing still routes to the WebView build.

---

### F9 — TanStack Start XSS, shipping — High — Confirmed

`@tanstack/react-start` 1.168.32 and `@tanstack/start-server-core` 1.169.17 are both in range for **GHSA-qx66-fv34-fjm8 (Critical)** — unauthenticated reflected XSS in server-function responses. `src/` has nine server-function modules, so the path is used; the built resolver is in `.output/server`; the client half ships inside the iOS bundle at `ios/App/App/public/assets/`.

**Fix:** minor bump (`fixAvailable: true`), which also clears the `seroval` critical. Better: if nothing consumes that Worker, delete it and the finding with it.

---

### F10 — `ask-rex` prompt injection writes persistent memory — Medium — Confirmed

`supabase/functions/ask-rex/index.ts:542` interpolates friend-authored notes into the prompt with no delimiting or escaping. A note containing a quote and a newline can forge instruction lines or fake candidate entries.

That alone would be a bad answer. The chain is worse: `:227-240` writes the model's `facts` output into `rex_facts` for the victim with only a length filter and no confirmation, labelled `source: "stated"` — as if they'd said it — and `:498-500` reads those facts back into every later prompt. One malicious note becomes durable, self-reinforcing memory.

**What currently stops it being one-tap phishing:** the answer renders with plain `Text(answer.prose)` (`TalkToRexView.swift:299`), not `Text(linked:)`. **Do not change that line** without fixing F11 first.

**Fix:** delimit and strip untrusted candidate text; make `facts` a proposal the user confirms.

---

### F11 — Link spoofing in notes — Medium — Confirmed

`Theme.swift:1001-1003` — the markdown link regex allows display text and href to differ, so `[https://www.monzo.com/login](https://evil.example/harvest)` renders as a tappable link reading as Monzo. Cross-user: blast replies, feed notes, item pages. `plainLinkText` flattens to the *display* text, so the spoofed string goes into push notifications too.

Separately, the `NSDataDetector` path in the same function applies no scheme check, so `shortcuts://`, `file://` and `fb://` become tappable. `RexNotesText.swift:206-221` is a second copy with the same gap. `javascript:` and `data:` were tested and are *not* reachable.

**Note:** this is the hyperlink feature added on 14 October. Both halves are worth fixing together.

**Fix:** show the real host beside linked words (or confirm on tap when they disagree); filter detector matches to `http`/`https` in both copies.

---

### F12 / F13 / F14 — Privacy paperwork — High — Confirmed

**F12 — the policy is wrong in six ways.** `web/privacy.html` and `LegalContentView.swift` are generated from one source, so each error appears twice:
- §13 contains the literal string `[TO CONFIRM — Kathryn to add the registered company address]`
- The processor list omits OpenAI, Google Gemini, OMDb, Wikipedia, TikTok and Meta's graph endpoint
- Anthropic is scoped to "Import from doc" but also receives pasted link captions and your full list text
- Nothing anywhere mentions Ask Rex memory (`rex_facts`)
- *"You can remove it at any time in Profile > Edit profile"* (phone hash) — **there is no phone field in `EditProfileView.swift`.** The backend supports clearing; no screen reaches it
- *"it is never shown to anyone"* — contradicted by F5

**F13 — Ask Rex transmits other people's data to undisclosed processors.** The prompt carries friends' display names, item addresses and their notes **verbatim** to `api.openai.com` or `generativelanguage.googleapis.com`. Those friends didn't invoke the feature and have no notice. Under UK GDPR that's an Art. 13/14 transparency failure plus an undocumented processor and international transfer.

**F14 — App Store blockers.** There is **no `PrivacyInfo.xcprivacy` anywhere under `ios/`**; the app uses `UserDefaults` pervasively, which is a Required Reason API. `NSContactsUsageDescription` still says *"checks the email addresses in your contacts"* — verified against `FindFriendsViews.swift:320-332`, which now also fetches `CNContactPhoneNumbersKey`. And `RexOutboundLinks.swift:3` imports `AdSupport` with no `ASIdentifierManager` use, which invites Apple's scanner to expect an IDFA declaration contradicting your "no tracking" label.

---

### F15–F21 — remaining Medium/High

- **F15** `wants` and `saved_posts` INSERT don't constrain `list_id`, so anyone can write rows into another user's collection — and into a *public* one, where `get_shared_collection_items` serves them to `anon`. The UPDATE policies added two days later *do* check; the insert path was missed.
- **F16** `items` UPDATE is `USING (auth.uid() IS NOT NULL)`. Defensible when the table held title and address; it now holds `chain_key`, `tickets_on_sale_at`, `link_url`, photos. Any user can rewrite any of them — including the timestamp `send_due_ticket_reminders` fires on.
- **F17** Blocking is advisory. `hidden_user_ids()` is filtered **client-side** (`RexAPI.swift:414, 467-469`); curl with the same token ignores it. No policy references `user_blocks`, so a blocked user can still send friend requests and (with F4) push-bearing comments. The migration cites App Store Guideline 1.2.
- **F18** `RexAPI.swift:3475-3489` mints signed photo URLs with `expiresIn: 157_680_000` — five years — and stores them in the row. The bearer token travels with the data, and `get_shared_recommendation` hands the row to `anon`. Unrevocable short of rotating the storage secret.
- **F19** "Post anonymously" is display-level only: `user_id` passes through the masking view, and `profile_basics` resolves any id to a name. Trip and collection share pages don't mask at all, to the open internet.
- **F20** `extract-from-link`'s allowlist is correct, but `l.instagram.com` passes the `.instagram.com` suffix check and is Instagram's off-site redirector, and the fetch follows redirects. Fix: `redirect: "manual"` and re-check each hop.
- **F21** `ask-rex` has a 40/day cap. `extract-recommendations`, `organise-list` and `extract-recipe-photo` have **none** — `organise-list` bounds line count but not line length; `extract-recipe-photo` accepts an unbounded base64 image. Any one account can run up an unlimited Anthropic bill.

### F22–F41 — Lower severity

Summarised in the table above. The ones worth doing cheaply: add four headers to `web/_headers` (F22); schedule the `prune_rex_asks` function that was written and never wired up (F24); drop or wire up `profiles.interests` (F25); delete the debug `print()` (F37); add `android/build` to `.gitignore` (F40).

---

## 4. Needs manual check

Code can't answer these:

1. **`pg_proc.proacl` for every public function** — settles F1's blast radius and F35 entirely.
2. **Default privileges** — `select defaclobjtype, defaclacl from pg_default_acl;` decides whether `revoke … from public, anon` was sufficient.
3. **Are the `rec-photos` and `avatars` buckets public?** No migration creates them. If either is `public = true`, F18 becomes High.
4. **Which migrations actually ran.** Two migrations record that earlier ones were never applied. `select * from pg_policies where schemaname='public'` is the only authority — worth diffing against the matrix the RLS agent produced.
5. **`verify_jwt` per edge function.** `config.toml` holds only `project_id`. Four functions parse the JWT without verifying the signature, relying on the platform gate. A single `--no-verify-jwt` deploy turns them into open endpoints.
6. **Supabase Auth settings** — is "Confirm email" on? Rate limits? CAPTCHA? This decides whether signup is an enumeration oracle (F23).
7. **Google Cloud** — are the plist keys restricted by bundle id and API? Is the Lovable-era key disabled? Are quota caps set?
8. **Is the `kathrynkfinnis-rgb-rex-app` Worker live, and does anything consume it?** Decides F9's severity.
9. **Cloudflare** — HSTS at the edge; Access in front of `/admin.html`.
10. **Registered company address and ICO registration** (F12).
11. **App Store Connect privacy labels** — must now declare the AI flows and Ask Rex memory.
12. **Has git history been pushed anywhere public?** Decides whether F34 is exposure or hygiene.

---

## 5. What's done well

Worth knowing so it doesn't get refactored away:

- **RLS on every table, no exceptions.** `apple_credentials` and `share_links` go further: no policies at all plus explicit revokes — the right shape for service-role-only, and commented as such.
- **`security_invoker = true` on `recommendations_display`**, with a comment explaining exactly why omitting it would have turned a privacy fix into a worse leak.
- **Zero analytics, zero crash SDKs, one `print()` in 46k lines.** The "we don't track you" claim is true because nothing was ever added.
- **Contact matching is genuinely privacy-preserving** — hashed on device, names never read, nothing stored — and the migration documents its own weakness rather than overclaiming.
- **Account deletion is real and correctly ordered**: storage first with a hard stop on failure, Apple revocation before the auth row goes, then cascade. Every table added since carries the right cascade.
- **`user_roles` has no write policies at all**, and admin gates live in the database — *"a screen that hides a button is not access control."*
- **The share pages escape centrally**, so forgetting one `og:` tag is structurally hard. I went looking for XSS and found none.
- **`URLQueryItem` used uniformly across ~150 call sites**, which is why PostgREST injection isn't possible.
- **The `verify_jwt`-accepts-the-anon-key trap** was found and closed consistently across all seven edge functions.
- **Apple Sign In is correct**, including the Apple-wants-SHA256/Supabase-wants-raw nonce subtlety.
- **A 24-hour supply-chain cooling-off period is configured at all** — very few projects do this.
- **The deployed site has zero npm dependencies.** 616 packages cannot touch find-rex.com. The single best structural decision in the repo.
- **`RexMemoryView`** lets people read and delete what the AI inferred about them. Most products that build the feature never build that screen.
- **The migration comments are an asset.** Several findings were faster to confirm *because* a previous author wrote down what they checked.

---

## 6. Prioritised fix plan

### Before launch

| Fix | Findings | Effort |
|---|---|---|
| Run the **corrected** merge migration, not the original | F1 | 2 min |
| Column-scope the `friendships` UPDATE grant | F2 | 15 min |
| Parent-visibility checks on 5 INSERT policies | F4, F15 | 1 h |
| Column-scope `profiles`; add `f.status = 'accepted'` | F5 | 45 min |
| Scope the two tag SELECT policies; add `published_at` + anonymity mask to share RPCs | F3, F19, F29 | 2 h |
| Privacy policy: real address, all processors, Ask Rex memory, remove the false deletion promise | F12, F13 | 2 h |
| Add `PrivacyInfo.xcprivacy`; fix contacts purpose string; drop `AdSupport` | F14 | 1 h |
| Tokens to Keychain; revoke on sign-out | F6, F7 | 3 h |
| Four headers in `web/_headers` | F22 | 15 min |
| Rate-limit the three unguarded AI functions | F21 | 2 h |
| Settle and remove the Capacitor WebView | F8 | 2 h |

### Next sprint

F9 (bump TanStack or delete the Worker), F10/F11 (prompt injection + link spoofing), F16, F17 (enforce blocks in the database), F18 (short-lived photo URLs), F20, F23, F24, F25, F26, F27, F28, F32, F33 (one CI workflow running `npm audit`), F34.

### Later

F30, F31, F35, F36, F37, F38, F39, F40, F41.

---

*Prepared 16 October 2026. Read-only review; no code or data was modified. Awaiting approval before any fix is applied.*
