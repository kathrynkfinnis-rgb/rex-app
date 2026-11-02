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

    /** Collections you own. */
    suspend fun myCollections(): List<RexList> =
        client.from("lists")
            .select { order("created_at", Order.DESCENDING) }
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
}
