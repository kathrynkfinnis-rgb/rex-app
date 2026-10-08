package com.kathrynfinnis.rex.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Map
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.kathrynfinnis.rex.ui.collections.CollectionsScreen
import com.kathrynfinnis.rex.ui.explore.ExploreScreen
import com.kathrynfinnis.rex.ui.feed.FeedScreen
import com.kathrynfinnis.rex.ui.map.MapScreen
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

@Composable
fun RexRoot() {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val here = entry?.destination?.route

    Scaffold(
        containerColor = RexColor.background,
        bottomBar = {
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
            modifier = androidx.compose.ui.Modifier.padding(padding),
        ) {
            composable(Tab.Feed.route) { FeedScreen() }
            composable(Tab.Map.route) { MapScreen() }
            composable(Tab.Collections.route) { CollectionsScreen() }
            composable(Tab.Explore.route) { ExploreScreen() }
        }
    }
}
