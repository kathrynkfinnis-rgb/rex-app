package com.kathrynfinnis.rex.data

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
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
        client.from("recommendations")
            .select(
                Columns.raw(
                    "id,rating,note,created_at,photo_urls,user_id,item_id,trip_id,show_in_feed," +
                    "items!inner(id,type,title,subtitle,image_url,genre,address,lat,lng,link_url,google_rating,chain_key)," +
                    "profiles!recommendations_user_id_fkey(id,username,display_name,avatar_url)"
                )
            ) {
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
        client.from("recommendations")
            .select(
                Columns.raw(
                    "id,rating,note,created_at,photo_urls,user_id,item_id,trip_id,show_in_feed," +
                    "items!inner(id,type,title,subtitle,image_url,genre,address,lat,lng,link_url,google_rating,chain_key)," +
                    "profiles!recommendations_user_id_fkey(id,username,display_name,avatar_url)"
                )
            ) {
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

    /** What is inside one collection. */
    suspend fun collectionItems(listId: String): List<SavedPost> =
        client.from("saved_posts")
            .select(
                Columns.raw(
                    "id,list_id,recommendation_id,note,section,sort_order," +
                    "recommendations(id,rating,note,created_at,photo_urls,user_id,item_id,trip_id,show_in_feed," +
                    "items!inner(id,type,title,subtitle,image_url,genre,address,lat,lng,link_url,google_rating,chain_key)," +
                    "profiles!recommendations_user_id_fkey(id,username,display_name,avatar_url))"
                )
            ) {
                filter { eq("list_id", listId) }
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
