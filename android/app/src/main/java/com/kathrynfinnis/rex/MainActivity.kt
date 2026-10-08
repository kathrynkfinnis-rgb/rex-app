package com.kathrynfinnis.rex

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.kathrynfinnis.rex.ui.RexRoot
import com.kathrynfinnis.rex.ui.theme.RexTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            RexTheme { RexRoot() }
        }
    }
}
