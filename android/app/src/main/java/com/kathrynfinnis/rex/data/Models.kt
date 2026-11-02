package com.kathrynfinnis.rex.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Mirrors the Swift models in ios/App/App/Native/Models.kt — same column
 * names, because both are decoding the same PostgREST rows. Anything added
 * to one needs adding to the other; the database is the contract.
 */
@Serializable
data class RexProfile(
    val id: String,
    val username: String,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
)

@Serializable
data class RexItem(
    val id: String,
    val type: String,
    val title: String,
    val subtitle: String? = null,
    @SerialName("image_url") val imageUrl: String? = null,
    val genre: String? = null,
    val address: String? = null,
    val lat: Double? = null,
    val lng: Double? = null,
    @SerialName("link_url") val linkUrl: String? = null,
    @SerialName("google_rating") val googleRating: Double? = null,
    @SerialName("chain_key") val chainKey: String? = null,
)

@Serializable
data class FeedRecommendation(
    val id: String,
    val rating: Double,
    val note: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("photo_urls") val photoUrls: List<String>? = null,
    @SerialName("user_id") val userId: String,
    @SerialName("item_id") val itemId: String,
    @SerialName("trip_id") val tripId: String? = null,
    @SerialName("show_in_feed") val showInFeed: Boolean? = null,
    val items: RexItem? = null,
    val profiles: RexProfile? = null,
) {
    /** The five-tier scale from RexRatingScale.swift, kept in step by hand. */
    val tier: String?
        get() = when {
            rating <= 0 -> null
            rating < 6 -> "Do not Rex"
            rating < 7 -> "Meh"
            rating < 9 -> "Rex"
            rating < 10 -> "Loved"
            else -> "Obsessed"
        }
}

/**
 * Nov 2 — the rest of what the core loop reads. Added in one go rather than
 * screen by screen, because every one of these is a shape the database
 * already returns and discovering them separately is how two screens end up
 * decoding the same row into two different classes.
 *
 * Column names match the Swift models exactly. The database is the contract:
 * anything added to one needs adding to the other.
 */

/**
 * Somewhere you mean to go, as distinct from somewhere you have been. Its own
 * table rather than a recommendation with no rating — a want has no opinion
 * in it yet, and the feed, the profile and the collections all treat the two
 * differently.
 */
@Serializable
data class WantRow(
    val id: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("item_id") val itemId: String,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("list_id") val listId: String? = null,
    @SerialName("show_in_feed") val showInFeed: Boolean? = null,
    val note: String? = null,
    val items: RexItem? = null,
)

/** A collection: a named group somebody has put things into. */
@Serializable
data class RexList(
    val id: String,
    val name: String,
    @SerialName("user_id") val userId: String,
    val emoji: String? = null,
    val topic: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)

/**
 * One row inside a collection. A saved post points at somebody's Rex; a want
 * filed in a collection sits in the wants table instead, which is why a
 * collection reads from two places and merges them.
 */
@Serializable
data class SavedPost(
    val id: String,
    @SerialName("list_id") val listId: String,
    @SerialName("recommendation_id") val recommendationId: String? = null,
    val note: String? = null,
    val section: String? = null,
    @SerialName("sort_order") val sortOrder: Int? = null,
    val recommendations: FeedRecommendation? = null,
)

/**
 * Who you are to each other. status is 'pending' or 'accepted'; which of the
 * two columns holds you decides whether a pending row is a request you sent
 * or one you have been sent.
 */
@Serializable
data class Friendship(
    val id: String,
    @SerialName("requester_id") val requesterId: String,
    @SerialName("addressee_id") val addresseeId: String,
    val status: String,
    @SerialName("created_at") val createdAt: String? = null,
)

// Insert and projection shapes. Separate from the read models because a row
// going in is not the row coming back: the database fills id, created_at and
// the defaults, and sending nulls for them would overwrite what it chose.

@Serializable
internal data class ItemId(val id: String)

@Serializable
internal data class ItemMatch(val id: String, val title: String, val subtitle: String? = null)

@Serializable
internal data class NewItem(
    val type: String,
    val title: String,
    val subtitle: String? = null,
    @SerialName("image_url") val imageUrl: String? = null,
    val genre: String? = null,
    val address: String? = null,
    @SerialName("link_url") val linkUrl: String? = null,
    @SerialName("external_id") val externalId: String? = null,
    @SerialName("external_source") val externalSource: String? = null,
)

@Serializable
internal data class NewRecommendation(
    @SerialName("user_id") val userId: String,
    @SerialName("item_id") val itemId: String,
    val rating: Double,
    val note: String? = null,
)

@Serializable
internal data class NewWant(
    @SerialName("user_id") val userId: String,
    @SerialName("item_id") val itemId: String,
)
