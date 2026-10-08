package com.kathrynfinnis.rex.ui.map

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.kathrynfinnis.rex.ui.theme.RexColor

/** Placeholder. The iOS equivalent is MapView; none of it is ported yet. */
@Composable
fun MapScreen() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text("Map", color = RexColor.mutedForeground)
    }
}
