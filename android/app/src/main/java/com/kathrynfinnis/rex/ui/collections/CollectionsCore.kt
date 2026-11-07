package com.kathrynfinnis.rex.ui.collections

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
// Aliased because `items` exists in both the grid and the column scope and
// Kotlin will not take two imports of one name. The grid is for collections,
// the column for what is inside one, and both belong in this file.
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.kathrynfinnis.rex.data.FeedRecommendation
import com.kathrynfinnis.rex.data.Rex
import com.kathrynfinnis.rex.data.RexAuth
import com.kathrynfinnis.rex.data.RexList
import com.kathrynfinnis.rex.data.SavedPost
import com.kathrynfinnis.rex.ui.readableFailure
import com.kathrynfinnis.rex.ui.theme.RexColor

/**
 * Collections, and what is inside one — the Android pass at CollectionsView
 * and CollectionDetailView.
 *
 * Deliberately narrower than iOS. CollectionsView draws three horizontal
 * shelves (your wish lists, your collections grouped by topic, friends'
 * collections) because it has the reads for all three; this build has
 * Rex.myCollections() and nothing else, so a single grid of your own
 * collections is the whole truthful screen. Faking the other two shelves from
 * the one query would put headings on screen that can never fill.
 *
 * Written as two composables in one file rather than two files because the
 * detail exists only to be opened from the list and they share the row and
 * tile helpers below; splitting them would mean making those helpers public.
 */

// ──────────────────────────────────────────────────────── collections

@Composable
fun CollectionsList(onOpenCollection: (String, String) -> Unit) {
    var state by remember { mutableStateOf<CollectionsState>(CollectionsState.Loading) }
    // Bumping this re-runs the load. A retry that re-reads the same query is
    // the whole recovery story for a dropped connection, which is what nearly
    // every failure here will be.
    var attempt by remember { mutableStateOf(0) }

    /*
     * Signed out, row-level security returns an empty list rather than an
     * error — the same thing FeedScreen sees. An empty grid and a locked-out
     * grid look identical from here, so the session is what decides which
     * empty state is honest.
     */
    val signedIn by RexAuth.isSignedIn.collectAsState(initial = RexAuth.currentUserId != null)

    LaunchedEffect(attempt) {
        state = CollectionsState.Loading
        state = try {
            CollectionsState.Loaded(Rex.myCollections())
        } catch (e: Exception) {
            CollectionsState.Failed(readableFailure(e))
        }
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp)) {
            Text(
                "Collections",
                style = MaterialTheme.typography.headlineMedium,
                color = RexColor.foreground,
            )
            Text(
                "Organise and explore your recommendations",
                color = RexColor.mutedForeground,
            )
        }

        when (val s = state) {
            CollectionsState.Loading -> LoadingTiles()

            is CollectionsState.Failed -> FailureState(
                headline = "Couldn't load your collections",
                detail = s.message,
                onRetry = { attempt++ },
            )

            is CollectionsState.Loaded -> if (s.lists.isEmpty()) {
                EmptyState(
                    headline = if (signedIn) "No collections yet" else "You're not signed in",
                    body = if (signedIn) {
                        // Honest about where the feature lives: this build has
                        // no way to make a collection, because RexApi has no
                        // write for it.
                        "Collections you make in REX on iPhone will appear here."
                    } else {
                        "Sign in and the collections you've made will be here."
                    },
                )
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(2),
                    contentPadding = PaddingValues(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    gridItems(s.lists, key = { it.id }) { list ->
                        CollectionTile(list) { onOpenCollection(list.id, list.name) }
                    }
                }
            }
        }
    }
}

private sealed interface CollectionsState {
    data object Loading : CollectionsState
    data class Loaded(val lists: List<RexList>) : CollectionsState
    data class Failed(val message: String?) : CollectionsState
}

/**
 * One square tile. Emoji, name, and the topic it is filed under when it has
 * one — topic is on the row already, and a label is the cheap half of what
 * iOS does with it.
 *
 * No item count and no 2x2 thumbnail grid, both of which iOS tiles have. They
 * need the contents of every collection, which is one Rex.collectionItems()
 * call per tile on a screen that currently makes one call in total. The
 * alternative was an N+1 on every open of the tab; a quieter tile lost less.
 */
@Composable
private fun CollectionTile(list: RexList, onOpen: () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = RexColor.card),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.clickable(onClick = onOpen),
    ) {
        Column {
            Box(
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(1.4f)
                    .padding(8.dp),
                contentAlignment = Alignment.Center,
            ) {
                // The same default notebook iOS falls back to in
                // CollectionDetailView's init, so a collection with no emoji
                // is the same thing on both platforms.
                Text(list.emoji?.takeIf { it.isNotBlank() } ?: "📒", fontSize = 34.sp)
            }
            Column(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 12.dp)) {
                Text(
                    list.name,
                    fontWeight = FontWeight.SemiBold,
                    color = RexColor.foreground,
                    maxLines = 2,
                )
                list.topic?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.labelSmall,
                        color = RexColor.mutedForeground,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

// ──────────────────────────────────────────────────────── one collection

/**
 * What is inside one collection.
 *
 * The name arrives from the tile that was tapped rather than being re-fetched,
 * so the title is right on the first frame instead of appearing a moment after
 * the rest. Same trade iOS makes with CollectionRoute.
 */
@Composable
fun CollectionDetail(
    listId: String,
    name: String,
    onBack: () -> Unit,
    onOpenItem: (String) -> Unit,
) {
    var state by remember { mutableStateOf<DetailState>(DetailState.Loading) }
    var attempt by remember { mutableStateOf(0) }

    LaunchedEffect(listId, attempt) {
        state = DetailState.Loading
        state = try {
            DetailState.Loaded(groupRows(Rex.collectionItems(listId)))
        } catch (e: Exception) {
            DetailState.Failed(readableFailure(e))
        }
    }

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp, top = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // A plain Row rather than Material3's TopAppBar: the bar is still
            // experimental in material3 1.3, and nothing else in this build
            // has one to be consistent with yet.
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back to collections",
                    tint = RexColor.primary,
                )
            }
            Column(Modifier.weight(1f)) {
                Text(
                    name,
                    style = MaterialTheme.typography.titleLarge,
                    color = RexColor.foreground,
                    maxLines = 2,
                )
                val loaded = state as? DetailState.Loaded
                if (loaded != null && loaded.contents.kept > 0) {
                    Text(
                        // "Rex" is both singular and plural, as on iOS — it is
                        // the name of the thing, not a count noun.
                        "${loaded.contents.kept} Rex",
                        color = RexColor.mutedForeground,
                    )
                }
            }
        }

        when (val s = state) {
            DetailState.Loading -> LoadingRows()

            is DetailState.Failed -> FailureState(
                headline = "Couldn't load this collection",
                detail = s.message,
                onRetry = { attempt++ },
            )

            is DetailState.Loaded -> {
                val contents = s.contents
                if (contents.kept == 0) {
                    EmptyState(
                        headline = if (contents.skipped > 0) "Nothing left in here" else "Nothing in here yet",
                        body = if (contents.skipped > 0) {
                            "Every Rex that was saved to this collection has since been deleted."
                        } else {
                            "Nothing has been saved into this collection yet."
                        },
                    )
                } else {
                    LazyColumn(
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        contents.sections.forEach { section ->
                            section.heading?.let { heading ->
                                item(key = "heading-$heading") {
                                    Text(
                                        heading,
                                        style = MaterialTheme.typography.titleMedium,
                                        color = RexColor.foreground,
                                        modifier = Modifier.padding(top = 4.dp),
                                    )
                                }
                            }
                            items(section.rows, key = { it.savedPostId }) { row ->
                                SavedRow(row) { onOpenItem(row.rex.itemId) }
                            }
                        }

                        /*
                         * Said rather than hidden. A saved post whose Rex was
                         * deleted leaves a gap between what somebody remembers
                         * putting in a collection and what they can see, and a
                         * silently shorter list reads as a bug in the app. The
                         * count above excludes these.
                         */
                        if (contents.skipped > 0) {
                            item(key = "deleted-note") {
                                Text(
                                    if (contents.skipped == 1) {
                                        "One Rex saved here has since been deleted, so it isn't shown."
                                    } else {
                                        "${contents.skipped} Rex saved here have since been deleted, so they aren't shown."
                                    },
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = RexColor.mutedForeground,
                                    modifier = Modifier.padding(top = 8.dp),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private sealed interface DetailState {
    data object Loading : DetailState
    data class Loaded(val contents: CollectionContents) : DetailState
    data class Failed(val message: String?) : DetailState
}

private data class CollectionContents(
    val sections: List<CollectionSection>,
    /** Rows that can actually be drawn. This is the number shown as the count. */
    val kept: Int,
    /** Rows whose recommendation is gone. Counted, mentioned, never drawn. */
    val skipped: Int,
)

private data class CollectionSection(val heading: String?, val rows: List<SavedRowModel>)

private data class SavedRowModel(
    val savedPostId: String,
    /** The note about *placing* it here, which is not the note about the thing. */
    val placementNote: String?,
    val rex: FeedRecommendation,
)

/**
 * saved_posts into sections, in the order a person arranged them.
 *
 * A row with a null recommendation is a post whose Rex has been deleted —
 * saved_posts.recommendation_id is nullable and the join simply returns
 * nothing. Dropped here, at the point the shape is built, rather than guarded
 * at each use site: one filter cannot be forgotten by the next thing added to
 * the row.
 *
 * Ordering copies the rule in the migration that iOS relies on: a null
 * sort_order sorts last, so something never placed appears at the end rather
 * than in the middle of an order somebody chose. Sections follow the lowest
 * position inside them, and the unheaded rows go last — they are the pile not
 * yet sorted, and putting them above the headings would bury them.
 */
private fun groupRows(posts: List<SavedPost>): CollectionContents {
    /** The row plus the two columns only the grouping needs. */
    data class Placed(val row: SavedRowModel, val heading: String?, val position: Int?)

    val usable = posts.mapNotNull { post ->
        val rex = post.recommendations ?: return@mapNotNull null
        Placed(
            row = SavedRowModel(
                savedPostId = post.id,
                placementNote = post.note?.trim()?.takeIf { it.isNotEmpty() },
                rex = rex,
            ),
            heading = post.section?.trim()?.takeIf { it.isNotEmpty() },
            position = post.sortOrder,
        )
    }

    fun ordered(group: List<Placed>): List<SavedRowModel> = group
        .sortedWith(
            compareBy<Placed>(
                { it.position ?: Int.MAX_VALUE },
                { it.row.rex.items?.title?.lowercase() ?: "" },
            )
        )
        .map { it.row }

    /** A heading with its rows and the earliest position anything in it holds. */
    data class Group(val heading: String?, val rows: List<SavedRowModel>, val first: Int)

    val byHeading = usable.groupBy { it.heading }

    val headed = byHeading
        .filterKeys { it != null }
        .map { (heading, group) ->
            Group(
                heading = heading,
                rows = ordered(group),
                first = group.mapNotNull { it.position }.minOrNull() ?: Int.MAX_VALUE,
            )
        }
        .sortedWith(compareBy<Group>({ it.first }, { it.heading?.lowercase() ?: "" }))
        .map { CollectionSection(it.heading, it.rows) }

    // A collection where nobody has used headings gets no heading row at all,
    // rather than one reading "No heading" above everything.
    val unheaded = byHeading[null]
        ?.let { listOf(CollectionSection(null, ordered(it))) }
        ?: emptyList()

    return CollectionContents(
        sections = headed + unheaded,
        kept = usable.size,
        skipped = posts.size - usable.size,
    )
}

/**
 * One saved Rex. The item, what was said about it, and who said it — the same
 * four things FeedScreen's card leads with, plus the note about why it is in
 * this collection, which only exists here.
 */
@Composable
private fun SavedRow(row: SavedRowModel, onOpen: () -> Unit) {
    val rex = row.rex
    Card(
        colors = CardDefaults.cardColors(containerColor = RexColor.card),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen),
    ) {
        Row(Modifier.padding(12.dp)) {
            val image = rex.items?.imageUrl ?: rex.photoUrls?.firstOrNull()
            if (image != null) {
                AsyncImage(
                    model = image,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(56.dp).clip(RoundedCornerShape(8.dp)),
                )
            } else {
                // A tinted square rather than nothing, so a list of rows with
                // and without artwork keeps one left edge. Nothing invented
                // goes inside it.
                Box(
                    Modifier
                        .size(56.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(RexColor.badgeBackground)
                )
            }
            Spacer(Modifier.size(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    rex.items?.title ?: "Untitled",
                    fontWeight = FontWeight.SemiBold,
                    color = RexColor.foreground,
                )
                rex.items?.subtitle?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, color = RexColor.mutedForeground, maxLines = 1)
                }
                rex.note?.takeIf { it.isNotEmpty() }?.let {
                    Spacer(Modifier.height(4.dp))
                    Text(it, color = RexColor.foreground, maxLines = 3)
                }
                row.placementNote?.let {
                    Spacer(Modifier.height(4.dp))
                    // Set apart from the Rex's own note on purpose: this one
                    // is somebody's instruction to themselves about the list,
                    // not an opinion about the thing.
                    Text(
                        it,
                        color = RexColor.mutedForeground,
                        fontStyle = FontStyle.Italic,
                        maxLines = 2,
                    )
                }
                Spacer(Modifier.height(6.dp))
                Row {
                    Text(
                        rex.profiles?.displayName ?: rex.profiles?.username ?: "Someone",
                        color = RexColor.mutedForeground,
                    )
                    rex.tier?.let { Text(" · $it", color = RexColor.gold) }
                }
            }
        }
    }
}

// ──────────────────────────────────────────────────────── shared states

/**
 * Grey blocks in the shape of what is coming, as iOS does in both of these
 * views, rather than FeedScreen's centred spinner. A spinner says only "wait";
 * blocks the size of the tiles say what is about to be there, and the screen
 * does not jump when it arrives.
 */
@Composable
private fun LoadingTiles() {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        gridItems(List(4) { it }) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    .clip(RoundedCornerShape(16.dp))
                    .background(RexColor.divider)
            )
        }
    }
}

@Composable
private fun LoadingRows() {
    Column(
        Modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        repeat(3) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(88.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(RexColor.divider)
            )
        }
    }
}

/**
 * A failure says three things: that it failed, what the database actually
 * said, and the one thing worth trying. The underlying message is kept rather
 * than swallowed — almost every failure here is the network, and "Unable to
 * resolve host" is more use to somebody on a train than "something went wrong".
 */
@Composable
private fun FailureState(headline: String, detail: String?, onRetry: () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp),
        ) {
            Text(headline, fontWeight = FontWeight.SemiBold, color = RexColor.destructive)
            Spacer(Modifier.height(4.dp))
            Text(
                detail?.takeIf { it.isNotBlank() } ?: "Check your connection and try again.",
                color = RexColor.mutedForeground,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            TextButton(onClick = onRetry) {
                Text("Try again", color = RexColor.primary, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun EmptyState(headline: String, body: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp),
        ) {
            Text(headline, fontWeight = FontWeight.SemiBold, color = RexColor.foreground)
            Spacer(Modifier.height(4.dp))
            Text(body, color = RexColor.mutedForeground, textAlign = TextAlign.Center)
        }
    }
}
