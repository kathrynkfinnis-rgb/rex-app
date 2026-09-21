# What's left before we can submit REX

App ID 6799256042 · `com.kathrynfinnis.rexapp` · version 1.0
Checked against App Store Connect on 18 September 2026. Version 1.0 is in
Prepare for Submission with no build attached.

Live version, where ticks and owners are shared between the three of us:
https://claude.ai/code/artifact/1538405b-499d-4c8f-963c-62384de27585

**13 of these block submission outright. 16 are open in total. 6 are settled.**

---

## Listing copy and metadata

All of it is empty in App Store Connect today. Claude can draft and enter every
one; what's needed from us is a yes or a rewrite.

| | Owner | |
| --- | --- | --- |
| **Subtitle** — blocks | | 30 characters, under the name in search. Working idea: "From people you trust". |
| **Description** — blocks | | Up to 4,000 characters. Draft below. |
| **Keywords** — blocks | | 100 characters, comma separated, never shown. Don't repeat the name or subtitle. |
| **Support / privacy / marketing URLs** — blocks | | All three exist now: `find-rex.com/support.html`, `find-rex.com/privacy.html`, `find-rex.com`. |
| **Primary category** — blocks | | Not set. Social Networking fits what REX does; Lifestyle is softer and less competitive. |
| **Promotional text** | | 170 characters, changeable without review. Skippable for now. |

### Starting point for the description

> REX is where the recommendations you actually trust live: the restaurant your
> sister raved about, the book your friend couldn't put down, the trip worth
> copying stop by stop.
>
> Everything comes from someone you chose to follow — their rating, their words,
> their photos. No algorithm, no strangers, no ads.

*Draft only — the real thing needs about 400 more words, in your voice.*

---

## Only we can do these

Apple ties them to a signed-in human, or they're judgement calls nobody should
make on our behalf.

| | Owner | |
| --- | --- | --- |
| **Screenshots** — blocks | | The biggest job left. Sizes below. The feed, a trip, the map and a single Rex are the four worth showing. |
| **Age rating questionnaire** — blocks | | Answered to land on 16+ as agreed. Claude can fill it in, but someone has to agree the answers are true. |
| **Privacy nutrition label** — blocks | | Declares what REX collects: name, email, photos, rough location, usage. Must match the privacy policy — Apple does check. |
| **Demo account for the reviewer** — blocks | | REX shows nothing until you have friends, so the reviewer needs an account with a populated feed, or they reject it as empty. |
| **Content rights declaration** — blocks | | Whether the app shows third-party content. It does — book covers, film posters, Google place data. |
| **Press Submit** — blocks | | Only an Account Holder or Admin can. |

### Screenshot sizes

| Set | Size | How many |
| --- | --- | --- |
| 6.9" iPhone | 1320 × 2868 | 3 minimum, 10 max |
| 6.5" iPhone | 1242 × 2688 | 3 minimum, 10 max |
| iPad | — | Only if we ship for iPad |

---

## Engineering

Claude's to build. Only the first two block submission.

| | Owner | |
| --- | --- | --- |
| **Sign in with Apple token revocation** — blocks | Claude | Apple requires that deleting your account also revokes the Apple token. Deletion works; this half doesn't exist. Needs an Apple key and a server function — about half a day. |
| **Attach a build to version 1.0** — blocks | Claude | None attached. Trivial once we pick one; 48 is the candidate. |
| **Leaked-password protection** | Claude | One toggle in Supabase Auth, from the security lint. Not an Apple requirement. |
| **Non-empty first-run feed** | Claude | The REX account can be queued with posts, which also solves what the reviewer sees. Same job as the demo account, from the other end. |

---

## Already settled

Here so nobody re-opens them.

- **Public website** — find-rex.com is live, including the share pages every
  in-app link points at.
- **Privacy policy and terms** — rewritten from both drafts, 16+, England &
  Wales, generated from the app's own copy so they can't drift. One gap: the
  registered company address.
- **Report and block** — Guideline 1.2, required for user-generated content.
  Shipped in build 47 and live in the database.
- **Account deletion and data export** — both in Settings → Your data & privacy.
  Deletion is a hard Apple requirement.
- **Push notifications** — fixed 18 September. The APNs key had been created
  sandbox-only, so Apple refused every send.
- **Consent at sign-up** — terms and privacy accepted at sign-up, with a version
  recorded against each account.
