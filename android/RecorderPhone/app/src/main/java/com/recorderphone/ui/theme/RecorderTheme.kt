/*
 * RecorderPhone — Material 3 theme mapping example (Jetpack Compose)
 *
 * Source of truth:
 * - ../../../../../../design-tokens.json (themes + tokens)
 *
 * Notes:
 * - Material 3's `primaryContainer` expects an opaque color; `accent.soft` in tokens is an alpha overlay.
 *   This sample pre-blends `accent` over the target surface to produce an opaque container color.
 */
package com.recorderphone.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private object RecorderTokens {
    object Light {
        val Bg0 = Color(0xFFFFFFFF)
        val Bg1 = Color(0xFFF6F7F9)
        val Surface0 = Color(0xFFFFFFFF)
        val Surface1 = Color(0xFFF2F3F5)
        val Border0 = Color(0xFFE6E8EC)

        val Text0 = Color(0xFF0B0F1A)
        val Text1 = Color(0xFF3B4252)
        val Text2 = Color(0xFF6B7280)

        val Accent0 = Color(0xFF2F80ED)
        val Accent1 = Color(0xFF1B5FD6)
        val AccentContainer = Color(0xFFE6F0FD) // 12% Accent0 over white.

        val Success = Color(0xFF22C55E)
        val Warning = Color(0xFFF59E0B)
        val Danger = Color(0xFFEF4444)
        val Info = Color(0xFF38BDF8)
        val ErrorContainer = Color(0xFFFDE9E9) // 12% Danger over white.
    }

    object Dark {
        val Bg0 = Color(0xFF0B0F1A)
        val Bg1 = Color(0xFF0F1624)
        val Surface0 = Color(0xFF111A2B)
        val Surface1 = Color(0xFF162238)
        val Border0 = Color(0xFF22314D)

        val Text0 = Color(0xFFF3F6FF)
        val Text1 = Color(0xFFC7D0E0)
        val Text2 = Color(0xFF93A3BD)

        val Accent0 = Color(0xFF2F80ED)
        val Accent1 = Color(0xFF1B5FD6)
        val AccentContainer = Color(0xFF162C4E) // 18% Accent0 over Surface0.

        val Success = Color(0xFF22C55E)
        val Warning = Color(0xFFF59E0B)
        val Danger = Color(0xFFEF4444)
        val Info = Color(0xFF38BDF8)
        val ErrorContainer = Color(0xFF392230) // 18% Danger over Surface0.
    }
}

private val RecorderLightColorScheme = lightColorScheme(
    primary = RecorderTokens.Light.Accent0,
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = RecorderTokens.Light.AccentContainer,
    onPrimaryContainer = RecorderTokens.Light.Text0,
    secondary = RecorderTokens.Light.Accent0,
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = RecorderTokens.Light.AccentContainer,
    onSecondaryContainer = RecorderTokens.Light.Text0,
    background = RecorderTokens.Light.Bg0,
    onBackground = RecorderTokens.Light.Text0,
    surface = RecorderTokens.Light.Surface0,
    onSurface = RecorderTokens.Light.Text0,
    surfaceVariant = RecorderTokens.Light.Surface1,
    onSurfaceVariant = RecorderTokens.Light.Text1,
    outline = RecorderTokens.Light.Border0,
    error = RecorderTokens.Light.Danger,
    onError = Color(0xFFFFFFFF),
    errorContainer = RecorderTokens.Light.ErrorContainer,
    onErrorContainer = RecorderTokens.Light.Text0
)

private val RecorderDarkColorScheme = darkColorScheme(
    primary = RecorderTokens.Dark.Accent0,
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = RecorderTokens.Dark.AccentContainer,
    onPrimaryContainer = RecorderTokens.Dark.Text0,
    secondary = RecorderTokens.Dark.Accent0,
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = RecorderTokens.Dark.AccentContainer,
    onSecondaryContainer = RecorderTokens.Dark.Text0,
    background = RecorderTokens.Dark.Bg0,
    onBackground = RecorderTokens.Dark.Text0,
    surface = RecorderTokens.Dark.Surface0,
    onSurface = RecorderTokens.Dark.Text0,
    surfaceVariant = RecorderTokens.Dark.Surface1,
    onSurfaceVariant = RecorderTokens.Dark.Text1,
    outline = RecorderTokens.Dark.Border0,
    error = RecorderTokens.Dark.Danger,
    onError = Color(0xFFFFFFFF),
    errorContainer = RecorderTokens.Dark.ErrorContainer,
    onErrorContainer = RecorderTokens.Dark.Text0
)

private val RecorderShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(16.dp)
)

private val RecorderTypography = Typography(
    titleLarge = TextStyle(
        fontSize = 22.sp,
        lineHeight = 28.sp,
        fontWeight = FontWeight.SemiBold
    ),
    titleMedium = TextStyle(
        fontSize = 18.sp,
        lineHeight = 24.sp,
        fontWeight = FontWeight.SemiBold
    ),
    bodyLarge = TextStyle(
        fontSize = 15.sp,
        lineHeight = 22.sp,
        fontWeight = FontWeight.Normal
    ),
    bodyMedium = TextStyle(
        fontSize = 15.sp,
        lineHeight = 22.sp,
        fontWeight = FontWeight.Normal
    ),
    labelMedium = TextStyle(
        fontSize = 13.sp,
        lineHeight = 18.sp,
        fontWeight = FontWeight.Normal
    )
)

@Composable
fun RecorderTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = if (darkTheme) RecorderDarkColorScheme else RecorderLightColorScheme,
        typography = RecorderTypography,
        shapes = RecorderShapes,
        content = content
    )
}

