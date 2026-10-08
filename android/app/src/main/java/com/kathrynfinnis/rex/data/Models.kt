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
