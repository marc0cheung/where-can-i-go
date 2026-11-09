package com.marcocheung.wherecanigo.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp

/** Space the floating navigation bar occupies over the bottom of the phone panel. */
val LocalSheetBottomPadding = compositionLocalOf { 0.dp }

/**
 * Lets the active tab report how much of its top content must stay visible in the
 * collapsed (peek) panel, e.g. the first row of Overview stat cards.
 */
val LocalPeekContentReporter = staticCompositionLocalOf<(Dp) -> Unit> { {} }

/** Gap between items of a Material 3 Expressive grouped list. */
val GroupedListGap = 2.dp

/** A rounded, inset popup surface shared by all app menus. */
@Composable
fun AppDropdownMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismissRequest,
        modifier = modifier.widthIn(min = 200.dp, max = 320.dp),
        offset = DpOffset(0.dp, 8.dp),
        shape = RoundedCornerShape(20.dp),
        content = content,
    )
}

private val GroupOuterCorner = 20.dp
private val GroupInnerCorner = 4.dp

/** Shape of item [index] in a grouped list of [count] items: large outer corners, small inner ones. */
fun groupedShape(index: Int, count: Int): Shape {
    val top = if (index == 0) GroupOuterCorner else GroupInnerCorner
    val bottom = if (index == count - 1) GroupOuterCorner else GroupInnerCorner
    return RoundedCornerShape(topStart = top, topEnd = top, bottomStart = bottom, bottomEnd = bottom)
}

/** Container colour for list items / cards placed on the panel's surfaceContainer. */
@Composable
fun listItemColor() = MaterialTheme.colorScheme.surfaceContainerLowest

@Composable
fun EmptyState(icon: Int, title: String, body: String? = null, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.secondaryContainer) {
            Box(Modifier.size(64.dp), contentAlignment = Alignment.Center) {
                AppIcon(icon, Modifier.size(28.dp), tint = MaterialTheme.colorScheme.onSecondaryContainer)
            }
        }
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        if (body != null) {
            Text(
                body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}
