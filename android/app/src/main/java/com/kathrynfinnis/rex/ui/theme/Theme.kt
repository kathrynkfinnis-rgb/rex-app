package com.kathrynfinnis.rex.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Ported straight from the iOS Theme.swift so the two apps are the same app.
 * The hex values are copied, not re-picked — a colour that drifts by one step
 * between platforms is the kind of thing nobody notices until a screenshot
 * from one sits next to a screenshot from the other.
 */
object RexColor {
    val primary = Color(0xFF173626)          // Forest Green
    val primaryPressed = Color(0xFF10271C)
    val primaryForeground = Color(0xFFFFFFFF)
    val moss = Color(0xFF4D6B56)             // Secondary Green

    val background = Color(0xFFF8F8F5)       // Warm White
    val card = Color(0xFFFFFFFF)
    val border = Color(0xFFE2E5DE)
    val divider = Color(0xFFECEEE8)

    val foreground = Color(0xFF1D1D1D)       // Charcoal
    val mutedForeground = Color(0xFF666A66)  // Soft Grey
    val placeholder = Color(0xFF9A9C98)
    val disabled = Color(0xFFBCBEB8)

    val success = Color(0xFF2E7D32)
    val warning = Color(0xFFC79A3B)
    val destructive = Color(0xFFB44A3A)

    val accent = Color(0xFFC79A3B)
    val gold = Color(0xFFC79A3B)

    val badgeBackground = Color(0xFFEEF1EC)
    val badgeForeground = Color(0xFF4D6B56)
    val secondary = Color(0xFFEEF1EC)
}

private val RexScheme = lightColorScheme(
    primary = RexColor.primary,
    onPrimary = RexColor.primaryForeground,
    secondary = RexColor.moss,
    background = RexColor.background,
    onBackground = RexColor.foreground,
    surface = RexColor.card,
    onSurface = RexColor.foreground,
    surfaceVariant = RexColor.secondary,
    onSurfaceVariant = RexColor.mutedForeground,
    outline = RexColor.border,
    error = RexColor.destructive,
)

/**
 * The iOS app pins itself to light (RootView's preferredColorScheme, and
 * SceneDelegate's overrideUserInterfaceStyle behind it). Matching that here
 * rather than inheriting the system is deliberate: a dark REX has never been
 * designed, and half-doing it would look worse than not having it.
 */
val RexTypography = Typography(
    headlineMedium = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 15.sp),
    bodyMedium = TextStyle(fontSize = 13.sp),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium),
)

@Composable
fun RexTheme(content: @Composable () -> Unit) {
    @Suppress("UNUSED_EXPRESSION") isSystemInDarkTheme()
    MaterialTheme(colorScheme = RexScheme, typography = RexTypography, content = content)
}
