package com.marcocheung.wherecanigo.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF0B57D0),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD3E3FD),
    onPrimaryContainer = Color(0xFF0842A0),
    secondary = Color(0xFF526581),
    secondaryContainer = Color(0xFFE1EAF9),
    onSecondaryContainer = Color(0xFF263B58),
    background = Color(0xFFF8FAFF),
    onBackground = Color(0xFF202124),
    surface = Color.White,
    onSurface = Color(0xFF202124),
    surfaceContainer = Color(0xFFEEF3FC),
    surfaceContainerLow = Color(0xFFF3F6FC),
    surfaceContainerHigh = Color(0xFFE7EEF9),
    surfaceContainerHighest = Color(0xFFDFE6F2),
    surfaceContainerLowest = Color.White,
    surfaceVariant = Color(0xFFE1E7F0),
    onSurfaceVariant = Color(0xFF566171),
    outline = Color(0xFF747E8E),
    outlineVariant = Color(0xFFC4CDDB),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFA8C7FA),
    onPrimary = Color(0xFF062E6F),
    primaryContainer = Color(0xFF284777),
    onPrimaryContainer = Color(0xFFD3E3FD),
    secondary = Color(0xFFB9C7DE),
    secondaryContainer = Color(0xFF35445B),
    onSecondaryContainer = Color(0xFFDCE6F9),
    background = Color(0xFF111318),
    onBackground = Color(0xFFE3E3E8),
    surface = Color(0xFF111318),
    onSurface = Color(0xFFE3E3E8),
    surfaceContainer = Color(0xFF20242C),
    surfaceContainerLow = Color(0xFF1B1B1F),
    surfaceContainerHigh = Color(0xFF292E38),
    surfaceContainerHighest = Color(0xFF343A46),
    surfaceContainerLowest = Color(0xFF0C0F14),
    surfaceVariant = Color(0xFF414754),
    onSurfaceVariant = Color(0xFFBFC7D5),
    outline = Color(0xFF8993A3),
    outlineVariant = Color(0xFF414754),
)

@Composable
fun WhereCanIGoTheme(darkTheme: Boolean, content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}
