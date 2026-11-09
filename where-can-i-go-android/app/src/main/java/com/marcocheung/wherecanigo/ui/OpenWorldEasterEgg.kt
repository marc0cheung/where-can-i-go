package com.marcocheung.wherecanigo.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.marcocheung.wherecanigo.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

@Composable
internal fun OpenWorldEasterEgg(onDismiss: () -> Unit) {
    val context = LocalContext.current
    var error by remember { mutableStateOf(false) }
    val outlines by produceState<List<MapOutline>?>(null) {
        try {
            value = withContext(Dispatchers.IO) { MiniMapOutlines.load(context) }
        } catch (_: Exception) {
            error = true
            value = emptyList()
        }
    }
    var openCodes by remember { mutableStateOf(emptySet<String>()) }
    var showMessage by remember { mutableStateOf(false) }
    BackHandler(onBack = onDismiss)
    LaunchedEffect(outlines) {
        val countries = outlines.orEmpty()
        if (countries.isEmpty()) {
            showMessage = true
            return@LaunchedEffect
        }
        delay(500)
        val batchSize = (countries.size / 40.0).toInt().coerceAtLeast(1)
        countries.shuffled().chunked(batchSize).forEach { batch ->
            openCodes = openCodes + batch.map { it.code }
            delay(60)
        }
        showMessage = true
    }
    val messageAlpha by animateFloatAsState(if (showMessage) 1f else 0f, label = "easter-egg-message")
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            Modifier.fillMaxSize().background(
                Brush.linearGradient(listOf(Color(0xFF123B3B), Color(0xFF17283D), Color(0xFF30234A))),
            ),
        ) {
            Column(
                Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.SpaceBetween,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    IconButton(onClick = onDismiss) {
                        AppIcon(R.drawable.ic_close, tint = Color.White)
                    }
                }
                if (error) {
                    Text(stringResource(R.string.map_error), color = Color.White, textAlign = TextAlign.Center)
                } else {
                    Canvas(Modifier.fillMaxWidth().height(220.dp)) {
                        scale(size.width / 360f, size.height / 180f, pivot = Offset.Zero) {
                            outlines.orEmpty().forEach { country ->
                                drawPath(
                                    country.path,
                                    if (country.code in openCodes) Color(0xFF5CCF85) else Color.White.copy(alpha = 0.18f),
                                )
                            }
                        }
                    }
                }
                Column(
                    Modifier.padding(horizontal = 8.dp).alpha(messageAlpha),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Text(
                        stringResource(R.string.easteregg_message),
                        style = MaterialTheme.typography.headlineSmall,
                        color = Color.White,
                        textAlign = TextAlign.Center,
                    )
                    Text(
                        stringResource(R.string.easteregg_subtitle),
                        style = MaterialTheme.typography.bodyLarge,
                        color = Color.White.copy(alpha = 0.78f),
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.size(4.dp))
                    Text("——${stringResource(R.string.app_name)}", color = Color.White.copy(alpha = 0.55f))
                }
                Spacer(Modifier.height(48.dp))
            }
        }
    }
}
