package com.kathrynfinnis.rex.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Map
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.kathrynfinnis.rex.data.RexAuth
import com.kathrynfinnis.rex.ui.add.AddRexScreen
import com.kathrynfinnis.rex.ui.auth.AuthScreen
import com.kathrynfinnis.rex.ui.collections.CollectionDetail
import com.kathrynfinnis.rex.ui.collections.CollectionsList
import com.kathrynfinnis.rex.ui.explore.ExploreScreen
import com.kathrynfinnis.rex.ui.feed.FeedList
import com.kathrynfinnis.rex.ui.friends.FriendsScreen
import com.kathrynfinnis.rex.ui.item.ItemDetailScreen
import com.kathrynfinnis.rex.ui.map.MapScreen
import com.kathrynfinnis.rex.ui.profile.MyProfileScreen
import com.kathrynfinnis.rex.ui.profile.UserProfileScreen
import com.kathrynfinnis.rex.ui.theme.RexColor

/**
 * The four tabs iOS has, in the same order: Feed, Map, Collections, Explore.
 *
 * Friends and Profile are deliberately not tabs, for the reason MainTabView
 * records from 15 September — an iPhone tab bar holds five, and anything past
 * that goes into a system "More" tab with its own navigation bar, which is
 * what gave Danny two back arrows. Android has no such limit, but the two
 * apps should navigate the same way, and the decision was right regardless.
 */
private enum class Tab(val route: String, val label: String, val icon: ImageVector) {
    Feed("feed", "Feed", Icons.Outlined.Home),
    Map("map", "Map", Icons.Outlined.Map),
    Collections("collections", "Collections", Icons.Outlined.Bookmark),
    Explore("explore", "Explore", Icons.Outlined.Search),
}

/**
 * Nov 2 — the gate, written by hand after the five screens were built in
 * parallel. None of them could do this: a screen that owns navigation has to
 * know about every other screen, which is exactly the file five agents must
 * not all edit at once.
 *
 * Three states, not two. The SDK reads a stored session from disk at launch
 * and is briefly neither signed in nor signed out, and AuthScreen's own
 * contract says the caller must not show it during that window — without the
 * third state the app flashes a login at somebody already signed in, every
 * single launch.
 */
@Composable
fun RexRoot() {
    val resolving by RexAuth.isResolving.collectAsState(initial = true)
    val signedIn by RexAuth.isSignedIn.collectAsState(initial = false)

    when {
        resolving -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator(color = RexColor.primary)
        }
        // No onSignedIn callback needed: isSignedIn flips at the same moment,
        // and routing on both would navigate twice — the auth screen's notes
        // warn about exactly that.
        !signedIn -> AuthScreen(onSignedIn = {})
        else -> SignedIn()
    }
}

@Composable
private fun SignedIn() {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val here = entry?.destination?.route

    // The tab bar and the add button belong to the tabs, not to a pushed
    // screen: an item opened from the feed should not offer "add a Rex" over
    // the top of itself.
    val onTab = Tab.entries.any { it.route == here }

    Scaffold(
        containerColor = RexColor.background,
        // Nov 17 — the app had no top bar at all, which was fine while every
        // screen was a tab and is not once Friends exists. iOS reaches Friends
        // from the feed's toolbar; this is the same affordance in the same
        // place. Profile joins it as the next port, which is why it is a Row
        // rather than a single button.
        topBar = {
            if (!onTab) return@Scaffold
            Row(
                Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Spacer(Modifier.weight(1f))
                IconButton(onClick = { nav.navigate("friends") }) {
                    Icon(
                        Icons.Outlined.People,
                        contentDescription = "Friends",
                        tint = RexColor.foreground,
                    )
                }
                IconButton(onClick = { nav.navigate("me") }) {
                    Icon(
                        Icons.Outlined.AccountCircle,
                        contentDescription = "Your profile",
                        tint = RexColor.foreground,
                    )
                }
            }
        },
        floatingActionButton = {
            if (onTab) {
                FloatingActionButton(
                    onClick = { nav.navigate("add") },
                    containerColor = RexColor.primary,
                    contentColor = RexColor.primaryForeground,
                ) {
                    Icon(Icons.Outlined.Add, contentDescription = "Add a Rex")
                }
            }
        },
        bottomBar = {
            if (!onTab) return@Scaffold
            NavigationBar(containerColor = RexColor.card) {
                Tab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = here == tab.route,
                        onClick = {
                            nav.navigate(tab.route) {
                                popUpTo(Tab.Feed.route) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                        label = { Text(tab.label) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = RexColor.primary,
                            selectedTextColor = RexColor.primary,
                            unselectedIconColor = RexColor.mutedForeground,
                            unselectedTextColor = RexColor.mutedForeground,
                            indicatorColor = RexColor.badgeBackground,
                        ),
                    )
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = nav,
            startDestination = Tab.Feed.route,
            modifier = Modifier.padding(padding),
        ) {
            // FeedList rather than FeedScreen: the stub is still there and
            // still compiles, but the card written this morning is the one
            // that opens an item. The stub goes when nothing references it.
            composable(Tab.Feed.route) {
                FeedList(onOpenItem = { nav.navigate("item/$it") })
            }
            composable(Tab.Map.route) { MapScreen() }
            composable(Tab.Collections.route) {
                CollectionsList(onOpenCollection = { id, name ->
                    // The name rides in the route so the detail screen has a
                    // title before its first query returns. Encoded because a
                    // collection called "Books / films" would otherwise be two
                    // path segments and match nothing.
                    nav.navigate("collection/$id/${java.net.URLEncoder.encode(name, "UTF-8")}")
                })
            }
            composable(Tab.Explore.route) { ExploreScreen() }

            composable(
                "item/{itemId}",
                arguments = listOf(navArgument("itemId") { type = NavType.StringType }),
            ) { backStack ->
                ItemDetailScreen(
                    itemId = backStack.arguments?.getString("itemId").orEmpty(),
                    onBack = { nav.popBackStack() },
                )
            }

            composable(
                "collection/{listId}/{name}",
                arguments = listOf(
                    navArgument("listId") { type = NavType.StringType },
                    navArgument("name") { type = NavType.StringType },
                ),
            ) { backStack ->
                CollectionDetail(
                    listId = backStack.arguments?.getString("listId").orEmpty(),
                    name = java.net.URLDecoder.decode(
                        backStack.arguments?.getString("name").orEmpty(), "UTF-8",
                    ),
                    onBack = { nav.popBackStack() },
                    onOpenItem = { nav.navigate("item/$it") },
                )
            }

            // Not a tab, for the reason in the Tab comment above: the two apps
            // should navigate the same way, and on iOS Friends is a push from
            // the feed's toolbar rather than a fifth tab.
            //
            composable("friends") {
                FriendsScreen(
                    onBack = { nav.popBackStack() },
                    // Live as of 17 November. The rows were built to expect
                    // this and deliberately did not navigate until the profile
                    // screen existed.
                    onOpenProfile = { id, name ->
                        nav.navigate("user/$id/${java.net.URLEncoder.encode(name, "UTF-8")}")
                    },
                )
            }

            composable("me") {
                MyProfileScreen(
                    onBack = { nav.popBackStack() },
                    onOpenItem = { nav.navigate("item/$it") },
                    onOpenFriends = { nav.navigate("friends") },
                )
            }

            composable(
                "user/{userId}/{name}",
                arguments = listOf(
                    navArgument("userId") { type = NavType.StringType },
                    navArgument("name") { type = NavType.StringType },
                ),
            ) { backStack ->
                UserProfileScreen(
                    userId = backStack.arguments?.getString("userId").orEmpty(),
                    // Encoded for the same reason a collection's name is: a
                    // display name with a slash in it would otherwise be two
                    // path segments and match nothing.
                    fallbackName = java.net.URLDecoder.decode(
                        backStack.arguments?.getString("name").orEmpty(), "UTF-8",
                    ),
                    onBack = { nav.popBackStack() },
                    onOpenItem = { nav.navigate("item/$it") },
                )
            }

            composable("add") {
                AddRexScreen(
                    // Back to where they were, not to the feed: somebody who
                    // added a Rex from Collections meant to be in Collections.
                    onSaved = { nav.popBackStack() },
                    onCancel = { nav.popBackStack() },
                )
            }
        }
    }
}
