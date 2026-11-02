package com.kathrynfinnis.rex.ui.feed

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.kathrynfinnis.rex.data.FeedRecommendation
import com.kathrynfinnis.rex.data.Rex
import com.kathrynfinnis.rex.data.RexAuth
import com.kathrynfinnis.rex.ui.theme.RexColor
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The feed, second pass. FeedScreen.kt stays where it is — it was written to
 * prove the Supabase chain worked and it did its job — and this is the version
 * meant to be looked at: a card with the rating, the category and the time on
 * it, and states that explain themselves.
 *
 * It is a list, not a screen. FeedScreen owns a Scaffold slot already and the
 * header, the add button and the sign-in gate are all somebody else's work in
 * this build; taking a callback and nothing else means whoever wires the
 * navigation up by hand afterwards decides where it sits.
 */
@Composable
fun FeedList(onOpenItem: (String) -> Unit) {
    var load by remember { mutableStateOf<FeedLoad>(FeedLoad.Loading) }
    // Bumped by "Try again". A counter rather than a boolean because two
    // consecutive failures have to retrigger the effect, and a flag flipped
    // back to the same value does not.
    var attempt by remember { mutableIntStateOf(0) }

    // Signing in changes what the database will return — RLS keys off
    // auth.uid() — so the session is a dependency of this read, not just
    // something the empty state mentions. Without it, somebody who signs in
    // behind this list keeps staring at "nothing here yet" until they
    // navigate away and back.
    val signedIn by RexAuth.isSignedIn.collectAsState(initial = RexAuth.currentUserId != null)
    val resolving by RexAuth.isResolving.collectAsState(initial = false)

    LaunchedEffect(attempt, signedIn) {
        load = FeedLoad.Loading
        load = try {
            FeedLoad.Loaded(Rex.feed())
        } catch (e: Exception) {
            FeedLoad.Failed(e.message)
        }
    }

    when (val state = load) {
        FeedLoad.Loading -> LoadingFeed()

        is FeedLoad.Failed -> FeedMessage(
            headline = "The feed didn't load",
            body = buildString {
                append("Something went wrong between here and REX. ")
                append("Check your connection and try again.")
                state.detail?.takeIf { it.isNotBlank() }?.let { append("\n\n").append(it) }
            },
            onRetry = { attempt++ },
        )

        is FeedLoad.Loaded -> when {
            state.rex.isNotEmpty() -> LazyColumn(
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                // Keyed so a refresh reuses the rows it already has instead of
                // rebuilding every card and restarting every image load.
                items(state.rex, key = { it.id }) { rec ->
                    RecommendationCard(rec = rec, onOpenItem = onOpenItem)
                }
            }

            // An empty feed has two quite different causes and one of them is
            // not a problem at all. Signed out, RLS correctly returns nothing;
            // telling that person the feed is empty would be a lie about the
            // app rather than a fact about them.
            !signedIn && !resolving -> FeedMessage(
                headline = "Sign in to see your feed",
                body = "REX shows you what the people you follow have been to, " +
                    "watched and read. Signing in is what fills it.",
            )

            else -> FeedMessage(
                headline = "Nothing here yet",
                body = "Your feed fills up as the people you follow post. " +
                    "Add a Rex of your own, or find people you know in Explore.",
                onRetry = { attempt++ },
            )
        }
    }
}

private sealed interface FeedLoad {
    data object Loading : FeedLoad
    data class Loaded(val rex: List<FeedRecommendation>) : FeedLoad
    data class Failed(val detail: String?) : FeedLoad
}

/**
 * One Rex. A thumbnail beside the words rather than the full-width photo card
 * iOS uses: the iOS feed is a single column on a phone-width screen with one
 * card roughly per screenful, and a tall card with a hero image reads as one
 * post at a time. This list is the first thing the Android app shows and
 * scanning five of them matters more here than dwelling on one, so the image
 * is a 76dp square. If the hero treatment comes back it is this function and
 * nothing else that changes.
 */
@Composable
private fun RecommendationCard(rec: FeedRecommendation, onOpenItem: (String) -> Unit) {
    val item = rec.items
    // Same precedence as FeedScreen's first pass: the item's own artwork
    // first, the poster's photo second. The item image is consistent across
    // everyone who rexed the same thing, which is what makes a scroll of
    // cards look like one list rather than someone's camera roll.
    val image = item?.imageUrl ?: rec.photoUrls?.firstOrNull()

    Card(
        colors = CardDefaults.cardColors(containerColor = RexColor.card),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOpenItem(rec.itemId) },
    ) {
        Row(Modifier.padding(12.dp)) {
            Thumbnail(url = image, title = item?.title)
            Spacer(Modifier.width(12.dp))

            Column(Modifier.weight(1f)) {
                Text(
                    // The row is only in the feed because an item joined to
                    // it (items!inner), so a missing title means a title that
                    // did not decode rather than an item that isn't there.
                    text = item?.title?.takeIf { it.isNotBlank() } ?: "Untitled",
                    style = MaterialTheme.typography.titleMedium,
                    color = RexColor.foreground,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )

                // Genre rides on the subtitle line rather than getting a chip
                // of its own. Two chips side by side read as two equal facts,
                // and "Thriller" is a detail about the thing while "Film" is
                // what kind of thing it is — only the second earns the chip.
                val secondary = listOfNotNull(
                    item?.subtitle?.takeIf { it.isNotBlank() },
                    item?.genre?.takeIf { it.isNotBlank() },
                ).joinToString(" · ")
                if (secondary.isNotEmpty()) {
                    Text(
                        text = secondary,
                        style = MaterialTheme.typography.bodyMedium,
                        color = RexColor.mutedForeground,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                Spacer(Modifier.height(8.dp))

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    item?.type?.takeIf { it.isNotBlank() }?.let { Chip(label = typeLabel(it)) }
                    rec.tier?.let { TierBadge(it) }
                }

                rec.note?.trim()?.takeIf { it.isNotEmpty() }?.let { note ->
                    Spacer(Modifier.height(8.dp))
                    Text(
                        // Curly quotes, and the quote marks are the whole
                        // reason this reads as somebody's words rather than
                        // app copy. Three lines then ellipsis: the full note
                        // belongs on the item screen, where there is room for
                        // it and for everyone else's.
                        text = "“$note”",
                        style = MaterialTheme.typography.bodyLarge,
                        fontStyle = FontStyle.Italic,
                        color = RexColor.foreground,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                Spacer(Modifier.height(8.dp))

                Text(
                    // Username, not display name: a feed is people you know
                    // and @names are what people recognise each other by in
                    // REX. Display name is the fallback, and "Someone" only
                    // when the profile join came back empty — which happens
                    // for a deleted account, and saying "Someone" is better
                    // than dropping the line and leaving an orphan note.
                    text = byline(rec),
                    style = MaterialTheme.typography.bodyMedium,
                    color = RexColor.mutedForeground,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/** The @name and the when, joined only if we have both. */
private fun byline(rec: FeedRecommendation): String {
    val who = rec.profiles?.username?.takeIf { it.isNotBlank() }?.let { "@$it" }
        ?: rec.profiles?.displayName?.takeIf { it.isNotBlank() }
        ?: "Someone"
    val when_ = relativeTime(rec.createdAt)
    return if (when_ == null) who else "$who · $when_"
}

@Composable
private fun Thumbnail(url: String?, title: String?) {
    val shape = RoundedCornerShape(10.dp)
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(76.dp)
            .clip(shape)
            // The placeholder is a tinted square, so a card with no artwork
            // is the same shape as a card with artwork and the list does not
            // jump about as images arrive.
            .background(RexColor.badgeBackground)
            .border(1.dp, RexColor.border, shape),
    ) {
        if (url != null) {
            AsyncImage(
                model = url,
                contentDescription = null, // The title beside it already says what this is.
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Text(
                text = title?.trim()?.firstOrNull()?.uppercase() ?: "·",
                style = MaterialTheme.typography.titleLarge,
                color = RexColor.badgeForeground,
            )
        }
    }
}

@Composable
private fun Chip(label: String) {
    Text(
        text = label,
        style = MaterialTheme.typography.labelSmall,
        color = RexColor.badgeForeground,
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(RexColor.badgeBackground)
            .padding(horizontal = 8.dp, vertical = 3.dp),
    )
}

@Composable
private fun TierBadge(tier: String) {
    Text(
        text = tier,
        style = MaterialTheme.typography.labelSmall,
        color = RexColor.primaryForeground,
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(tierColour(tier))
            .padding(horizontal = 8.dp, vertical = 3.dp),
    )
}

/**
 * Filled badges rather than the numeric score. The five tiers are the scale
 * REX actually talks in — "Obsessed" is the word people use — and a 9.4 beside
 * an 8.8 invites a comparison the scale was designed to avoid. The number is
 * still on the item screen for anyone who wants it.
 *
 * The colours are from RexColor and chosen for the same ordering iOS reads
 * top to bottom: gold is the top of the scale, destructive the bottom.
 */
private fun tierColour(tier: String): Color = when (tier) {
    "Obsessed" -> RexColor.gold
    "Loved" -> RexColor.primary
    "Rex" -> RexColor.moss
    "Meh" -> RexColor.mutedForeground
    "Do not Rex" -> RexColor.destructive
    else -> RexColor.mutedForeground
}

/**
 * "Film" from "film". Capitalising the database's own word rather than mapping
 * each type to a nicer label: the list of types lives in the schema and in the
 * iOS add flow, and a lookup table here would quietly print nothing — or the
 * wrong thing — the day somebody adds a sixth type. Two letters or fewer are
 * uppercased, which is what makes "tv" read as "TV".
 */
private fun typeLabel(type: String): String {
    val t = type.trim()
    return if (t.length <= 2) t.uppercase(Locale.UK)
    else t.replaceFirstChar { it.titlecase(Locale.UK) }
}

private val dayMonth = DateTimeFormatter.ofPattern("d MMM", Locale.UK)
private val dayMonthYear = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.UK)

/**
 * "2h ago", "3d ago", then an actual date past a week — a feed is about what
 * is recent, and "47d ago" is arithmetic nobody asked for.
 *
 * created_at comes back as PostgREST writes it, which is an offset timestamp
 * most of the time and a bare local one when the column is `timestamp`
 * without a zone. Both are parsed, and anything else returns null so the
 * byline loses its time rather than printing a raw database string at
 * somebody. Null is also what a clock-skewed future timestamp avoids: ahead
 * of now counts as "just now" rather than a negative age.
 */
private fun relativeTime(iso: String, now: Instant = Instant.now()): String? {
    val then = runCatching { OffsetDateTime.parse(iso).toInstant() }
        .recoverCatching { LocalDateTime.parse(iso).toInstant(ZoneOffset.UTC) }
        .getOrNull() ?: return null

    val seconds = (now.epochSecond - then.epochSecond).coerceAtLeast(0)
    val minutes = seconds / 60
    val hours = minutes / 60
    val days = hours / 24

    return when {
        minutes < 1 -> "just now"
        minutes < 60 -> "${minutes}m ago"
        hours < 24 -> "${hours}h ago"
        days < 7 -> "${days}d ago"
        else -> {
            val local = then.atZone(ZoneId.systemDefault())
            val formatter = if (local.year == now.atZone(ZoneId.systemDefault()).year) {
                dayMonth
            } else {
                dayMonthYear
            }
            local.format(formatter)
        }
    }
}

/**
 * Placeholder cards, not a spinner. The feed is the first thing on screen at
 * launch and a centred spinner tells somebody nothing about what is coming;
 * three card-shaped blocks say "a list of things, shortly" and the list does
 * not jump when they are replaced.
 *
 * Static on purpose — a shimmer animation is the obvious next step and it is
 * also an animation running during the slowest moment of the launch.
 */
@Composable
private fun LoadingFeed() {
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
    ) {
        repeat(3) {
            Card(
                colors = CardDefaults.cardColors(containerColor = RexColor.card),
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(Modifier.padding(12.dp)) {
                    Box(
                        Modifier
                            .size(76.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(RexColor.divider)
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        PlaceholderBar(widthFraction = 0.7f, height = 16.dp)
                        Spacer(Modifier.height(8.dp))
                        PlaceholderBar(widthFraction = 0.45f, height = 12.dp)
                        Spacer(Modifier.height(12.dp))
                        PlaceholderBar(widthFraction = 0.9f, height = 12.dp)
                    }
                }
            }
        }
    }
}

@Composable
private fun PlaceholderBar(widthFraction: Float, height: Dp) {
    Box(
        Modifier
            .fillMaxWidth(widthFraction)
            .height(height)
            .clip(RoundedCornerShape(4.dp))
            .background(RexColor.divider)
    )
}

/**
 * Every non-happy path, written the same way: what happened, then what the
 * person can do about it. The retry is optional because one of these states —
 * being signed out — is not something retrying fixes, and a button that does
 * nothing is worse than no button.
 */
@Composable
private fun FeedMessage(
    headline: String,
    body: String,
    onRetry: (() -> Unit)? = null,
) {
    Box(Modifier.fillMaxSize(), Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp),
        ) {
            Text(
                text = headline,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = RexColor.foreground,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = body,
                style = MaterialTheme.typography.bodyLarge,
                color = RexColor.mutedForeground,
                textAlign = TextAlign.Center,
            )
            if (onRetry != null) {
                Spacer(Modifier.height(20.dp))
                Button(
                    onClick = onRetry,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = RexColor.primary,
                        contentColor = RexColor.primaryForeground,
                    ),
                ) {
                    Text("Try again")
                }
            }
        }
    }
}
