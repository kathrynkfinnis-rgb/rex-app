# Rex — handover

Written 16 November 2026, for someone joining the project with their own
Claude. Read `AGENTS.md` first: it covers the repo layout, the brand pipeline
and the deploy commands, and it does not repeat them here. This file is the
state of play, which `AGENTS.md` deliberately does not hold.

## What Rex is

An iOS app for keeping track of things you have enjoyed — places, books,
films, TV, podcasts, recipes, events — and seeing what your friends have
enjoyed. A recommendation is a "Rex". You can also put out a "blast", which
is a question to your friends, and collect their answers in one place.

Live on the UK and US App Stores as **Find Rex**, free, iOS 18 and later.

## Where it stands

**1.0.1 (build 105) shipped on 16 November** and is the public version. It
carried fourteen fixes found through TestFlight the week before.

The store name is **Find Rex** rather than Rex because "Rex" alone is taken on
another Apple account — App Store Connect refuses it outright. "Rex -
Recommendations" is available and is the plan for the next version. The app
itself says Rex everywhere, and the icon on a phone reads Rex.

**Build 106 is in progress**, fixing the TestFlight round from build 105.

## How work actually happens

1. Testers report through TestFlight feedback, with screenshots. Two groups:
   **Founders** (internal, 3 people, gets every build automatically) and
   **Testers** (external, 21 people, needs Apple's beta review each time).
2. Feedback is pulled with `python3 ~/rex-app-build/asc.py feedback <build>`,
   and the screenshots with `asc.py shots <build> <dir>`. The screenshot is
   usually the whole diagnosis — the comment rarely says which screen.
3. Fixes land on `main` directly. There is no branch protection and no CI gate
   on merge.
4. A build is archived, exported, uploaded and distributed by hand.

## The things that will bite you

**There are no tests.** None. No unit tests, no UI tests, nothing runs the app
except a person. Every fix in 1.0.1 was compile-checked and shipped without
being run, because the only device with a real account on it belongs to
Kathryn. If you change shared code — the feed, the API layer, the card view —
assume you have broken something and get it onto a phone before it ships.

**Everything deploys separately.** The app, the edge functions, the website
and the database migrations are four independent deploys. An edge function
does *not* ride along with an app build, and a migration is run by hand in the
Supabase SQL editor. A fix that spans two of them is not finished when the
build goes out.

**The repo is public.** No secrets in it, and keep it that way. Keys are
handed over separately.

**Google Places costs money.** Roughly 250–300 calls a day. There is a
per-device daily ceiling in `GoogleBudget` — that is a brake on runaway code,
not a cost control, and there is no account-level cap. Spend is currently
about £0.39 a month because of a 10k-free-per-SKU allowance, but the error
rates are bad: around 13% of text searches and over half of geocoding calls
fail. Failures are swallowed and return an empty list, so a person
experiences them as "Rex can't find things" and searches again.

**Amazon affiliate is switched off.** The `findrex-21` tag was rejected —
Amazon reviewed find-rex.com, found no tagged links there (they are in the
app) and could not verify the traffic source. The tag is blanked in
`RexOutboundLinks` until a new one is approved, and the reapplication will be
under Three Lines Studios Ltd with the iOS app as the declared property.
Expect a new tracking ID, not that one back.

**find-rex.com is out of date.** It still says "Join the beta on TestFlight"
and names the company without its final "s". The corrected copy is committed
and has never been deployed.

## Conventions worth matching

Comments in this codebase explain *why*, usually with the date and the words
of whoever reported the problem. They are not decoration: several bugs have
been found by reading a comment that no longer matched the code. Match the
density and the habit, and quote the report that caused the change.

Commit messages are the same shape — what was reported, what was actually
wrong, and what was rejected along the way.

## Open work

* The feedback round from build 105 (keyboard hiding the note field, drafts
  not working for books, blasts that cannot be deleted, a link missing its
  arrow, Explore returning children's books for an adult request).
* Reposting someone else's Rex when you have been there too — the most asked
  for thing on the list.
* Map: filter by rating, and show ratings on the pins.
* 55% geocoding failure rate.
* 54 Dependabot alerts, 6 critical, on a public repo. Unexamined.
* Android is behind iOS and needs scoping before anyone starts.
* Apple Developer account is an Individual one; converting it to an
  Organization under Three Lines Studios Ltd is what would give other people
  their own App Store Connect and TestFlight logins.
