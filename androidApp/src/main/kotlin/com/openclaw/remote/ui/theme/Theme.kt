package com.openclaw.remote.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

@Immutable
data class MochiColors(
    val background: Color,
    val surface: Color,
    val primary: Color,
    val onPrimary: Color,
    val secondary: Color,
    val onSecondary: Color,
    val accent: Color,
    val userBubble: Color,
    val userBubbleFg: Color,
    val assistantBg: Color,
    val assistantFg: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val divider: Color,
    val inputBg: Color,
    val inputBorder: Color,
    val inputText: Color,
    val inputPlaceholder: Color,
    val icon: Color,
    val onlineGreen: Color,
    val recordingRed: Color,
)

private val LightMochiColors = MochiColors(
    background         = LightBackground,
    surface            = LightSurface,
    primary            = LightPrimary,
    onPrimary          = LightOnPrimary,
    secondary          = LightSecondary,
    onSecondary        = LightOnSecondary,
    accent             = LightAccent,
    userBubble         = LightUserBubble,
    userBubbleFg       = LightUserBubbleFg,
    assistantBg        = LightAssistantBg,
    assistantFg        = LightAssistantFg,
    textPrimary        = LightTextPrimary,
    textSecondary      = LightTextSecondary,
    divider            = LightDivider,
    inputBg            = LightInputBg,
    inputBorder        = LightInputBorder,
    inputText          = LightInputText,
    inputPlaceholder   = LightInputPlaceholder,
    icon               = LightIcon,
    onlineGreen        = OnlineGreen,
    recordingRed       = RecordingRed,
)

private val DarkMochiColors = MochiColors(
    background         = DarkBackground,
    surface            = DarkSurface,
    primary            = DarkPrimary,
    onPrimary          = DarkOnPrimary,
    secondary          = DarkSecondary,
    onSecondary        = DarkOnSecondary,
    accent             = DarkAccent,
    userBubble         = DarkUserBubble,
    userBubbleFg       = DarkUserBubbleFg,
    assistantBg        = DarkAssistantBg,
    assistantFg        = DarkAssistantFg,
    textPrimary        = DarkTextPrimary,
    textSecondary      = DarkTextSecondary,
    divider            = DarkDivider,
    inputBg            = DarkInputBg,
    inputBorder        = DarkInputBorder,
    inputText          = DarkInputText,
    inputPlaceholder   = DarkInputPlaceholder,
    icon               = DarkIcon,
    onlineGreen        = OnlineGreen,
    recordingRed       = RecordingRed,
)

val LocalMochiColors = staticCompositionLocalOf { LightMochiColors }

@Composable
fun MochiTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val mochiColors = if (darkTheme) DarkMochiColors else LightMochiColors

    val colorScheme = if (darkTheme) {
        darkColorScheme(
            primary = mochiColors.primary,
            onPrimary = mochiColors.onPrimary,
            secondary = mochiColors.secondary,
            onSecondary = mochiColors.onSecondary,
            surface = mochiColors.surface,
            background = mochiColors.background,
        )
    } else {
        lightColorScheme(
            primary = mochiColors.primary,
            onPrimary = mochiColors.onPrimary,
            secondary = mochiColors.secondary,
            onSecondary = mochiColors.onSecondary,
            surface = mochiColors.surface,
            background = mochiColors.background,
        )
    }

    CompositionLocalProvider(LocalMochiColors provides mochiColors) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = MochiTypography,
            content = content
        )
    }
}

object MochiTheme {
    val colors: MochiColors
        @Composable
        get() = LocalMochiColors.current
}
