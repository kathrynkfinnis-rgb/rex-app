package com.kathrynfinnis.rex.ui.item

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.kathrynfinnis.rex.data.FeedRecommendation
import com.kathrynfinnis.rex.data.Rex
import com.kathrynfinnis.rex.data.RexAuth
import com.kathrynfinnis.rex.data.RexItem
import com.kathrynfinnis.rex.ui.readableFailure
import com.kathrynfinnis.rex.ui.theme.RexColor
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * One thing, and everything anybody has said about it. The Android answer to
 * ItemDetailView.swift, which is 2,700 lines — this is the spine of it: the
 * header, the takes, and the want-to-try toggle. What is missing is missing
 * because the Android data layer has no query for it yet (comments, likes,
 * who else only means to go, the Google place details, other branches of a
 * chain, "more by this author"), not because it was judged unimportant.
 *
 * The three rules this screen borrows from iOS are the ones that are invisible
 * until they bite, so they are ported rather than left for later: a row with
 * no opinion on it is not a take, one person gets one take, and a want toggle
 * moves before the network does. All three are below, with their reasons.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ItemDetailScreen(itemId: String, onBack: () -> Unit) {
    var state by remember(itemId) { mutableStateOf<ItemState>(ItemState.Loading) }
    var wanted by remember(itemId) { mutableStateOf<WantState>(WantState.Unknown) }
    var wantError by remember(itemId) { mutableStateOf<String?>(null) }
    // A counter rather than a Unit key, so the retry button can ask for the
    // same itemId a second time.
    var attempt by remember(itemId) { mutableStateOf(0) }

    // Reactive rather than a one-off read of currentUserId: signing in from
    // elsewhere in the app has to make the toggle appear here, and the page
    // underneath is reloaded by the key below when it does.
    val signedIn by RexAuth.isSignedIn.collectAsState(initial = RexAuth.currentUserId != null)
    val scope = rememberCoroutineScope()

    LaunchedEffect(itemId, attempt, signedIn) {
        state = ItemState.Loading
        wanted = WantState.Unknown
        wantError = null
        state = try {
            // Together, not one after the other: the item row and its takes
            // are independent reads and the header should not wait on a list
            // it does not depend on. iOS does the same with a task group.
            //
            // The takes read is the one allowed to fail the page. The item
            // read is caught, because recommendationsFor joins items!inner and
            // so carries a copy of the header anyway — losing items while the
            // takes arrive should cost nothing visible. It only becomes an
            // error when there is no take to fall back on.
            coroutineScope {
                val item = async { runCatching { Rex.item(itemId) } }
                val takes = async { Rex.recommendationsFor(itemId) }
                val said = takes.await()
                val header = item.await()
                header.exceptionOrNull()?.let { if (said.isEmpty()) throw it }
                ItemState.Loaded(header.getOrNull(), said)
            }
        } catch (e: Exception) {
            ItemState.Failed(readableFailure(e))
        }

        // Separately, and deliberately not inside the block above: whether
        // you have this on your want-to-try list is a detail of one control,
        // and losing it should cost you that control rather than the page. On
        // a failure the toggle stays out of the way instead of guessing.
        if (signedIn) {
            wanted = try {
                WantState.Known(Rex.myWants().any { it.itemId == itemId })
            } catch (e: Exception) {
                WantState.Unavailable
            }
        }
    }

    Scaffold(
        containerColor = RexColor.background,
        topBar = {
            TopAppBar(
                title = {
                    // The item's own title, once it is known. Empty until
                    // then rather than a placeholder that is replaced a
                    // moment later — iOS makes the same choice, and has a
                    // showsTitle flag for the map sheet where the name is
                    // already the first thing in the card. Nothing on Android
                    // presents this as a sheet yet, so there is no flag here.
                    val heading = (state as? ItemState.Loaded)?.subject?.title
                    if (heading != null) {
                        Text(
                            heading,
                            color = RexColor.foreground,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = RexColor.foreground,
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = RexColor.background),
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (val s = state) {
                ItemState.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                    CircularProgressIndicator(color = RexColor.primary)
                }

                is ItemState.Failed -> Message(
                    heading = "Couldn't load this",
                    body = s.message
                        ?: "Something went wrong between here and Rex. Check your connection and try again.",
                    actionLabel = "Try again",
                    onAction = { attempt++ },
                )

                is ItemState.Loaded -> {
                    val subject = s.subject
                    if (subject == null) {
                        // Nothing in items and nothing in recommendations.
                        // Either it was removed or the link that brought you
                        // here is stale; both read the same from here, so say
                        // what is true rather than picking one.
                        Message(
                            heading = "This isn't here any more",
                            body = "We couldn't find anything behind this link. It may have been removed.",
                            actionLabel = "Go back",
                            onAction = onBack,
                        )
                    } else {
                        Detail(
                            subject = subject,
                            takes = s.takes,
                            wanted = wanted,
                            wantError = wantError,
                            signedIn = signedIn,
                            onToggleWant = {
                                val known = wanted as? WantState.Known
                                if (known != null) {
                                    val next = !known.value
                                    // Optimistic, as on iOS: the control
                                    // answers on the tap and the write
                                    // catches up. Put back on a throw, with a
                                    // line saying so — iOS reverts silently,
                                    // which leaves a tap that visibly did
                                    // nothing and no reason why.
                                    wanted = WantState.Known(next)
                                    wantError = null
                                    scope.launch {
                                        try {
                                            if (next) Rex.createWant(itemId) else Rex.removeWant(itemId)
                                        } catch (e: Exception) {
                                            wanted = WantState.Known(!next)
                                            wantError = if (next) {
                                                "Couldn't add this to your want-to-try list. Try again."
                                            } else {
                                                "Couldn't take this off your want-to-try list. Try again."
                                            }
                                        }
                                    }
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

private sealed interface ItemState {
    data object Loading : ItemState
    data class Failed(val message: String?) : ItemState
    data class Loaded(val item: RexItem?, val takes: List<FeedRecommendation>) : ItemState {
        /**
         * The item row if we got one, otherwise the copy embedded in a take.
         * Null only when neither exists, which is a thing that is genuinely
         * not there rather than a thing that failed to load.
         */
        val subject: RexItem? get() = item ?: takes.firstNotNullOfOrNull { it.items }
    }
}

/**
 * Whether this is on your want-to-try list. Unknown and Unavailable are not
 * the same thing: one is "we are still asking", the other is "we asked and
 * could not find out", and a toggle drawn in the second case would be a
 * switch that lies about its starting position.
 */
private sealed interface WantState {
    data object Unknown : WantState
    data object Unavailable : WantState
    data class Known(val value: Boolean) : WantState
}

@Composable
private fun Detail(
    subject: RexItem,
    takes: List<FeedRecommendation>,
    wanted: WantState,
    wantError: String?,
    signedIn: Boolean,
    onToggleWant: () -> Unit,
) {
    val opinions = remember(takes) { onePerPerson(takes.filter(::carriesAnOpinion)) }
    val me = RexAuth.currentUserId

    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item("header") { Header(subject) }

        item("want") {
            WantToTry(
                wanted = wanted,
                error = wantError,
                signedIn = signedIn,
                onToggle = onToggleWant,
            )
        }

        item("takes-heading") {
            Column {
                Spacer(Modifier.height(4.dp))
                Text(
                    // "Rex'd by" on iOS, which only works above a row of
                    // faces. Above a column of written takes it reads as a
                    // label with no sentence, so this says what the section
                    // is instead.
                    if (opinions.isEmpty()) "Takes" else "What people say",
                    fontWeight = FontWeight.SemiBold,
                    color = RexColor.foreground,
                    style = MaterialTheme.typography.titleMedium,
                )
            }
        }

        if (opinions.isEmpty()) {
            item("takes-empty") {
                Text(
                    // Not an error, and not nothing: an item with no takes is
                    // ordinary — it arrives the moment somebody adds it to a
                    // list or a trip. Posting the first one is done from
                    // elsewhere in the app, so this does not offer a button
                    // it cannot wire up.
                    "Nobody has Rexed this yet.",
                    color = RexColor.mutedForeground,
                )
            }
        } else {
            items(opinions, key = { it.id }) { take ->
                Take(take = take, isMine = take.userId == me)
            }
        }
    }
}

@Composable
private fun Header(subject: RexItem) {
    Card(
        colors = CardDefaults.cardColors(containerColor = RexColor.card),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column {
            subject.imageUrl?.takeIf { it.isNotBlank() }?.let { url ->
                // 3:2 and cropped. A film poster and a restaurant photo have
                // nothing in common in aspect, and the alternative — letting
                // each image set the height — makes the page jump as they
                // load. iOS crops to a fixed banner for the same reason.
                AsyncImage(
                    model = url,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(3f / 2f),
                )
            }
            Column(Modifier.padding(16.dp)) {
                Text(
                    subject.title,
                    fontWeight = FontWeight.SemiBold,
                    color = RexColor.foreground,
                    style = MaterialTheme.typography.titleLarge,
                )
                subject.subtitle?.takeIf { it.isNotBlank() }?.let {
                    Spacer(Modifier.height(2.dp))
                    Text(it, color = RexColor.mutedForeground)
                }

                // Category and genre on one line. Two badges would imply the
                // genre stands on its own, and it never does — "Thriller" is
                // only meaningful next to "Film".
                val category = listOfNotNull(
                    categoryLabel(subject.type),
                    subject.genre?.takeIf { it.isNotBlank() },
                ).joinToString(" · ")
                if (category.isNotEmpty()) {
                    Spacer(Modifier.height(10.dp))
                    Box(
                        Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(RexColor.badgeBackground)
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Text(
                            category,
                            color = RexColor.badgeForeground,
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                }

                // Only for places. A film's address column is empty, and a
                // festival's is the venue — showing it under anything else
                // would be showing whatever happens to be in the column.
                if (subject.type == "place") {
                    subject.address?.takeIf { it.isNotBlank() }?.let {
                        Spacer(Modifier.height(10.dp))
                        Text(it, color = RexColor.mutedForeground)
                    }
                }
            }
        }
    }
}

@Composable
private fun WantToTry(
    wanted: WantState,
    error: String?,
    signedIn: Boolean,
    onToggle: () -> Unit,
) {
    when {
        // Signed out, RLS returns an empty want list and createWant would
        // throw. A disabled toggle would be a dead control with no
        // explanation, so this says what is needed instead.
        !signedIn -> Text(
            "Sign in to keep a want-to-try list.",
            color = RexColor.mutedForeground,
        )

        wanted is WantState.Unknown -> Text(
            "Checking your want-to-try list…",
            color = RexColor.placeholder,
        )

        wanted is WantState.Unavailable -> Text(
            "We couldn't check your want-to-try list just now, so adding this is off until the page is reloaded.",
            color = RexColor.mutedForeground,
        )

        wanted is WantState.Known -> Column {
            // Filled once it is on the list, outlined when it is not: the
            // same pair of states the iOS button uses, and the same words, so
            // the two apps are describing one list rather than two features.
            val on = wanted.value
            if (on) {
                Button(
                    onClick = onToggle,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = RexColor.primary,
                        contentColor = RexColor.primaryForeground,
                    ),
                ) {
                    Icon(Icons.Filled.Bookmark, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("On your want-to-try list")
                }
            } else {
                OutlinedButton(
                    onClick = onToggle,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = RexColor.primary),
                ) {
                    Icon(Icons.Outlined.Bookmark, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Want to try")
                }
            }
            error?.let {
                Spacer(Modifier.height(6.dp))
                Text(it, color = RexColor.destructive)
            }
        }
    }
}

@Composable
private fun Take(take: FeedRecommendation, isMine: Boolean) {
    Card(
        colors = CardDefaults.cardColors(containerColor = RexColor.card),
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                take.profiles?.avatarUrl?.takeIf { it.isNotBlank() }?.let { url ->
                    AsyncImage(
                        model = url,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.size(28.dp).clip(RoundedCornerShape(14.dp)),
                    )
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    // "You" for your own, because a page of takes with your
                    // own username in the middle of it reads as somebody
                    // else. The profiles join can come back null when RLS
                    // hides the person but not the row; "Someone" is then the
                    // honest word, and matches what the feed card says.
                    when {
                        isMine -> "You"
                        else -> take.profiles?.displayName
                            ?: take.profiles?.username
                            ?: "Someone"
                    },
                    fontWeight = FontWeight.SemiBold,
                    color = RexColor.foreground,
                )
                take.tier?.let {
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "· $it",
                        // "Do not Rex" is the one tier that is not praise, so
                        // it does not get the gold the other four share.
                        color = if (it == "Do not Rex") RexColor.destructive else RexColor.gold,
                        fontWeight = FontWeight.Medium,
                    )
                }
            }

            // A take with a rating and no note is complete — the five-tier
            // scale is itself the opinion, and iOS only shows the box once
            // you have picked a face. So no "no comment" line here.
            take.note?.takeIf { it.isNotBlank() }?.let {
                Spacer(Modifier.height(8.dp))
                HorizontalDivider(color = RexColor.divider)
                Spacer(Modifier.height(8.dp))
                Text(it, color = RexColor.foreground)
            }

            // Their photos, if they added any. The item's own picture is in
            // the header; these are what the person themselves took, which is
            // the bit of a take worth seeing at this size. Only the first,
            // until there is a carousel to open them in — iOS has
            // PhotoCarouselView and Android has nothing to push to yet.
            take.photoUrls?.firstOrNull()?.takeIf { it.isNotBlank() }?.let { url ->
                Spacer(Modifier.height(8.dp))
                AsyncImage(
                    model = url,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f)
                        .clip(RoundedCornerShape(10.dp)),
                )
            }
        }
    }
}

/** An empty or failed state, written as a sentence with a way out of it. */
@Composable
private fun Message(
    heading: String,
    body: String,
    actionLabel: String,
    onAction: () -> Unit,
) {
    Box(Modifier.fillMaxSize(), Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp),
        ) {
            Text(heading, fontWeight = FontWeight.SemiBold, color = RexColor.foreground)
            Spacer(Modifier.height(6.dp))
            Text(body, color = RexColor.mutedForeground, textAlign = TextAlign.Center)
            Spacer(Modifier.height(16.dp))
            OutlinedButton(
                onClick = onAction,
                colors = ButtonDefaults.outlinedButtonColors(contentColor = RexColor.primary),
            ) { Text(actionLabel) }
        }
    }
}

/**
 * The category names from RexCategory in iOS Theme.swift, verbatim.
 *
 * "Movie" over the British "Film" is a deliberate exception to the house rule
 * on copy: these ten words are the shared vocabulary of the category picker,
 * the badges and the search, and one of them differing by platform is a
 * product inconsistency rather than a localisation. If it changes it should
 * change in both places at once.
 *
 * An unknown type falls through to no badge rather than to the raw column
 * value — "other_thing" on screen is worse than nothing there.
 */
private fun categoryLabel(type: String): String? = when (type) {
    "place" -> "Place"
    "trip" -> "Trip"
    "book" -> "Book"
    "movie" -> "Movie"
    "tv" -> "TV"
    "podcast" -> "Podcast"
    "recipe" -> "Recipe"
    "event" -> "Event"
    "other" -> "Other"
    "list" -> "List"
    else -> null
}

/**
 * Ported from ItemDetailView.carriesAnOpinion (iOS, 18 October).
 *
 * Adding something to a list or a trip writes a recommendation row to hang
 * the entry on: rating 0, no note. It is structure, not a take, and iOS spent
 * two bug reports on it — "this should be a want to try for Phoebe", where a
 * film she had only filed appeared under her name as a Rex, and the 15 October
 * report of trip stops showing as separate reviews.
 *
 * Decided on what the row carries rather than on trip_id or list_id, because a
 * stop or a filed item that does have a rating or a note is a real take and
 * still counts.
 */
private fun carriesAnOpinion(take: FeedRecommendation): Boolean =
    take.rating > 0 || !take.note.isNullOrEmpty()

/**
 * Ported from ItemDetailView.onePerPerson (iOS, 16 October — "Phoebe shouldn't
 * be able to Rex the same place twice").
 *
 * She hadn't. Adding a place you have already Rexed to a trip writes a second
 * row for it, which is deliberate and is what lets a trip revisit somewhere.
 * This page asks for every row on the item, so without this one person shows
 * up twice.
 *
 * One row per person, the fullest one winning — a rating counts for more than
 * a note, because a tier with no words still says something and words with no
 * tier are a stop's label. Order is the one the query returned, newest first.
 */
private fun onePerPerson(takes: List<FeedRecommendation>): List<FeedRecommendation> {
    fun weight(take: FeedRecommendation): Int =
        (if (take.rating > 0) 2 else 0) + (if (take.note.isNullOrEmpty()) 0 else 1)

    val best = LinkedHashMap<String, FeedRecommendation>()
    for (take in takes) {
        val held = best[take.userId]
        if (held == null || weight(take) > weight(held)) best[take.userId] = take
    }
    val seen = HashSet<String>()
    return takes.mapNotNull { take ->
        if (!seen.add(take.userId)) null else best[take.userId]
    }
}
