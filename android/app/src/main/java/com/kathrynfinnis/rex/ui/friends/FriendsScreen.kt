package com.kathrynfinnis.rex.ui.friends

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import com.kathrynfinnis.rex.data.Friendship
import com.kathrynfinnis.rex.data.Rex
import com.kathrynfinnis.rex.data.RexAuth
import com.kathrynfinnis.rex.data.RexProfile
import com.kathrynfinnis.rex.data.SuggestedFriend
import com.kathrynfinnis.rex.ui.readableFailure
import com.kathrynfinnis.rex.ui.theme.RexColor
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Nov 17 — the Android port of FriendsView.swift, and the first screen in the
 * parity work because nothing else on this platform worked without it. The
 * feed reads what the people you follow have posted; there was no way to
 * follow anybody; so a new Android account saw an empty feed for ever, under
 * an empty state promising it would fill up.
 *
 * Same scope as the iOS v1: search and send, incoming and outgoing requests,
 * the friends list, and friends-of-friends suggestions.
 *
 * Two things from iOS are deliberately not here.
 *
 *  - The contacts finder. It needs READ_CONTACTS, a permission prompt, a
 *    rationale screen and a Play data-safety declaration, which is its own
 *    piece of work and not something to bury in a port.
 *  - The invite link. iOS shares a TestFlight URL, which is wrong for this
 *    app on two counts: Rex is on the App Store now, and there is no Play
 *    listing to send an Android user's friends to at all. A share sheet
 *    pointing Android people at an iPhone beta is worse than no button.
 *
 * Which leaves search needing a username, and iOS's own note says that is
 * exactly what nobody has on day one. Suggestions carry that weight here, and
 * they include active accounts with no mutuals for precisely this reason.
 */
@Composable
fun FriendsScreen(onBack: () -> Unit, onOpenProfile: ((String, String) -> Unit)? = null) {
    val scope = rememberCoroutineScope()

    var state by remember { mutableStateOf<FriendsState>(FriendsState.Loading) }
    var attempt by remember { mutableStateOf(0) }

    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<RexProfile>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    var searchNote by remember { mutableStateOf<String?>(null) }
    // Ids with a request in flight, so one Add button can spin without
    // disabling the others.
    var working by remember { mutableStateOf<Set<String>>(emptySet()) }

    val me = RexAuth.currentUserId

    LaunchedEffect(attempt) {
        state = FriendsState.Loading
        state = runCatching {
            val friendships = Rex.friendships()
            val ids = friendships.flatMap { listOf(it.requesterId, it.addresseeId) }.distinct()
            val byId = Rex.profiles(ids).associateBy { it.id }
            // Best-effort, exactly as on iOS: suggested_friends_for_me is a
            // later migration than the rest of this, and a project without it
            // should still get a working screen rather than an error.
            val suggested = runCatching { Rex.suggestedFriends() }.getOrDefault(emptyList())
            FriendsState.Loaded(friendships, byId, suggested)
        }.getOrElse { FriendsState.Failed(readableFailure(it)) }
    }

    // Results as you type, 350ms behind the last keystroke. Restarting the
    // effect on `query` cancels the previous delay, which is the debounce.
    LaunchedEffect(query) {
        val q = query.trim()
        if (q.length < 2) {
            results = emptyList()
            searchNote = null
            return@LaunchedEffect
        }
        delay(350)
        searching = true
        runCatching { Rex.searchProfiles(q) }
            .onSuccess { found ->
                results = found.filter { it.id != me }
                searchNote = if (found.isEmpty()) {
                    "No one on Rex matches “$q”. Try their name instead of their username."
                } else {
                    null
                }
            }
            // Sept 14 on iOS — search used to swallow its own failure and show
            // nothing, which is how a missing database function went unnoticed
            // from July to September. It says what happened.
            .onFailure {
                results = emptyList()
                searchNote = readableFailure(it)
            }
        searching = false
    }

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp, top = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = RexColor.foreground,
                )
            }
            Text(
                "Friends",
                style = MaterialTheme.typography.headlineMedium,
                color = RexColor.foreground,
            )
        }

        when (val s = state) {
            FriendsState.Loading -> Box(
                Modifier.fillMaxSize(),
                contentAlignment = Alignment.TopCenter,
            ) {
                CircularProgressIndicator(
                    color = RexColor.primary,
                    modifier = Modifier.padding(top = 80.dp),
                )
            }

            is FriendsState.Failed -> Failure(s.message) { attempt++ }

            is FriendsState.Loaded -> {
                val incoming = s.friendships.filter { it.addresseeId == me && it.status == "pending" }
                val outgoing = s.friendships.filter { it.requesterId == me && it.status == "pending" }
                val accepted = s.friendships.filter { it.status == "accepted" }
                // Anybody already in a friendship row with you, whichever way
                // round and whatever its status. Filtering suggestions and
                // search on this rather than removing a row on send means a
                // successful request simply drops out on the next load, with
                // no separate bookkeeping.
                val connected = s.friendships
                    .flatMap { listOf(it.requesterId, it.addresseeId) }
                    .toSet()

                fun other(f: Friendship): RexProfile? =
                    s.profiles[if (f.requesterId == me) f.addresseeId else f.requesterId]

                fun send(id: String) {
                    working = working + id
                    scope.launch {
                        runCatching { Rex.sendFriendRequest(id) }
                            .onSuccess { attempt++ }
                            .onFailure { state = FriendsState.Failed(readableFailure(it)) }
                        working = working - id
                    }
                }

                fun respond(f: Friendship, accept: Boolean) {
                    working = working + f.id
                    scope.launch {
                        runCatching { Rex.respondToFriendRequest(f.id, accept) }
                            .onSuccess { attempt++ }
                            .onFailure { state = FriendsState.Failed(readableFailure(it)) }
                        working = working - f.id
                    }
                }

                LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                    item {
                        SearchField(
                            query = query,
                            searching = searching,
                            onQueryChange = { query = it },
                        )
                        searchNote?.let {
                            Text(
                                it,
                                fontSize = 13.sp,
                                color = RexColor.mutedForeground,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                            )
                        }
                    }

                    if (results.isNotEmpty()) {
                        sectionHeader("Search results")
                        items(results, key = { "search-${it.id}" }) { profile ->
                            PersonRow(
                                profile = profile,
                                onOpen = onOpenProfile,
                            ) {
                                AddButton(
                                    alreadyConnected = profile.id in connected,
                                    busy = profile.id in working,
                                    onClick = { send(profile.id) },
                                )
                            }
                        }
                    }

                    val toSuggest = s.suggested.filter { it.id !in connected && it.id != me }
                    if (toSuggest.isNotEmpty()) {
                        sectionHeader("Suggested for you")
                        items(toSuggest, key = { "suggested-${it.id}" }) { person ->
                            PersonRow(
                                profile = RexProfile(
                                    id = person.id,
                                    username = person.username,
                                    displayName = person.displayName,
                                    avatarUrl = person.avatarUrl,
                                ),
                                // Oct 4 on iOS — suggestions include active
                                // accounts as well as friends-of-friends, so a
                                // new account sees somebody. Those arrive with
                                // no mutuals, and "0 mutual friends" is a worse
                                // line than saying nothing: it reads as a
                                // reason not to add them.
                                subtitle = when (person.mutualCount) {
                                    0 -> "On Rex"
                                    1 -> "1 mutual friend"
                                    else -> "${person.mutualCount} mutual friends"
                                },
                                onOpen = onOpenProfile,
                            ) {
                                AddButton(
                                    alreadyConnected = false,
                                    busy = person.id in working,
                                    onClick = { send(person.id) },
                                )
                            }
                        }
                    }

                    if (incoming.isNotEmpty()) {
                        sectionHeader("Requests for you")
                        items(incoming, key = { it.id }) { f ->
                            other(f)?.let { profile ->
                                PersonRow(profile = profile, onOpen = onOpenProfile) {
                                    if (f.id in working) {
                                        CircularProgressIndicator(
                                            color = RexColor.primary,
                                            modifier = Modifier.size(20.dp),
                                        )
                                    } else {
                                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                            RoundAction(
                                                icon = Icons.Outlined.Check,
                                                label = "Accept",
                                                background = RexColor.primary,
                                                tint = RexColor.primaryForeground,
                                            ) { respond(f, accept = true) }
                                            RoundAction(
                                                icon = Icons.Outlined.Close,
                                                label = "Decline",
                                                background = RexColor.card,
                                                tint = RexColor.foreground,
                                                outlined = true,
                                            ) { respond(f, accept = false) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if (outgoing.isNotEmpty()) {
                        sectionHeader("Pending")
                        items(outgoing, key = { it.id }) { f ->
                            other(f)?.let { profile ->
                                PersonRow(profile = profile, onOpen = onOpenProfile) {
                                    Text(
                                        "Waiting…",
                                        fontSize = 12.sp,
                                        color = RexColor.mutedForeground,
                                    )
                                }
                            }
                        }
                    }

                    sectionHeader(
                        if (accepted.isEmpty()) "Your friends" else "Your friends (${accepted.size})"
                    )
                    if (accepted.isEmpty()) {
                        item {
                            Text(
                                "No friends yet. Search by name above, or add somebody " +
                                    "suggested for you.",
                                fontSize = 14.sp,
                                color = RexColor.mutedForeground,
                                modifier = Modifier.padding(horizontal = 16.dp),
                            )
                        }
                    } else {
                        items(accepted, key = { it.id }) { f ->
                            other(f)?.let { profile ->
                                PersonRow(profile = profile, onOpen = onOpenProfile) {}
                            }
                        }
                    }
                }
            }
        }
    }
}

private sealed interface FriendsState {
    data object Loading : FriendsState
    data class Loaded(
        val friendships: List<Friendship>,
        val profiles: Map<String, RexProfile>,
        val suggested: List<SuggestedFriend>,
    ) : FriendsState
    data class Failed(val message: String) : FriendsState
}

/** A section label, as its own list item so the header scrolls with its rows. */
private fun androidx.compose.foundation.lazy.LazyListScope.sectionHeader(title: String) {
    item {
        Text(
            title.uppercase(),
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = RexColor.mutedForeground,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp),
        )
    }
}

@Composable
private fun SearchField(query: String, searching: Boolean, onQueryChange: (String) -> Unit) {
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        singleLine = true,
        // Name as well as username: the database has matched both since
        // August, and iOS's placeholder spent months not saying so.
        placeholder = { Text("Search by name or username", color = RexColor.placeholder) },
        leadingIcon = {
            if (searching) {
                CircularProgressIndicator(
                    color = RexColor.primary,
                    modifier = Modifier.size(18.dp),
                )
            } else {
                Icon(Icons.Outlined.Search, contentDescription = null, tint = RexColor.mutedForeground)
            }
        },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(),
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = RexColor.card,
            unfocusedContainerColor = RexColor.card,
            focusedBorderColor = RexColor.primary,
            unfocusedBorderColor = RexColor.border,
            focusedTextColor = RexColor.foreground,
            unfocusedTextColor = RexColor.foreground,
            cursorColor = RexColor.primary,
        ),
        modifier = Modifier.fillMaxWidth().padding(16.dp),
    )
}

/**
 * Avatar, name, username, and whatever action belongs on the right.
 *
 * The name and photo open their profile and the trailing action does not,
 * matching iOS — accepting a request should never be one mis-tap away from
 * navigating somewhere. `onOpenProfile` is nullable because the profile screen
 * is the next port, not this one: until it exists the row simply does not
 * respond to a tap, rather than pretending to.
 */
@Composable
private fun PersonRow(
    profile: RexProfile,
    subtitle: String? = null,
    onOpen: ((String, String) -> Unit)? = null,
    trailing: @Composable () -> Unit,
) {
    val name = profile.displayName?.takeIf { it.isNotBlank() } ?: profile.username
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(RexColor.card)
            .padding(12.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .weight(1f)
                .then(
                    if (onOpen != null) {
                        Modifier.clickable { onOpen(profile.id, name) }
                    } else {
                        Modifier
                    }
                ),
        ) {
            Avatar(profile.avatarUrl, name)
            Spacer(Modifier.size(12.dp))
            Column {
                Text(
                    name,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = RexColor.foreground,
                )
                Text(
                    subtitle ?: "@${profile.username}",
                    fontSize = 12.sp,
                    color = RexColor.mutedForeground,
                )
            }
        }
        trailing()
    }
}

/** The photo, or the first letter of the name on Rex's own green. */
@Composable
private fun Avatar(url: String?, name: String) {
    val clean = url?.takeIf { it.isNotBlank() }
    Box(
        Modifier.size(40.dp).clip(CircleShape).background(RexColor.badgeBackground),
        contentAlignment = Alignment.Center,
    ) {
        // Subcompose rather than plain AsyncImage, so a failed load falls back
        // to the initial instead of an empty circle. See the note in
        // ProfileScreen — found by running it, not by compiling it.
        val initial = @Composable {
            Text(
                name.take(1).uppercase(),
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = RexColor.badgeForeground,
            )
        }
        if (clean != null) {
            SubcomposeAsyncImage(
                model = clean,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                loading = { initial() },
                error = { initial() },
            )
        } else {
            initial()
        }
    }
}

@Composable
private fun AddButton(alreadyConnected: Boolean, busy: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(if (alreadyConnected) RexColor.badgeBackground else RexColor.primary)
            .then(
                if (alreadyConnected || busy) Modifier else Modifier.clickable(onClick = onClick)
            )
            .padding(horizontal = 14.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (busy) {
            CircularProgressIndicator(
                color = RexColor.primaryForeground,
                modifier = Modifier.size(16.dp),
            )
        } else {
            Text(
                if (alreadyConnected) "Sent" else "Add",
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (alreadyConnected) RexColor.foreground else RexColor.primaryForeground,
            )
        }
    }
}

@Composable
private fun RoundAction(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    background: androidx.compose.ui.graphics.Color,
    tint: androidx.compose.ui.graphics.Color,
    outlined: Boolean = false,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(if (outlined) RexColor.card else background)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(18.dp))
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
            "Couldn't load your friends",
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = RexColor.foreground,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            message,
            fontSize = 13.sp,
            color = RexColor.mutedForeground,
            textAlign = TextAlign.Center,
        )
        TextButton(onClick = onRetry) {
            Text("Try again", color = RexColor.primary, fontWeight = FontWeight.SemiBold)
        }
    }
}
