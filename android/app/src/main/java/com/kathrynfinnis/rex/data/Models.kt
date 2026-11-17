package com.kathrynfinnis.rex.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

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

/**
 * Who posted a Rex, as the recommendations_display view hands it over.
 *
 * Nov 17 — a separate type from RexProfile, and the difference is the point.
 * RexProfile is a row of the profiles table and has an id. This is the view's
 * precomputed `profiles` column, which is a plain JSON object with three keys
 * and no id — and which is **null when the Rex is anonymous and you are not
 * the person who posted it**.
 *
 * Reading the recommendations table directly instead would hand back the real
 * author of every anonymous Rex, which is exactly the hole the 25 August
 * security review closed on iOS (#181) and which this app had reopened. Every
 * read of a recommendation goes through the view now; see the note on feed().
 */
@Serializable
data class RexAuthor(
    val username: String,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
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
    @SerialName("is_anonymous") val isAnonymous: Boolean? = null,
    val items: RexItem? = null,
    val profiles: RexAuthor? = null,
) {
    /**
     * What to call the person who posted this. "Someone" when the view has
     * masked them, which is the whole point of the mask: the UI must not have
     * a name to fall back to.
     */
    val authorName: String
        get() = profiles?.displayName?.takeIf { it.isNotBlank() }
            ?: profiles?.username?.takeIf { it.isNotBlank() }
            ?: "Someone"

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

/**
 * Somebody you might know, from suggested_friends_for_me. Friends-of-friends
 * ranked by mutual count, plus active accounts with no mutuals at all so a
 * brand-new sign-up sees somebody rather than an empty screen.
 *
 * mutual_count defaults to 0 rather than being required: those no-mutual
 * suggestions are exactly the rows a new account gets, and a strict decode
 * would fail the whole list for the people who need it most.
 */
@Serializable
data class SuggestedFriend(
    val id: String,
    val username: String,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("mutual_count") val mutualCount: Int = 0,
)

/**
 * One row in the bell.
 *
 * `actor` is filled in after the fetch, not by the query: notifications.
 * actor_id has no foreign key to profiles, so there is no embed for PostgREST
 * to build. The web app and iOS both stitch it on the same way.
 *
 * `data` is a free-form jsonb payload whose keys depend on `type`, which is
 * why it stays a JsonObject rather than becoming a class per kind.
 */
@Serializable
data class RexNotification(
    val id: String,
    @SerialName("actor_id") val actorId: String? = null,
    val type: String,
    @SerialName("entity_type") val entityType: String? = null,
    @SerialName("entity_id") val entityId: String? = null,
    val data: JsonObject? = null,
    @SerialName("read_at") val readAt: String? = null,
    @SerialName("created_at") val createdAt: String,
) {
    /** Stitched on after the fetch; a body property, so never serialized. */
    var actor: RexAuthor? = null

    val isUnread: Boolean get() = readAt == null

    private fun str(key: String): String =
        (data?.get(key) as? JsonPrimitive)?.takeIf { it.isString }?.content.orEmpty()

    private fun num(key: String): Int =
        (data?.get(key) as? JsonPrimitive)?.content?.toDoubleOrNull()?.toInt() ?: 0

    private fun bool(key: String): Boolean =
        (data?.get(key) as? JsonPrimitive)?.content == "true"

    /**
     * What the row reads as.
     *
     * Ported line for line from RexNotification.copy in Models.swift, and
     * deliberately not paraphrased. Every branch below is a bug that was
     * reported and fixed on iOS: rec_tagged wrote rows from 22 August and read
     * "New activity" until 15 October; ticket_reminder did the same from 12
     * October, which meant the one notification whose whole job is naming a
     * time never named it. A fresh implementation would reproduce all of them.
     */
    val copy: String
        get() {
            val who = actor?.displayName?.takeIf { it.isNotBlank() }
                ?: actor?.username?.takeIf { it.isNotBlank() }
                ?: "Someone"
            val preview = str("preview")
            val title = str("title")
            return when (type) {
                "rec_like" -> "$who liked your Rex"
                "rec_saved" -> "$who added your Rex to their collection"
                "rec_comment" -> "$who commented: “$preview”"
                "rec_comment_thread" -> "$who also commented: “$preview”"
                "friend_request" -> "$who sent you a friend request"
                "friend_accepted" -> "$who accepted your friend request"
                "blast_new" -> "$who put out a blast: “$title”"
                "blast_comment" ->
                    if (bool("has_suggestion")) {
                        "$who suggested something on your blast “$title”"
                    } else {
                        "$who replied to your blast: “$preview”"
                    }
                "blast_comment_thread" ->
                    if (title.isEmpty()) {
                        "$who also replied: “$preview”"
                    } else {
                        "$who also replied on “$title”: “$preview”"
                    }
                "rec_tagged" ->
                    if (title.isEmpty()) "$who tagged you in a Rex"
                    else "$who tagged you in their Rex of $title"
                "want_tagged" ->
                    if (title.isEmpty()) "$who wants to try something with you"
                    else "$who wants to try $title with you"
                "mention" -> "$who tagged you: “$preview”"
                "friend_new_rec" -> "$who Rexed ${title.ifEmpty { "something new" }}"
                "ticket_reminder" -> {
                    val what = if (title.isEmpty()) "Tickets" else "Tickets for $title"
                    val lead = num("lead_minutes")
                    when {
                        lead >= 1440 -> "$what go on sale tomorrow"
                        lead >= 60 -> "$what go on sale in ${lead / 60} hours"
                        lead > 0 -> "$what go on sale in $lead minutes"
                        else -> "$what are on sale now"
                    }
                }
                // `who` is deliberately unused: the row has no actor, because
                // a pile of requests has no single author.
                "friend_requests_waiting" -> {
                    val n = num("count")
                    if (n == 1) "You have a friend request waiting"
                    else "You have $n friend requests waiting"
                }
                else -> "New activity"
            }
        }

    /**
     * The recommendation this points at — a *recommendation* id, not an item
     * id. Every trigger that writes entity_type='recommendation' sets
     * entity_id to recommendations.id, so handing it straight to an item
     * screen just 404s, which is what iOS did until it resolved them. Trips
     * are excluded because they open an itinerary, which Android has no
     * screen for.
     */
    val linkedRecommendationId: String?
        get() = if (entityType == "recommendation" && str("category") != "trip") entityId else null
}

// Insert and projection shapes. Separate from the read models because a row
// going in is not the row coming back: the database fills id, created_at and
// the defaults, and sending nulls for them would overwrite what it chose.

@Serializable
internal data class ReadAtPatch(@SerialName("read_at") val readAt: String)

/**
 * The two columns an Android edit may touch. Deliberately not a copy of
 * NewRecommendation: a patch that named photo_urls or tags would send nulls
 * for them and wipe what an iPhone had put there. See updateRecommendation.
 */
@Serializable
internal data class RecommendationPatch(val rating: Int, val note: String? = null)

@Serializable
internal data class RecItemId(val id: String, @SerialName("item_id") val itemId: String)

@Serializable
internal data class NewFriendship(
    @SerialName("requester_id") val requesterId: String,
    @SerialName("addressee_id") val addresseeId: String,
    val status: String = "pending",
)

@Serializable
internal data class FriendshipStatusPatch(val status: String)

// RPC arguments. Named with the leading underscore the functions themselves
// declare — Postgres resolves named arguments by name, so these are not free
// to tidy.

@Serializable
internal data class SearchProfilesArgs(
    @SerialName("_query") val query: String,
    @SerialName("_limit") val limit: Int = 15,
)

@Serializable
internal data class ProfileBasicsArgs(@SerialName("_ids") val ids: List<String>)

@Serializable
internal data class SuggestedFriendsArgs(@SerialName("_limit") val limit: Int = 20)

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

/**
 * Nov 17 — `rating` is Int, and it has to be.
 *
 * recommendations.rating is a smallint. Kotlin serialises a Double 6.0 as
 * "6.0", and Postgres refuses that for an integer column:
 *
 *   400  invalid input syntax for type smallint: "6.0"
 *
 * Which means posting a Rex from Android had never once worked — not since
 * this screen was written on 2 November. It compiled, the screen looked
 * right, and every Post ended in "that didn't save". Swift writes the same
 * value as "6", so iOS never met it, and nobody had run the Android build.
 *
 * The five tier values are whole numbers by design (3, 6, 8, 9, 10), so Int
 * is also the honest type for them. Reads keep Double: FeedRecommendation
 * buckets ranges, and a Double parses a smallint happily.
 */
@Serializable
internal data class NewRecommendation(
    @SerialName("user_id") val userId: String,
    @SerialName("item_id") val itemId: String,
    val rating: Int,
    val note: String? = null,
)

@Serializable
internal data class NewWant(
    @SerialName("user_id") val userId: String,
    @SerialName("item_id") val itemId: String,
)
