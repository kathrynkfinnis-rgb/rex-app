package com.kathrynfinnis.rex.ui.profile

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
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.kathrynfinnis.rex.data.FeedRecommendation
import com.kathrynfinnis.rex.data.Friendship
import com.kathrynfinnis.rex.data.Rex
import com.kathrynfinnis.rex.data.RexAuth
import com.kathrynfinnis.rex.data.RexList
import com.kathrynfinnis.rex.data.RexProfile
import com.kathrynfinnis.rex.ui.readableFailure
import com.kathrynfinnis.rex.ui.theme.RexColor
import kotlinx.coroutines.launch

/**
 * Nov 17 — the Android port of ProfileView.swift and UserProfileView.swift,
 * in one file because they are the same page with a different owner. iOS
 * splits them and pays for it: 668 and 734 lines that render the same header,
 * the same grid and the same empty states, twice.
 *
 * Your own profile is where signing out lives, which until today Android had
 * no way to do at all. Somebody else's is what a row in Friends has been
 * waiting for — the rows were built to expect it and deliberately did not
 * navigate until it existed.
 *
 * Ported at the same v1 shape as the rest of this app, and these are the
 * pieces of iOS left out, each for a stated reason rather than by omission:
 *
 *  - Editing your profile. It needs the photo picker and an upload path, and
 *    Storage is installed but nothing on Android writes to it yet.
 *  - Blocking, and hiding a user. iOS keeps a hidden-users set in the client
 *    and filters every read through it; a block button with no filtering
 *    behind it would be a lie.
 *  - Ranked categories, followed collections, and the wants shelf on someone
 *    else's profile. Each is its own read and its own screen on iOS.
 *  - Deleting a Rex. There is no edit path on Android to pair it with.
 */

/** Your own profile. */
@Composable
fun MyProfileScreen(
    onBack: () -> Unit,
    onOpenItem: (String) -> Unit,
    onOpenFriends: () -> Unit,
) {
    val me = RexAuth.currentUserId
    if (me == null) {
        NotSignedIn(onBack)
        return
    }
    ProfilePage(
        userId = me,
        isMe = true,
        fallbackName = null,
        onBack = onBack,
        onOpenItem = onOpenItem,
        onOpenFriends = onOpenFriends,
    )
}

/**
 * Somebody else's.
 *
 * `fallbackName` is the name the caller already had — Friends passes the one
 * off the row it was tapped from, so the header reads correctly before the
 * first query returns rather than flashing "Someone".
 */
@Composable
fun UserProfileScreen(
    userId: String,
    fallbackName: String,
    onBack: () -> Unit,
    onOpenItem: (String) -> Unit,
) {
    ProfilePage(
        userId = userId,
        isMe = userId == RexAuth.currentUserId,
        fallbackName = fallbackName,
        onBack = onBack,
        onOpenItem = onOpenItem,
        onOpenFriends = null,
    )
}

@Composable
private fun ProfilePage(
    userId: String,
    isMe: Boolean,
    fallbackName: String?,
    onBack: () -> Unit,
    onOpenItem: (String) -> Unit,
    onOpenFriends: (() -> Unit)?,
) {
    val scope = rememberCoroutineScope()
    var state by remember { mutableStateOf<ProfileState>(ProfileState.Loading) }
    var attempt by remember { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf(false) }

    val me = RexAuth.currentUserId

    LaunchedEffect(userId, attempt) {
        state = ProfileState.Loading
        state = runCatching {
            val profile = Rex.profiles(listOf(userId)).firstOrNull()
            val rex = Rex.recommendationsBy(userId)
            val collections = if (isMe) Rex.myCollections() else Rex.collectionsOf(userId)
            // Only wanted for the friend button, so only fetched when there is
            // one to draw.
            val friendships = if (isMe) emptyList() else Rex.friendships()
            ProfileState.Loaded(profile, rex, collections, friendships)
        }.getOrElse { ProfileState.Failed(readableFailure(it)) }
    }

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(start = 4.dp, end = 8.dp, top = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = RexColor.foreground,
                )
            }
            Spacer(Modifier.weight(1f))
            if (isMe) {
                TextButton(onClick = {
                    busy = true
                    scope.launch {
                        runCatching { RexAuth.signOut() }
                        busy = false
                        // No navigation afterwards: RexRoot watches the session
                        // and swaps the whole tree for the sign-in screen the
                        // moment it clears. Popping here as well would be the
                        // double-navigation the auth screen's notes warn about.
                    }
                }) {
                    Text(
                        if (busy) "Signing out…" else "Sign out",
                        color = RexColor.destructive,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }

        when (val s = state) {
            ProfileState.Loading -> Box(Modifier.fillMaxSize(), Alignment.TopCenter) {
                CircularProgressIndicator(
                    color = RexColor.primary,
                    modifier = Modifier.padding(top = 80.dp),
                )
            }

            is ProfileState.Failed -> Failure(s.message) { attempt++ }

            is ProfileState.Loaded -> {
                val name = s.profile?.displayName?.takeIf { it.isNotBlank() }
                    ?: s.profile?.username?.takeIf { it.isNotBlank() }
                    ?: fallbackName
                    ?: "Someone"

                LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
                    item {
                        Header(
                            name = name,
                            username = s.profile?.username,
                            avatarUrl = s.profile?.avatarUrl,
                            rexCount = s.rex.size,
                            collectionCount = s.collections.size,
                        )
                        if (!isMe && me != null) {
                            FriendButton(
                                userId = userId,
                                me = me,
                                friendships = s.friendships,
                                busy = busy,
                                onSend = {
                                    busy = true
                                    scope.launch {
                                        runCatching { Rex.sendFriendRequest(userId) }
                                            .onFailure {
                                                state = ProfileState.Failed(readableFailure(it))
                                            }
                                        busy = false
                                        attempt++
                                    }
                                },
                                onAccept = { f ->
                                    busy = true
                                    scope.launch {
                                        runCatching {
                                            Rex.respondToFriendRequest(f.id, accept = true)
                                        }.onFailure {
                                            state = ProfileState.Failed(readableFailure(it))
                                        }
                                        busy = false
                                        attempt++
                                    }
                                },
                            )
                        }
                        if (isMe && onOpenFriends != null) {
                            RowLink("Friends", onOpenFriends)
                        }
                    }

                    if (s.collections.isNotEmpty()) {
                        sectionHeader("Collections (${s.collections.size})")
                        item {
                            Column {
                                s.collections.forEach { list ->
                                    CollectionLine(list)
                                }
                            }
                        }
                    }

                    sectionHeader(
                        if (s.rex.isEmpty()) "Rex" else "Rex (${s.rex.size})"
                    )
                    if (s.rex.isEmpty()) {
                        item {
                            Text(
                                if (isMe) {
                                    "Nothing yet. Tap the + to Rex something."
                                } else {
                                    "$name hasn't Rex'd anything you can see."
                                },
                                fontSize = 14.sp,
                                color = RexColor.mutedForeground,
                                modifier = Modifier.padding(horizontal = 16.dp),
                            )
                        }
                    } else {
                        items(s.rex, key = { it.id }) { rec ->
                            RexLine(rec) { onOpenItem(rec.itemId) }
                        }
                    }
                }
            }
        }
    }
}

private sealed interface ProfileState {
    data object Loading : ProfileState
    data class Loaded(
        val profile: RexProfile?,
        val rex: List<FeedRecommendation>,
        val collections: List<RexList>,
        val friendships: List<Friendship>,
    ) : ProfileState
    data class Failed(val message: String) : ProfileState
}

@Composable
private fun Header(
    name: String,
    username: String?,
    avatarUrl: String?,
    rexCount: Int,
    collectionCount: Int,
) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.size(84.dp).clip(CircleShape).background(RexColor.badgeBackground),
            contentAlignment = Alignment.Center,
        ) {
            val clean = avatarUrl?.takeIf { it.isNotBlank() }
            if (clean != null) {
                AsyncImage(
                    model = clean,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Text(
                    name.take(1).uppercase(),
                    fontSize = 32.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = RexColor.badgeForeground,
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        Text(
            name,
            style = MaterialTheme.typography.headlineMedium,
            color = RexColor.foreground,
            textAlign = TextAlign.Center,
        )
        username?.takeIf { it.isNotBlank() }?.let {
            Text("@$it", fontSize = 13.sp, color = RexColor.mutedForeground)
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            Stat(rexCount, if (rexCount == 1) "Rex" else "Rex")
            Stat(collectionCount, if (collectionCount == 1) "Collection" else "Collections")
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun Stat(value: Int, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            "$value",
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            color = RexColor.foreground,
        )
        Text(label.uppercase(), fontSize = 10.sp, color = RexColor.mutedForeground)
    }
}

/**
 * Add, accept, pending or nothing — whichever the friendship rows say.
 *
 * Reads the same four states FriendsScreen does, from the same rows, rather
 * than keeping its own idea of them: an incoming request is answerable from
 * here too, which is what you want when you have opened somebody's profile to
 * decide whether you know them.
 */
@Composable
private fun FriendButton(
    userId: String,
    me: String,
    friendships: List<Friendship>,
    busy: Boolean,
    onSend: () -> Unit,
    onAccept: (Friendship) -> Unit,
) {
    val row = friendships.firstOrNull {
        (it.requesterId == me && it.addresseeId == userId) ||
            (it.addresseeId == me && it.requesterId == userId)
    }
    val label: String
    val action: (() -> Unit)?
    when {
        row == null -> { label = "Add friend"; action = onSend }
        row.status == "accepted" -> { label = "Friends"; action = null }
        row.addresseeId == me -> { label = "Accept request"; action = { onAccept(row) } }
        else -> { label = "Request sent"; action = null }
    }

    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(if (action == null) RexColor.badgeBackground else RexColor.primary)
            .then(if (action != null && !busy) Modifier.clickable(onClick = action) else Modifier)
            .padding(vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (busy) {
            CircularProgressIndicator(
                color = RexColor.primaryForeground,
                modifier = Modifier.size(18.dp),
            )
        } else {
            Text(
                label,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (action == null) RexColor.foreground else RexColor.primaryForeground,
            )
        }
    }
    Spacer(Modifier.height(8.dp))
}

@Composable
private fun RowLink(label: String, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(RexColor.card)
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = RexColor.foreground)
    }
}

@Composable
private fun CollectionLine(list: RexList) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(RexColor.card)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(list.emoji?.takeIf { it.isNotBlank() } ?: "📍", fontSize = 18.sp)
        Spacer(Modifier.size(10.dp))
        Text(list.name, fontSize = 14.sp, color = RexColor.foreground)
    }
}

/**
 * One Rex. The author is not drawn — on a profile every row has the same one,
 * which is also why nothing here needs authorName and the anonymity mask
 * never comes up.
 */
@Composable
private fun RexLine(rec: FeedRecommendation, onOpen: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(RexColor.card)
            .clickable(onClick = onOpen)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(48.dp).clip(RoundedCornerShape(10.dp)).background(RexColor.badgeBackground),
            contentAlignment = Alignment.Center,
        ) {
            val art = rec.items?.imageUrl?.takeIf { it.isNotBlank() }
            if (art != null) {
                AsyncImage(
                    model = art,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Text("🦕", fontSize = 20.sp)
            }
        }
        Spacer(Modifier.size(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                rec.items?.title ?: "Untitled",
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = RexColor.foreground,
            )
            val sub = listOfNotNull(
                rec.tier,
                rec.items?.subtitle?.takeIf { it.isNotBlank() },
            ).joinToString(" · ")
            if (sub.isNotEmpty()) {
                Text(sub, fontSize = 12.sp, color = RexColor.mutedForeground)
            }
        }
    }
}

private fun LazyListScope.sectionHeader(title: String) {
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
private fun NotSignedIn(onBack: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(64.dp))
        Text(
            "You're not signed in",
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = RexColor.foreground,
        )
        TextButton(onClick = onBack) {
            Text("Back", color = RexColor.primary, fontWeight = FontWeight.SemiBold)
        }
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
            "Couldn't load this profile",
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
