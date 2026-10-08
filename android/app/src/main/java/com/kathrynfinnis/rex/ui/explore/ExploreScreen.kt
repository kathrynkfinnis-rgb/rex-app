package com.kathrynfinnis.rex.ui.explore

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.kathrynfinnis.rex.ui.theme.RexColor

/** Placeholder. The iOS equivalent is ExploreView; none of it is ported yet. */
@Composable
fun ExploreScreen() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text("Explore", color = RexColor.mutedForeground)
    }
}
