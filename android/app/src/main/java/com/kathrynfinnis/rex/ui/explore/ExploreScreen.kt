package com.kathrynfinnis.rex.ui.explore

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import com.kathrynfinnis.rex.data.FeedRecommendation
import com.kathrynfinnis.rex.data.Rex
import com.kathrynfinnis.rex.ui.categoryPlural
import com.kathrynfinnis.rex.ui.exploreCategories
import com.kathrynfinnis.rex.ui.readableFailure
import com.kathrynfinnis.rex.ui.theme.RexColor

/**
 * Nov 17 — Explore, which until today rendered the word "Explore" in the
 * middle of an empty screen. One of the two tabs out of four that did.
 *
 * Much smaller than ExploreView.swift, which is 842 lines across nine calls:
 * editorial collections, Rexperts shelves, a trending RPC, friends'
 * collections, an Ask Rex bar and an admin tool. None of those exist on
 * Android, and several are whole features rather than a screen.
 *
 * What it does port is the part that makes Explore worth opening — what your
 * friends have Rex'd most, by category — and that needs no new API surface at
 * all, because iOS derives the same shelves client-side from the feed it has
 * already read. Same grouping here, over Rex.feed().
 *
 * Three rules copied deliberately, each of them a bug iOS fixed in public:
 *
 *  - One tile per thing. The shelf groups by item_id and counts. Oct 12:
 *    "this is duplicative in Explore — it should only come up once and then
 *    say Rex'd by two people." MobLand appeared twice on the TV shelf because
 *    two people had Rex'd it, and that shelf was built one tile per row.
 *  - Everything qualifies, ordered by how many people agree. Oct 8: "can we
 *    populate these with stuff even if not Rex'd that much." Requiring two
 *    people is a fair definition of "most Rex'd" and a poor one for an app
 *    this size — the recipes shelf held one recipe.
 *  - Twenty to a shelf. Oct 3: ten "reads as though the app has nothing
 *    more".
 */
@Composable
fun ExploreScreen(onOpenItem: (String) -> Unit) {
    var state by remember { mutableStateOf<ExploreState>(ExploreState.Loading) }
    var attempt by remember { mutableIntStateOf(0) }
    var filter by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(attempt) {
        state = ExploreState.Loading
        state = runCatching {
            // A bigger slice than the feed tab takes: shelves are built by
            // grouping, so a thin read makes thin shelves. PostgREST caps at
            // 1,000 whatever is asked for.
            ExploreState.Loaded(Rex.feed(limit = 300))
        }.getOrElse { ExploreState.Failed(readableFailure(it)) }
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp)) {
            Text(
                "Explore",
                style = MaterialTheme.typography.headlineMedium,
                color = RexColor.foreground,
            )
            Text(
                "What your friends have Rex'd most",
                color = RexColor.mutedForeground,
            )
        }

        when (val s = state) {
            ExploreState.Loading -> Box(Modifier.fillMaxSize(), Alignment.TopCenter) {
                CircularProgressIndicator(
                    color = RexColor.primary,
                    modifier = Modifier.padding(top = 72.dp),
                )
            }

            is ExploreState.Failed -> Failure(s.message) { attempt++ }

            is ExploreState.Loaded -> {
                val shelves = remember(s.rex) { shelvesOf(s.rex) }
                if (shelves.isEmpty()) {
                    Empty()
                } else {
                    val shown = shelves.filter { filter == null || it.type == filter }
                    LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                        item {
                            FilterRow(
                                types = shelves.map { it.type },
                                selected = filter,
                                onSelect = { filter = it },
                            )
                        }
                        items(shown, key = { it.type }) { shelf ->
                            Shelf(shelf, onOpenItem)
                        }
                    }
                }
            }
        }
    }
}

private sealed interface ExploreState {
    data object Loading : ExploreState
    data class Loaded(val rex: List<FeedRecommendation>) : ExploreState
    data class Failed(val message: String) : ExploreState
}

private data class Tile(val rec: FeedRecommendation, val count: Int)
private data class ShelfData(val type: String, val title: String, val tiles: List<Tile>)

/**
 * The grouping, kept out of the composable so it can be read on its own — and
 * so `remember` can hang on to the result rather than regrouping three hundred
 * rows on every recomposition.
 */
private fun shelvesOf(rex: List<FeedRecommendation>): List<ShelfData> {
    val byItem = LinkedHashMap<String, MutableList<FeedRecommendation>>()
    for (rec in rex) {
        val type = rec.items?.type ?: continue
        if (type !in exploreCategories) continue
        byItem.getOrPut(rec.itemId) { mutableListOf() }.add(rec)
    }

    val byType = LinkedHashMap<String, MutableList<Tile>>()
    for ((_, recs) in byItem) {
        val first = recs.first()
        val type = first.items?.type ?: continue
        byType.getOrPut(type) { mutableListOf() }.add(Tile(first, recs.size))
    }

    return exploreCategories.mapNotNull { type ->
        val tiles = byType[type]?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
        ShelfData(
            type = type,
            title = categoryPlural(type) ?: return@mapNotNull null,
            tiles = tiles.sortedByDescending { it.count }.take(20),
        )
    }
}

@Composable
private fun FilterRow(types: List<String>, selected: String?, onSelect: (String?) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(bottom = 8.dp),
    ) {
        item {
            FilterChip("All", selected == null) { onSelect(null) }
        }
        items(types, key = { it }) { type ->
            FilterChip(categoryPlural(type) ?: type, selected == type) { onSelect(type) }
        }
    }
}

@Composable
private fun FilterChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(if (selected) RexColor.primary else RexColor.card)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
        Text(
            label,
            fontSize = 13.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) RexColor.primaryForeground else RexColor.mutedForeground,
        )
    }
}

@Composable
private fun Shelf(shelf: ShelfData, onOpenItem: (String) -> Unit) {
    Column(Modifier.padding(bottom = 20.dp)) {
        Text(
            shelf.title,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = RexColor.foreground,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp),
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(shelf.tiles, key = { it.rec.id }) { tile ->
                TileCard(tile, onOpenItem)
            }
        }
    }
}

@Composable
private fun TileCard(tile: Tile, onOpenItem: (String) -> Unit) {
    val rec = tile.rec
    Column(
        Modifier
            .width(140.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(RexColor.card)
            .clickable { onOpenItem(rec.itemId) }
            .padding(10.dp),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(120.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(RexColor.badgeBackground),
            contentAlignment = Alignment.Center,
        ) {
            val art = rec.items?.imageUrl?.takeIf { it.isNotBlank() }
            val glyph = @Composable { Text("🦕", fontSize = 26.sp) }
            if (art != null) {
                SubcomposeAsyncImage(
                    model = art,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                    loading = { glyph() },
                    error = { glyph() },
                )
            } else {
                glyph()
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            rec.items?.title ?: "Untitled",
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = RexColor.foreground,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        // The caption tells the truth about which kind of shelf this is: a
        // thing two people agree on says so, a thing one person likes says
        // who. iOS makes the same distinction for the same reason.
        Text(
            if (tile.count > 1) {
                "Rex'd by ${tile.count} people"
            } else {
                rec.authorName
            },
            fontSize = 11.sp,
            color = RexColor.mutedForeground,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun Empty() {
    Column(
        Modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(48.dp))
        Text(
            "Nothing to explore yet",
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = RexColor.foreground,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            "Shelves fill up as the people you follow post. Add a few friends and " +
                "come back.",
            fontSize = 14.sp,
            color = RexColor.mutedForeground,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun Failure(message: String, onRetry: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(48.dp))
        Text(
            "Couldn't load Explore",
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = RexColor.foreground,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(8.dp))
        Text(message, fontSize = 13.sp, color = RexColor.mutedForeground, textAlign = TextAlign.Center)
        TextButton(onClick = onRetry) {
            Text("Try again", color = RexColor.primary, fontWeight = FontWeight.SemiBold)
        }
    }
}
