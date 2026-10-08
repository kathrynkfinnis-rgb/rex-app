package com.kathrynfinnis.rex.ui.feed

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.kathrynfinnis.rex.data.FeedRecommendation
import com.kathrynfinnis.rex.data.Rex
import com.kathrynfinnis.rex.ui.theme.RexColor

/**
 * The first real screen, and deliberately the first: it reads from the live
 * database rather than a fixture, so the whole chain — Supabase client, row
 * level security, the model names, the feed's own rules — is proved on day
 * one rather than assumed.
 *
 * Signed out, RLS returns nothing. That is the correct answer rather than a
 * failure, and the empty state says so plainly instead of pretending the feed
 * is empty.
 */
@Composable
fun FeedScreen() {
    var state by remember { mutableStateOf<FeedState>(FeedState.Loading) }

    LaunchedEffect(Unit) {
        state = try {
            FeedState.Loaded(Rex.feed())
        } catch (e: Exception) {
            FeedState.Failed(e.message ?: "Couldn't load the feed.")
        }
    }

    when (val s = state) {
        FeedState.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator(color = RexColor.primary)
        }

        is FeedState.Failed -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            Text(s.message, color = RexColor.destructive, modifier = Modifier.padding(32.dp))
        }

        is FeedState.Loaded -> if (s.rex.isEmpty()) {
            Box(Modifier.fillMaxSize(), Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Nothing here yet", fontWeight = FontWeight.SemiBold, color = RexColor.foreground)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "Sign in to see what your friends are Rexing.",
                        color = RexColor.mutedForeground,
                    )
                }
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(s.rex) { RexCard(it) }
            }
        }
    }
}

private sealed interface FeedState {
    data object Loading : FeedState
    data class Loaded(val rex: List<FeedRecommendation>) : FeedState
    data class Failed(val message: String) : FeedState
}

/**
 * A deliberately plain first pass at RecommendationCardView. The thumbnail,
 * title, who said it and what they said — the four things the iOS card leads
 * with. Ratings, the want-to-try flame, the action row and the swipe all come
 * later; this is here to prove the data arrives and reads correctly.
 */
@Composable
private fun RexCard(rec: FeedRecommendation) {
    Card(
        colors = CardDefaults.cardColors(containerColor = RexColor.card),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(Modifier.padding(12.dp)) {
            val image = rec.items?.imageUrl ?: rec.photoUrls?.firstOrNull()
            if (image != null) {
                AsyncImage(
                    model = image,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(56.dp)
                        .clip(RoundedCornerShape(8.dp)),
                )
                Spacer(Modifier.size(12.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(
                    rec.items?.title ?: "Untitled",
                    fontWeight = FontWeight.SemiBold,
                    color = RexColor.foreground,
                )
                rec.items?.subtitle?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, color = RexColor.mutedForeground)
                }
                rec.note?.takeIf { it.isNotEmpty() }?.let {
                    Spacer(Modifier.height(4.dp))
                    Text(it, color = RexColor.foreground, maxLines = 3)
                }
                Spacer(Modifier.height(6.dp))
                Row {
                    Text(
                        rec.profiles?.displayName ?: rec.profiles?.username ?: "Someone",
                        color = RexColor.mutedForeground,
                    )
                    rec.tier?.let {
                        Text(" · $it", color = RexColor.gold)
                    }
                }
            }
        }
    }
}
