# Recommendations — friend-powered picks across places, books, movies & TV

An installable iPhone web app (PWA) where you and your friends share recommendations across categories, check in / review, and see what friends are loving.

## Categories

- **Restaurants & places** — map pin, address, check-in supported
- **Books** — title, author, cover
- **Movies** — title, year, poster
- **TV shows** — title, poster

Each recommendation has: category, rating (1–5), note, optional photo, friend attribution.

## Core screens

- **Feed** (home): friends' recent recommendations across all categories, filterable by category chip (All / Places / Books / Movies / TV).
- **Map**: only Places category — pins for restaurants + check-in-able spots.
- **Add**: pick category first → smart search per type (Google Places for restaurants, Google Books for books, TMDB for movies/TV) → rating + note.
- **Item detail**: friends' ratings & notes, add your own, "I've been here / read it / seen it" check-in.
- **Friends**: request/accept by username.
- **Profile**: your recommendations grouped by category.

## Tech decisions

- **Backend**: Lovable Cloud (auth, Postgres, storage, server functions).
- **Auth**: email/password + Google. Usernames for friend search.
- **Search per category**:
  - Places → Google Maps Platform connector (Places API)
  - Books → Google Books API (public, no key needed for basic search)
  - Movies/TV → TMDB API (requires a free API key you'd add as a secret)
- **Push**: Web Push (VAPID). iOS requires "Add to Home Screen" first — I'll build an install prompt.
- **PWA**: manifest + icons for home-screen install.

## Data model (RLS on, friend-scoped reads)

- `profiles` (id, username, display_name, avatar_url)
- `friendships` (requester_id, addressee_id, status)
- `items` — unified table for the thing being recommended:
  - id, type ('place' | 'book' | 'movie' | 'tv')
  - title, subtitle (author / year / cuisine), image_url
  - external_id (google_place_id / isbn / tmdb_id), external_source
  - lat, lng (nullable — places only)
- `recommendations` (id, user_id, item_id, rating, note, photo_url, created_at)
- `check_ins` (id, user_id, item_id, note, created_at)
- `push_subscriptions` (user_id, endpoint, p256dh, auth)

One `items` table keeps the feed simple; `type` drives the UI.

## Build order

1. Enable Lovable Cloud + connect Google Maps.
2. Auth (email + Google) + profiles/usernames.
3. Schema + RLS.
4. Feed with category filter (start with a couple of seed items).
5. Add-recommendation flow — Places first, then Books, then Movies/TV.
6. Map screen (Places only).
7. Item detail + check-in + reviews.
8. Friends system.
9. PWA install prompt + web push on new friend recommendation.

## Caveats

- Installable web app, not App Store native. Feels app-like on iPhone once added to home screen.
- iOS push works only after home-screen install (Apple rule).
- Movies/TV needs a free TMDB API key — I'll ask for it when we get to that step.

Approve and I'll start building.