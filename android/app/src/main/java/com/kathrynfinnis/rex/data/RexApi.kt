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
}
