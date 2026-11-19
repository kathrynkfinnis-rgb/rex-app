package com.kathrynfinnis.rex.ui.map

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.rememberCameraPositionState
import com.kathrynfinnis.rex.BuildConfig
import com.kathrynfinnis.rex.data.FeedRecommendation
import com.kathrynfinnis.rex.data.Rex
import com.kathrynfinnis.rex.ui.readableFailure
import com.kathrynfinnis.rex.ui.theme.RexColor

/**
 * Nov 19 — the last of the four tabs that rendered its own name in the middle
 * of an empty screen.
 *
 * Much smaller than MapView.swift, which is 1,562 lines over eleven calls —
 * wants on the map, trips, chain branches, places missing a pin, a coordinate
 * repair tool and an admin mode. This is the part people open the tab for:
 * every place your friends have Rex'd, as pins, tappable through to the thing
 * itself.
 *
 * It needs no new API call. The feed read already selects lat and lng on
 * items, so the pins come out of the same query Explore groups — which is
 * also why this was cheap to add once the key existed.
 *
 * On the key, and why this screen says so out loud when there isn't one:
 *
 * iOS does not pay for maps. RexMapSnapshot moved every tile to MKMapSnapshotter
 * on 29 September, after a cost review found Google Static Maps was "the
 * highest-volume Google SKU Rex had by a wide margin — the first one that
 * would run out, at roughly fifty active users". Android has no free
 * equivalent, so this tab is the one place in Rex that costs money to draw.
 * Ten thousand map loads a month are free and the app is nowhere near that,
 * but it is a billed SKU and should be known to be one.
 *
 * So a debug build uses MAPS_API_KEY_DEBUG from local.properties and nothing
 * else. With no key the map would otherwise render as a blank grey rectangle
 * with a line in logcat, which reads as a broken app; it says what is wrong
 * instead. Never fall back to the production key here — see RexSearch.swift,
 * which refuses the same fallback for the same reason.
 */
@Composable
fun MapScreen(onOpenItem: (String) -> Unit) {
    if (BuildConfig.MAPS_API_KEY.isBlank()) {
        NoKey()
        return
    }

    var state by remember { mutableStateOf<MapState>(MapState.Loading) }
    var attempt by remember { mutableIntStateOf(0) }
    var selected by remember { mutableStateOf<Place?>(null) }

    LaunchedEffect(attempt) {
        state = MapState.Loading
        state = runCatching { MapState.Loaded(placesOf(Rex.feed(limit = 300))) }
            .getOrElse { MapState.Failed(readableFailure(it)) }
    }

    when (val s = state) {
        MapState.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator(color = RexColor.primary)
        }

        is MapState.Failed -> Failure(s.message) { attempt++ }

        is MapState.Loaded -> if (s.places.isEmpty()) {
            Empty()
        } else {
            val camera = rememberCameraPositionState {
                // Opens on the places rather than on the middle of the ocean,
                // which is where a default LatLng(0,0) puts you.
                position = CameraPosition.fromLatLngZoom(
                    LatLng(
                        s.places.map { it.lat }.average(),
                        s.places.map { it.lng }.average(),
                    ),
                    10f,
                )
            }
            Box(Modifier.fillMaxSize()) {
                GoogleMap(
                    modifier = Modifier.fillMaxSize(),
                    cameraPositionState = camera,
                    properties = MapProperties(mapType = com.google.maps.android.compose.MapType.NORMAL),
                    // No "my location" button: the location permission is
                    // declared but nothing asks for it yet, and a button that
                    // does nothing is worse than no button.
                    uiSettings = MapUiSettings(zoomControlsEnabled = false, myLocationButtonEnabled = false),
                    onMapClick = { selected = null },
                ) {
                    s.places.forEach { place ->
                        Marker(
                            state = MarkerState(position = LatLng(place.lat, place.lng)),
                            title = place.title,
                            onClick = {
                                selected = place
                                // true: we have handled it, so the default
                                // info window does not also open over the top
                                // of the card below.
                                true
                            },
                        )
                    }
                }

                selected?.let { place ->
                    PlaceCard(
                        place = place,
                        onOpen = { onOpenItem(place.itemId) },
                        onDismiss = { selected = null },
                        modifier = Modifier.align(Alignment.BottomCenter),
                    )
                }
            }
        }
    }
}

private sealed interface MapState {
    data object Loading : MapState
    data class Loaded(val places: List<Place>) : MapState
    data class Failed(val message: String) : MapState
}

private data class Place(
    val itemId: String,
    val title: String,
    val address: String?,
    val lat: Double,
    val lng: Double,
    val count: Int,
    val who: String,
)

/**
 * One pin per thing, not one per Rex — the same grouping Explore does, and the
 * same reason: two people Rexing the same restaurant is one restaurant, and
 * two pins stacked on one spot is a bug people report.
 *
 * A row with no coordinates is skipped rather than dropped at (0,0), which is
 * in the Atlantic.
 */
private fun placesOf(rex: List<FeedRecommendation>): List<Place> {
    val byItem = LinkedHashMap<String, MutableList<FeedRecommendation>>()
    for (rec in rex) {
        val item = rec.items ?: continue
        if (item.lat == null || item.lng == null) continue
        byItem.getOrPut(rec.itemId) { mutableListOf() }.add(rec)
    }
    return byItem.values.mapNotNull { recs ->
        val first = recs.first()
        val item = first.items ?: return@mapNotNull null
        Place(
            itemId = first.itemId,
            title = item.title,
            address = item.address,
            lat = item.lat ?: return@mapNotNull null,
            lng = item.lng ?: return@mapNotNull null,
            count = recs.size,
            who = first.authorName,
        )
    }
}

@Composable
private fun PlaceCard(
    place: Place,
    onOpen: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .fillMaxWidth()
            .padding(16.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(RexColor.card)
            .clickable(onClick = onOpen)
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                place.title,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = RexColor.foreground,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onDismiss) {
                Text("Close", fontSize = 12.sp, color = RexColor.mutedForeground)
            }
        }
        place.address?.takeIf { it.isNotBlank() }?.let {
            Text(it, fontSize = 12.sp, color = RexColor.mutedForeground, maxLines = 2)
        }
        Spacer(Modifier.height(4.dp))
        Text(
            if (place.count > 1) "Rex'd by ${place.count} people" else place.who,
            fontSize = 12.sp,
            color = RexColor.primary,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

/**
 * Said plainly, because the person who sees this is whoever is building Rex,
 * not somebody who installed it. A blank grey map with a logcat line is the
 * alternative and it reads as a broken app.
 */
@Composable
private fun NoKey() {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
    ) {
        Text("🗺️", fontSize = 36.sp)
        Spacer(Modifier.height(12.dp))
        Text(
            "No Maps key in this build",
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = RexColor.foreground,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            "Add MAPS_API_KEY_DEBUG to android/local.properties and build again. " +
                "Debug builds never fall back to the production key — see " +
                "mapsKey() in app/build.gradle.kts.",
            fontSize = 13.sp,
            color = RexColor.mutedForeground,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun Empty() {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
    ) {
        Text(
            "Nothing on the map yet",
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = RexColor.foreground,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            "Places your friends Rex show up here once they've been added with " +
                "an address.",
            fontSize = 14.sp,
            color = RexColor.mutedForeground,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun Failure(message: String, onRetry: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
    ) {
        Text(
            "Couldn't load the map",
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
