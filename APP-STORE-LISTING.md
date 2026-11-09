# App Store listing copy

App ID 6799256042 · `com.kathrynfinnis.rexapp` · store name **Find Rex**

The live text for the listing, kept here so there is one copy to edit rather
than a screenshot in a chat. Written 8 November 2026.

APP-STORE-READINESS.md is the September pre-submission checklist and is now
historical — the app is approved. This file is the current copy.

## What needs a review and what does not

| Field | Changeable on a live app? |
| --- | --- |
| **Promotional text** | **Yes, any time.** No review, no new build. It appears above the description. |
| Description | No — needs a new version |
| Screenshots, app previews | No — needs a new version |
| Name, subtitle, keywords | No — needs a new version |
| App icon | No — it is compiled into the binary, so it needs a new build *and* a review |
| Price, availability | Yes, any time. No review. |

So the promotional text below can go live today. The description waits for
1.0.1, which is already going to carry the new icon and screenshots.

## Promotional text

170 characters maximum.

```
Rex is your place to keep track of everything you and your friends love. Because the best recommendations come from people you know.
```

## Description

4,000 characters maximum.

```
Tired of scrolling back through chats to find that one thing your friend recommended? Rex tracks everything you've been enjoying and lets you see what your friends are into:

📚 Books you've stayed up late reading

🎞️ Films worth watching twice

📺 TV shows to binge

🍝 Restaurants you always go back to

🧑🏽‍🍳 Recipes you make again and again

Need ideas instead? 💡 Ask your friends for recommendations on anything, from weekend escapes to what to cook tonight.

Friends, not strangers: Every recommendation comes from someone you chose to follow, with their own rating and their own words.
```

## What's new — 1.0.1

4,000 characters maximum. Ordered by what a person will actually notice, not
by what was hardest to build.

```
Take a photo without leaving Rex — the camera tile opens the camera now, not just your library.

Type @ while you're writing a Rex and your friends' names come up, the way they do in WhatsApp.

If a friend Rex'd something you've Rex'd too, you'll see both. No more one card standing in for two people.

Blasts: attachments show up on replies, and you can edit or delete your own.

Changed your mind about a trip or a list? Move it back to drafts.

Pasted links are one neat arrow now instead of a wall of text, and map pins stay apart for longer before they group together.

Fixed: a published list keeps its items, and a notification about a list opens the list.
```

Deliberately not mentioned:

* **The icon.** The November artwork is the same dino with tighter framing and
  a slightly yellower cream. Nobody will see a difference, and release notes
  that announce an invisible change teach people not to read them.
* **Affiliate links.** They were gated to TestFlight and now are not. That is
  revenue, not a feature, and saying so in the notes invites a conversation
  nobody is asking for.
* **The Rex rename.** Internal consistency. The store still reads Find Rex.

## A note on the name

Settled 9 November: the name is **Rex**, swept through the repo in one commit.
The App Store listing is still **Find Rex**, because only a new version can
change it — so 1.0.1 is the free opportunity, and after that it costs another
review.

Checked on 9 November: no app is named exactly "Rex" in the UK or US store, so
the name is probably free. But **Rex: Book, Movie & TV Tracker** (Late Summer
Labs LLC, released March 2026, still being updated) is the same word on the
same kind of product, which means Apple may read "Rex" as confusingly similar
and refuse it. App Store Connect is the only test that settles it.

## The website says the opposite

find-rex.com still leads with "Join the beta on TestFlight" and "Rex is in beta
on iPhone, and needs iOS 18 or later". The app is approved and on sale. That
copy should become an App Store link — but not until the territory list is
fixed, because an App Store button that 404s for a UK visitor is worse than a
TestFlight one that works.
