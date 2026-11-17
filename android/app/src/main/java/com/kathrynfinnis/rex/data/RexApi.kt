package com.kathrynfinnis.rex.data

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.storage.Storage

/**
 * The Android half of what RexAPI.swift does on iOS — against the same
 * project, the same row-level security and the same functions. Nothing here
 * decides who can see what; the database does, exactly as it does for iOS.
 *
 * The URL and key below are the public client pair that already ships inside
 * the iOS binary and in find-rex.com's Pages Functions. They are public by
 * design: RLS is what protects the data, not the key.
 */
object Rex {
    private const val URL = "https://uhpzkbkwxcgqfxmlyktj.supabase.co"
    private const val ANON_KEY =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHprYmt3eGNncWZ4bWx5a3RqIiwicm9sZSI6" +
        "ImFub24iLCJpYXQiOjE3ODU4Mzk2NDMsImV4cCI6MjEwMTQxNTY0M30." +
        "IvQ8byDwHErLhuJI1Pg3bRcb4AKK4sb9Bm6cr_6sHbI"

    val client: SupabaseClient = createSupabaseClient(URL, ANON_KEY) {
        install(Auth)
        install(Postgrest)
        install(Storage)
    }

    /**
     * Every read of a Rex goes through this view, never the recommendations
     * table. Nov 17, and it is a privacy fix rather than a tidy-up.
     *
     * "Post anonymously" hides the poster in the app's own UI only. The raw
     * row still carries the real user_id, and embedding profiles off it hands
     * back the real author of every anonymous Rex — which is what every read
     * in this file was doing, so an anonymous Rex was not anonymous on
     * Android at all. iOS closed this on 25 August (#181, security review)
     * with recommendations_display: a 1:1 passthrough whose `profiles` column
     * is NULL when the row is anonymous and you are not its owner.
     *
     * `security_invoker = true` on the view means recommendations' own RLS is
     * enforced as if the table had been queried directly, so this can only
     * ever narrow what is visible, never widen it.
     *
     * Two consequences for anything written against it. `profiles` is a plain
     * JSON column, not an FK embed, so it is selected by name and decodes to
     * RexAuthor, which has no id. And the name can be absent — use
     * FeedRecommendation.authorName, which says "Someone", rather than
     * reaching for a fallback the mask was meant to deny you.
     */
    private const val RECS = "recommendations_display"

    /** The columns every Rex read wants, in one place so they cannot drift. */
    private const val REC_COLUMNS =
        "id,rating,note,created_at,photo_urls,user_id,item_id,trip_id,show_in_feed,is_anonymous,profiles," +
        "items!inner(id,type,title,subtitle,image_url,genre,address,lat,lng,link_url,google_rating,chain_key)"

    /**
     * The feed, as close to fetchFeed() in RexAPI.swift as this early stage
     * warrants. Two of its rules are copied deliberately because getting
     * them wrong is visible immediately:
     *
     *  - trip_id is null, so a trip's fifteen stops don't become fifteen
     *    cards. Browsing hides them; search reaches them (8 October).
     *  - show_in_feed is null or true. Absent or true shows, only an explicit
     *    false hides — which is how a list keeps its items off the feed. The
     *    old web app missed this and would have posted every hidden row.
     *
     * Wants are a separate table and a separate query, merged in by date on
     * iOS. Not here yet; the feed is half a feed until it is.
     */
    suspend fun feed(limit: Long = 50): List<FeedRecommendation> =
        client.from(RECS)
            .select(Columns.raw(REC_COLUMNS)) {
                filter {
                    exact("trip_id", null)
                    or {
                        exact("show_in_feed", null)
                        eq("show_in_feed", true)
                    }
                }
                order("created_at", Order.DESCENDING)
                limit(limit)
            }
            .decodeList()

    /**
     * Nov 2 — the reads the core loop needs, beyond the feed.
     *
     * Kept as plain suspend functions on one object, matching what is already
     * here, rather than a repository per screen. Five screens against one
     * database do not need five indirections, and RexAPI.swift's own shape —
     * one type, many small methods — is what makes the two readable side by
     * side when something behaves differently on one platform.
     */

    /** Everything anybody has said about one thing. The item detail screen. */
    suspend fun recommendationsFor(itemId: String): List<FeedRecommendation> =
        client.from(RECS)
            .select(Columns.raw(REC_COLUMNS)) {
                filter { eq("item_id", itemId) }
                order("created_at", Order.DESCENDING)
            }
            .decodeList()

    /** One item on its own, for a card opened before its Rexes have loaded. */
    suspend fun item(itemId: String): RexItem? =
        client.from("items")
            .select { filter { eq("id", itemId) }; limit(1) }
            .decodeList<RexItem>()
            .firstOrNull()

    /**
     * Your want-to-try list. Whose is decided by RLS rather than by a filter
     * here — asking for somebody else's returns nothing rather than an error,
     * which is the behaviour every other read in this file has.
     */
    suspend fun myWants(): List<WantRow> =
        client.from("wants")
            .select(
                Columns.raw(
                    "id,created_at,item_id,user_id,list_id,show_in_feed,note," +
                    "items!inner(id,type,title,subtitle,image_url,genre,address,lat,lng,link_url,google_rating,chain_key)"
                )
            ) {
                order("created_at", Order.DESCENDING)
            }
            .decodeList()

    /**
     * Collections you own.
     *
     * The table is `hitlist_lists`, not `lists` — a leftover name from before
     * collections were called collections, and the one thing about this
     * schema nobody would guess. Nov 4: this read asked for `lists` and
     * PostgREST 404'd the tab for anyone who opened it.
     *
     * Filtered by user_id as well as RLS, matching fetchLists on iOS: RLS lets
     * you see collections shared with you, and this list is specifically the
     * ones that are yours.
     *
     * Ordering mirrors iOS exactly, nullslast included — without it a
     * collection you have never dragged sorts above every one you have.
     */
    suspend fun myCollections(): List<RexList> =
        client.from("hitlist_lists")
            // Exactly the fields RexList declares, no more: user_id is not
            // optional on the model, and sort_order can be ordered by without
            // being selected.
            .select(Columns.raw("id,name,user_id,emoji,topic,created_at")) {
                filter { eq("user_id", RexAuth.currentUserId ?: error("Not signed in.")) }
                order("sort_order", Order.ASCENDING, nullsFirst = false)
                order("created_at", Order.DESCENDING)
            }
            .decodeList()

    /**
     * What is inside one collection.
     *
     * Two queries rather than one embed, and not by choice. saved_posts'
     * foreign key points at the recommendations table, so a nested embed can
     * only name the table — which would hand back the real author of an
     * anonymous Rex inside a collection, the one path the view could not
     * cover. So the rows come first without their Rex, and the Rex come from
     * the view by id and are merged here.
     *
     * The cost is one extra round trip per collection open. The alternative
     * was a privacy hole in the only read that could still have one.
     */
    suspend fun collectionItems(listId: String): List<SavedPost> {
        val rows = client.from("saved_posts")
            .select(Columns.raw("id,list_id,recommendation_id,note,section,sort_order")) {
                filter { eq("list_id", listId) }
            }
            .decodeList<SavedPost>()

        val ids = rows.mapNotNull { it.recommendationId }.distinct()
        if (ids.isEmpty()) return rows
        val byId = client.from(RECS)
            .select(Columns.raw(REC_COLUMNS)) { filter { isIn("id", ids) } }
            .decodeList<FeedRecommendation>()
            .associateBy { it.id }
        return rows.map { row ->
            row.copy(recommendations = row.recommendationId?.let { byId[it] })
        }
    }

    /**
     * Somebody's own Rex, newest first — the profile screen, yours or theirs.
     *
     * trip_id is null for the reason iOS records against this exact query:
     * adding an existing Rex to a trip creates a second row for the same item
     * as a stop, with no rating, note or photo of its own. Without the filter
     * the profile showed the real Rex and the bare stop row side by side —
     * "I just added this Rex to a trip and now it has duplicated".
     *
     * No show_in_feed filter, deliberately, and this is where it differs from
     * feed(): a Rex you have kept out of the feed is still yours and still
     * belongs on your profile. RLS decides whether you may see somebody
     * else's at all.
     */
    suspend fun recommendationsBy(userId: String): List<FeedRecommendation> =
        client.from(RECS)
            .select(Columns.raw(REC_COLUMNS)) {
                filter {
                    eq("user_id", userId)
                    exact("trip_id", null)
                }
                order("created_at", Order.DESCENDING)
            }
            .decodeList()

    /**
     * Somebody else's collections.
     *
     * visibility in (public, friends) as well as RLS, matching
     * fetchLists(forUser:) on iOS — a private collection is not something to
     * list on a profile even to someone the policy would let read it.
     */
    suspend fun collectionsOf(userId: String): List<RexList> =
        client.from("hitlist_lists")
            .select(Columns.raw("id,name,user_id,emoji,topic,created_at")) {
                filter {
                    eq("user_id", userId)
                    isIn("visibility", listOf("public", "friends"))
                }
                order("created_at", Order.DESCENDING)
            }
            .decodeList()

    /** Your own profile row, for the avatar and the name in the chrome. */
    suspend fun myProfile(): RexProfile? {
        val id = RexAuth.currentUserId ?: return null
        return client.from("profiles")
            .select { filter { eq("id", id) }; limit(1) }
            .decodeList<RexProfile>()
            .firstOrNull()
    }

    // ──────────────────────────────────────────────────── notifications

    /**
     * Nov 17 — the bell. In-app only: this is the list, not the delivery.
     * Push on Android is a separate and much larger job — there is no Firebase
     * or FCM anywhere in this project, so send-push has only ever reached
     * iPhones.
     *
     * Actors come separately because notifications.actor_id has no foreign key
     * to profiles and so cannot be embedded. Best-effort: a notification
     * whose actor cannot be resolved still reads, as "Someone".
     */
    suspend fun notifications(): List<RexNotification> {
        val userId = RexAuth.currentUserId ?: error("Not signed in.")
        val rows = client.from("notifications")
            .select(
                Columns.raw("id,actor_id,type,entity_type,entity_id,data,read_at,created_at")
            ) {
                filter { eq("user_id", userId) }
                order("created_at", Order.DESCENDING)
                limit(100)
            }
            .decodeList<RexNotification>()

        val actorIds = rows.mapNotNull { it.actorId }.distinct()
        if (actorIds.isEmpty()) return rows
        val byId = runCatching { profiles(actorIds) }.getOrDefault(emptyList()).associateBy { it.id }
        rows.forEach { n ->
            byId[n.actorId]?.let { p ->
                n.actor = RexAuthor(
                    username = p.username,
                    displayName = p.displayName,
                    avatarUrl = p.avatarUrl,
                )
            }
        }
        return rows
    }

    /**
     * Item ids for a batch of recommendation ids.
     *
     * A notification's entity_id is the recommendation, and every screen
     * Android can open is addressed by item. iOS resolves the same way and
     * records why: passing entity_id to an item screen directly just 404s.
     */
    suspend fun itemIdsFor(recommendationIds: List<String>): Map<String, String> {
        if (recommendationIds.isEmpty()) return emptyMap()
        return client.from(RECS)
            .select(Columns.raw("id,item_id")) { filter { isIn("id", recommendationIds) } }
            .decodeList<RecItemId>()
            .associate { it.id to it.itemId }
    }

    /**
     * Best-effort, like iOS: having read your notifications is not something
     * worth showing an error about, and the list is already on screen.
     */
    suspend fun markNotificationsRead(ids: List<String>) {
        if (ids.isEmpty()) return
        val now = java.time.OffsetDateTime.now(java.time.ZoneOffset.UTC).toString()
        runCatching {
            client.from("notifications")
                .update(ReadAtPatch(now)) { filter { isIn("id", ids) } }
        }
    }

    /** Your own notifications are yours to delete — RLS says so explicitly. */
    suspend fun deleteNotification(id: String) {
        client.from("notifications").delete { filter { eq("id", id) } }
    }

    // ──────────────────────────────────────────────────────── friends

    /**
     * Nov 17 — the first thing an Android build needs that it did not have.
     *
     * Until now there was no way to follow anybody on Android at all, which
     * made the feed permanently empty: it reads what the people you follow
     * have posted, and you could not follow anyone. The empty state even
     * promised it would fill up.
     *
     * Two of these go through RPCs rather than reading the table, and that is
     * not an optimisation — see searchProfiles and the fallback in profiles().
     */

    /**
     * Every friendship you are part of, pending and accepted.
     *
     * requester_id and addressee_id reference auth.users(id) rather than
     * profiles, so there is no PostgREST embed to be had — the profiles come
     * separately and are merged by the caller, exactly as FriendsView.swift
     * does it.
     */
    suspend fun friendships(): List<Friendship> =
        client.from("friendships")
            .select(Columns.raw("id,requester_id,addressee_id,status"))
            .decodeList()

    /**
     * Names and avatars for a set of ids.
     *
     * The two-step matters. The profiles SELECT policy returns yourself, your
     * friends, and anyone you already have a friendship row with — so a
     * stranger comes back *missing* rather than refused: 200 OK, one fewer
     * row, nothing to notice. iOS hit this on 5 October with a stranger's
     * profile page showing no name at the exact moment you were deciding
     * whether to add them. Anyone the table declines to hand over is looked up
     * through profile_basics, which returns the same four columns.
     *
     * The fallback is best-effort: on a project where that function has not
     * been created the caller still gets everybody the table did return.
     */
    suspend fun profiles(ids: List<String>): List<RexProfile> {
        if (ids.isEmpty()) return emptyList()
        val direct = client.from("profiles")
            .select(Columns.raw("id,username,display_name,avatar_url")) {
                filter { isIn("id", ids) }
            }
            .decodeList<RexProfile>()

        val missing = ids.filterNot { id -> direct.any { it.id == id } }
        if (missing.isEmpty()) return direct
        val extra = runCatching {
            client.postgrest.rpc("profile_basics", ProfileBasicsArgs(missing))
                .decodeList<RexProfile>()
        }.getOrDefault(emptyList())
        return direct + extra
    }

    /**
     * Search by name or username.
     *
     * Through the search_profiles RPC, and it has to be. The obvious version —
     * select from profiles with an ilike — reads correctly and returns nothing
     * useful, because the RLS policy narrows profiles to "self, friends, or a
     * pending friendship row". So searching for anyone you are not already
     * connected to, which is the entire point of searching, comes back empty
     * with a 200 and no error.
     *
     * That is not hypothetical. It is how iOS's search quietly returned
     * nothing from July to September (#128). search_profiles exists as a
     * SECURITY DEFINER function specifically to get past this. Do not
     * "simplify" this into a table read.
     */
    suspend fun searchProfiles(query: String): List<RexProfile> =
        client.postgrest.rpc("search_profiles", SearchProfilesArgs(query.trim()))
            .decodeList()

    /**
     * People you might know, ranked by mutuals.
     *
     * suggested_friends_for_me, not suggested_friends_for: the second takes an
     * explicit caller argument and is locked to service_role, because any
     * authenticated caller could otherwise pass somebody else's id. This one
     * reads auth.uid() itself.
     */
    suspend fun suggestedFriends(limit: Int = 20): List<SuggestedFriend> =
        client.postgrest.rpc("suggested_friends_for_me", SuggestedFriendsArgs(limit))
            .decodeList()

    /** Ask to be friends. The row starts pending; they decide. */
    suspend fun sendFriendRequest(addresseeId: String) {
        val userId = RexAuth.currentUserId ?: error("Not signed in.")
        client.from("friendships").insert(
            NewFriendship(requesterId = userId, addresseeId = addresseeId)
        )
    }

    /**
     * Accept or decline. Declining deletes the row rather than marking it
     * rejected, matching iOS — which also means a request can be sent again
     * later, instead of one "no" being permanent.
     */
    suspend fun respondToFriendRequest(id: String, accept: Boolean) {
        if (accept) {
            client.from("friendships")
                .update(FriendshipStatusPatch("accepted")) { filter { eq("id", id) } }
        } else {
            client.from("friendships").delete { filter { eq("id", id) } }
        }
    }

    // ──────────────────────────────────────────────────────── writing

    /**
     * Nov 2 — adding a Rex, and the deduplication that has to come with it.
     *
     * Written by hand rather than fanned out to an agent alongside the
     * screens, because the rules below are the ones iOS spent a fortnight
     * getting wrong in public. Reimplementing them from the screen's point of
     * view would reproduce every one of those bugs on a second platform, and
     * they are invisible until somebody's list has two of something.
     */

    /** An item already in the catalogue from the same source. */
    private suspend fun findByExternalId(source: String, externalId: String): String? =
        client.from("items")
            .select(Columns.raw("id")) {
                filter {
                    eq("external_source", source)
                    eq("external_id", externalId)
                }
                limit(1)
            }
            .decodeList<ItemId>()
            .firstOrNull()?.id

    /**
     * Nov 1 on iOS — "still double rexing if you have had it as a want to try
     * and then go there". The cause was two rows: a want against an item
     * called "WAR" and a Rex against one called "War".
     *
     * Title and subtitle together, case-blind. Title alone would merge the
     * 2007 film War with the 2019 one; a film's subtitle is its director and
     * year and a book's is its author, so requiring both asks "same title by
     * the same person". Where either side has no subtitle it declines — a
     * duplicate is better than two different things merged.
     */
    private suspend fun findByTitle(type: String, title: String, subtitle: String?): String? {
        val mine = subtitle?.trim()?.lowercase().orEmpty()
        if (mine.isEmpty() || title.trim().length < 2) return null
        return client.from("items")
            .select(Columns.raw("id,title,subtitle")) {
                filter {
                    eq("type", type)
                    // ilike with no wildcards is an exact, case-blind match.
                    ilike("title", title.trim())
                }
                limit(25)
            }
            .decodeList<ItemMatch>()
            .firstOrNull { it.subtitle?.trim()?.lowercase() == mine }
            ?.id
    }

    /**
     * The item row, reused if we already hold it.
     *
     * Not yet carried over from iOS: the two geographic checks — same
     * coordinates, and same name at the same address — which catch two people
     * adding one restaurant by different routes. They need the map work this
     * build does not have, and a place added here still dedupes on its Google
     * place id, which is how most of them arrive.
     */
    suspend fun findOrCreateItem(
        type: String,
        title: String,
        subtitle: String? = null,
        imageUrl: String? = null,
        genre: String? = null,
        address: String? = null,
        linkUrl: String? = null,
        externalId: String? = null,
        externalSource: String? = null,
    ): String {
        if (externalId != null && externalSource != null) {
            findByExternalId(externalSource, externalId)?.let { return it }
        }
        if (type != "place" && type != "event") {
            findByTitle(type, title, subtitle)?.let { return it }
        }
        return client.from("items")
            .insert(
                NewItem(
                    type = type,
                    title = title.trim(),
                    subtitle = subtitle,
                    imageUrl = imageUrl,
                    genre = genre,
                    address = address,
                    linkUrl = linkUrl,
                    externalId = externalId,
                    externalSource = externalSource,
                )
            ) { select(Columns.raw("id")) }
            .decodeList<ItemId>()
            .first().id
    }

    /**
     * Your take on something. Posting one clears any want you had for it —
     * "the Rex should convert to a proper Rex, so it shouldn't come up with
     * two ratings for the thing" (14 October).
     */
    suspend fun createRecommendation(itemId: String, rating: Double, note: String?) {
        val userId = RexAuth.currentUserId ?: error("Not signed in.")
        client.from("recommendations").insert(
            NewRecommendation(
                userId = userId,
                itemId = itemId,
                rating = rating,
                note = note?.trim()?.ifEmpty { null },
            )
        )
        clearWantOnReview(itemId)
    }

    /**
     * Change your mind about a Rex you already posted.
     *
     * Nov 17 — rating and note ONLY, and that is the whole design of it.
     *
     * updateRecommendation in RexAPI.swift also writes photo_urls, photo_url
     * and tags on every call, because the iOS editor owns all five fields.
     * Android has no photo picker and no tag UI, so porting that signature
     * would mean every Android edit sending empty arrays — and silently
     * deleting the photos and tags somebody had added from their iPhone. A
     * typo fix on the train would quietly wipe the picture.
     *
     * So this is the narrow PATCH: the two fields this platform can actually
     * edit, leaving every other column exactly as it was. Add a field here
     * only when there is UI behind it.
     */
    suspend fun updateRecommendation(id: String, rating: Double, note: String?) {
        client.from("recommendations").update(
            RecommendationPatch(rating = rating, note = note?.trim()?.ifEmpty { null })
        ) {
            filter { eq("id", id) }
        }
    }

    /**
     * Delete a Rex of your own.
     *
     * Children first. A trip or a list is a parent row whose stops and items
     * are recommendations carrying its id in trip_id or list_id; deleting the
     * parent alone would orphan every one of them. Same order as iOS.
     *
     * Then the row itself, asking for what was deleted back. PostgREST answers
     * a DELETE that matched nothing with the same success as one that matched
     * — so without reading the result, a delete that row-level security
     * quietly refused is indistinguishable from one that worked, and the row
     * reappears on the next refresh with no error ever shown. iOS learnt this
     * on deleteWant.
     */
    suspend fun deleteRecommendation(id: String) {
        for (parent in listOf("trip_id", "list_id")) {
            client.from("recommendations").delete { filter { eq(parent, id) } }
        }
        val deleted = client.from("recommendations")
            .delete {
                select(Columns.raw("id"))
                filter { eq("id", id) }
            }
            .decodeList<ItemId>()
        if (deleted.isEmpty()) {
            error("Couldn't delete that — it may already be gone. Pull to refresh.")
        }
    }

    /** Somewhere you mean to go. */
    suspend fun createWant(itemId: String) {
        val userId = RexAuth.currentUserId ?: error("Not signed in.")
        client.from("wants").insert(NewWant(userId = userId, itemId = itemId))
    }

    suspend fun removeWant(itemId: String) {
        val userId = RexAuth.currentUserId ?: return
        client.from("wants").delete {
            filter {
                eq("user_id", userId)
                eq("item_id", itemId)
            }
        }
    }

    /**
     * Best-effort on purpose: the review is the thing that mattered and it is
     * already saved. Failing to tidy the want afterwards should not turn a
     * successful post into an error on screen.
     *
     * iOS also moves the want's collection placement onto the new Rex, so a
     * want filed in a list stays in that list. Not here yet — this build has
     * no collection editing, so there is no placement to carry.
     */
    private suspend fun clearWantOnReview(itemId: String) {
        runCatching { removeWant(itemId) }
    }
}
