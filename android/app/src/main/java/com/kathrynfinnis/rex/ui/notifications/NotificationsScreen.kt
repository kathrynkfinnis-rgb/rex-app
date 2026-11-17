package com.kathrynfinnis.rex.ui.notifications

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
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
import coil.compose.SubcomposeAsyncImage
import com.kathrynfinnis.rex.data.Friendship
import com.kathrynfinnis.rex.data.Rex
import com.kathrynfinnis.rex.data.RexAuth
import com.kathrynfinnis.rex.data.RexNotification
import com.kathrynfinnis.rex.ui.readableFailure
import com.kathrynfinnis.rex.ui.theme.RexColor
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.time.OffsetDateTime

/**
 * Nov 17 — the Android port of NotificationsView.swift. The bell, in-app.
 *
 * This is the list, not the delivery. Push on Android does not exist at all —
 * there is no Firebase or FCM anywhere in the project, so the send-push edge
 * function has only ever reached iPhones. That is a separate and much larger
 * job: a Firebase project, google-services.json, a service, a token table
 * write, and send-push taught to speak FCM as well as APNs.
 *
 * What a notification reads as lives on the model rather than here, ported
 * line for line from the Swift. Not paraphrased on purpose: every branch of
 * it is a bug somebody reported, and two of them (rec_tagged, ticket_reminder)
 * spent months reading "New activity" on iOS because a type had no line.
 *
 * Left out of this port, with reasons:
 *
 *  - Notification preferences. The columns and defaults exist and iOS has a
 *    screen for them, but a preferences page whose push toggle does nothing —
 *    because there is no push — would be a lie on this platform.
 *  - Opening a blast, a trip or a collection. None has an Android screen yet,
 *    so those rows read and mark as read but do not navigate. Deliberate: a
 *    row that goes nowhere beats one that goes somewhere wrong.
 */
@Composable
fun NotificationsScreen(
    onBack: () -> Unit,
    onOpenItem: (String) -> Unit,
    onOpenFriends: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var state by remember { mutableStateOf<NotifState>(NotifState.Loading) }
    var attempt by remember { mutableIntStateOf(0) }
    var working by remember { mutableStateOf<Set<String>>(emptySet()) }

    val me = RexAuth.currentUserId

    LaunchedEffect(attempt) {
        state = NotifState.Loading
        state = runCatching {
            val rows = Rex.notifications()
            // Resolved in one batch rather than per row: entity_id is a
            // recommendation and every screen here is addressed by item.
            val itemIds = Rex.itemIdsFor(rows.mapNotNull { it.linkedRecommendationId }.distinct())
            // Only needed to answer a friend request from this screen.
            val friendships = if (rows.any { it.type == "friend_request" }) {
                runCatching { Rex.friendships() }.getOrDefault(emptyList())
            } else {
                emptyList()
            }
            NotifState.Loaded(rows, itemIds, friendships)
        }.getOrElse { NotifState.Failed(readableFailure(it)) }

        // Marked read on open, as iOS does — arriving at the list is what
        // "seen" means. Best-effort inside the API call, so a failure here
        // never costs the list that is already on screen.
        (state as? NotifState.Loaded)?.let { loaded ->
            val unread = loaded.rows.filter { it.isUnread }.map { it.id }
            if (unread.isNotEmpty()) Rex.markNotificationsRead(unread)
        }
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
                "Notifications",
                style = MaterialTheme.typography.headlineMedium,
                color = RexColor.foreground,
            )
        }

        when (val s = state) {
            NotifState.Loading -> Box(Modifier.fillMaxSize(), Alignment.TopCenter) {
                CircularProgressIndicator(
                    color = RexColor.primary,
                    modifier = Modifier.padding(top = 80.dp),
                )
            }

            is NotifState.Failed -> Failure(s.message) { attempt++ }

            is NotifState.Loaded -> if (s.rows.isEmpty()) {
                Empty()
            } else {
                LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp)) {
                    items(s.rows, key = { it.id }) { n ->
                        val incoming = if (n.type == "friend_request" && me != null) {
                            s.friendships.firstOrNull {
                                it.status == "pending" &&
                                    it.addresseeId == me &&
                                    it.requesterId == n.actorId
                            }
                        } else {
                            null
                        }

                        NotificationRow(
                            notification = n,
                            busy = n.id in working,
                            // A friend request opens Friends when it can no
                            // longer be answered here, which is where the rest
                            // of them are.
                            onOpen = {
                                val recId = n.linkedRecommendationId
                                val itemId = recId?.let { s.itemIds[it] }
                                when {
                                    itemId != null -> onOpenItem(itemId)
                                    n.type == "friend_request" ||
                                        n.type == "friend_accepted" ||
                                        n.type == "friend_requests_waiting" -> onOpenFriends()
                                    else -> Unit
                                }
                            },
                            onDelete = {
                                working = working + n.id
                                scope.launch {
                                    runCatching { Rex.deleteNotification(n.id) }
                                        .onFailure {
                                            state = NotifState.Failed(readableFailure(it))
                                        }
                                    working = working - n.id
                                    attempt++
                                }
                            },
                            request = incoming,
                            onRespond = { f, accept ->
                                working = working + n.id
                                scope.launch {
                                    runCatching { Rex.respondToFriendRequest(f.id, accept) }
                                        .onFailure {
                                            state = NotifState.Failed(readableFailure(it))
                                        }
                                    working = working - n.id
                                    attempt++
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

private sealed interface NotifState {
    data object Loading : NotifState
    data class Loaded(
        val rows: List<RexNotification>,
        val itemIds: Map<String, String>,
        val friendships: List<Friendship>,
    ) : NotifState
    data class Failed(val message: String) : NotifState
}

@Composable
private fun NotificationRow(
    notification: RexNotification,
    busy: Boolean,
    onOpen: () -> Unit,
    onDelete: () -> Unit,
    request: Friendship?,
    onRespond: (Friendship, Boolean) -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(16.dp))
            // Unread reads as a tint on the whole row as well as the dot. The
            // dot alone is easy to miss on a phone held at arm's length.
            .background(if (notification.isUnread) RexColor.badgeBackground else RexColor.card)
            .clickable(onClick = onOpen)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Avatar(notification.actor?.avatarUrl, notification.actor?.username ?: "?")
        Spacer(Modifier.size(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                notification.copy,
                fontSize = 14.sp,
                color = RexColor.foreground,
                fontWeight = if (notification.isUnread) FontWeight.Medium else FontWeight.Normal,
            )
            Text(
                ago(notification.createdAt),
                fontSize = 12.sp,
                color = RexColor.mutedForeground,
            )
        }

        if (busy) {
            CircularProgressIndicator(color = RexColor.primary, modifier = Modifier.size(18.dp))
        } else if (request != null) {
            // Answerable here, which is the whole point of a friend-request
            // notification: iOS added this because going to Friends to accept
            // was two taps behind the thing telling you about it.
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                RoundAction(Icons.Outlined.Check, "Accept", RexColor.primary, RexColor.primaryForeground) {
                    onRespond(request, true)
                }
                RoundAction(Icons.Outlined.Close, "Decline", RexColor.card, RexColor.foreground) {
                    onRespond(request, false)
                }
            }
        } else {
            // "I've no way to X them" (Danny, 15 September). Your own
            // notifications are yours to delete.
            IconButton(onClick = onDelete, modifier = Modifier.size(32.dp)) {
                Icon(
                    Icons.Outlined.Close,
                    contentDescription = "Remove",
                    tint = RexColor.placeholder,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

@Composable
private fun Avatar(url: String?, name: String) {
    val clean = url?.takeIf { it.isNotBlank() }
    Box(
        Modifier.size(38.dp).clip(CircleShape).background(RexColor.secondary),
        contentAlignment = Alignment.Center,
    ) {
        // Subcompose rather than plain AsyncImage, so a failed load falls back
        // to the initial instead of an empty circle. See the note in
        // ProfileScreen — found by running it, not by compiling it.
        val initial = @Composable {
            Text(
                name.take(1).uppercase(),
                fontSize = 15.sp,
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
private fun RoundAction(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    background: androidx.compose.ui.graphics.Color,
    tint: androidx.compose.ui.graphics.Color,
    onClick: () -> Unit,
) {
    Box(
        Modifier.size(32.dp).clip(CircleShape).background(background).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(16.dp))
    }
}

/**
 * "3 hours ago", near enough.
 *
 * Postgres hands timestamps back as "…+00:00", which Instant.parse will not
 * take, so this goes through OffsetDateTime and falls back to an empty string
 * rather than throwing inside a list row.
 */
private fun ago(iso: String): String {
    val then = runCatching { OffsetDateTime.parse(iso).toInstant() }
        .recoverCatching { Instant.parse(iso) }
        .getOrNull() ?: return ""
    val d = Duration.between(then, Instant.now())
    val mins = d.toMinutes()
    // Nov 17, from the emulator: this read "1 days ago". iOS gets plurals free
    // from RelativeDateTimeFormatter; Kotlin does not, and the day and week
    // branches are the two that can land on one.
    fun plural(n: Long, unit: String) = "$n $unit${if (n == 1L) "" else "s"} ago"
    return when {
        mins < 1 -> "Just now"
        mins < 60 -> "$mins min ago"
        d.toHours() < 24 -> "${d.toHours()} hr ago"
        d.toDays() < 7 -> plural(d.toDays(), "day")
        else -> plural(d.toDays() / 7, "week")
    }
}

@Composable
private fun Empty() {
    Column(
        Modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(56.dp))
        Text(
            "Nothing yet",
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = RexColor.foreground,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            "Likes, comments and friend requests will show up here.",
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
            "Couldn't load your notifications",
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
