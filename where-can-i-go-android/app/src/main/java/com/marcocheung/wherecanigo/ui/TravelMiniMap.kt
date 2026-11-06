package com.marcocheung.wherecanigo.ui

import android.util.JsonReader
import android.util.JsonToken
import android.util.Log
import androidx.compose.foundation.Canvas
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.marcocheung.wherecanigo.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

internal data class MapOutline(val code: String, val path: Path, val marker: Pair<Double, Double>?)
internal object MiniMapOutlines {
    private var cached: List<MapOutline>? = null
    @Synchronized
    fun load(context: android.content.Context): List<MapOutline> {
        cached?.let { return it }
        val outlines = mutableListOf<MapOutline>()
        JsonReader(context.assets.open("world-countries.geojson").reader()).use { reader ->
            reader.beginObject()
            while (reader.hasNext()) {
                if (reader.nextName() != "features") { reader.skipValue(); continue }
                reader.beginArray()
                while (reader.hasNext()) {
                    var code = ""
                    val path = Path()
                    var mainRing = emptyList<Pair<Float, Float>>()
                    var largestArea = 0.0
                    reader.beginObject()
                    while (reader.hasNext()) when (reader.nextName()) {
                        "properties" -> {
                            reader.beginObject()
                            while (reader.hasNext()) {
                                if (reader.nextName() == "ISO3166-1-Alpha-3" && reader.peek() == JsonToken.STRING) code = reader.nextString()
                                else reader.skipValue()
                            }
                            reader.endObject()
                        }
                        "geometry" -> {
                            if (reader.peek() == JsonToken.NULL) { reader.skipValue(); continue }
                            reader.beginObject()
                            while (reader.hasNext()) {
                                if (reader.nextName() == "coordinates") readRings(reader, path) { ring ->
                                    val area = kotlin.math.abs(ring.indices.sumOf { index ->
                                        val a = ring[index]; val b = ring[(index + 1) % ring.size]
                                        a.first.toDouble() * b.second - b.first.toDouble() * a.second
                                    })
                                    if (area > largestArea) { largestArea = area; mainRing = ring }
                                } else reader.skipValue()
                            }
                            reader.endObject()
                        }
                        else -> reader.skipValue()
                    }
                    reader.endObject()
                    if (code.isNotEmpty()) outlines.add(MapOutline(code, path, representativePoint(mainRing)))
                }
                reader.endArray()
            }
            reader.endObject()
        }
        cached = outlines
        return outlines
    }

    private fun readRings(reader: JsonReader, path: Path, onRing: (List<Pair<Float, Float>>) -> Unit): Pair<Float, Float>? {
        reader.beginArray()
        if (reader.peek() == JsonToken.NUMBER) {
            val point = reader.nextDouble().toFloat() to reader.nextDouble().toFloat()
            while (reader.hasNext()) reader.skipValue()
            reader.endArray()
            return point
        }
        var started = false
        var previousLongitude = 0f
        val ring = mutableListOf<Pair<Float, Float>>()
        while (reader.hasNext()) {
            readRings(reader, path, onRing)?.let { (longitude, latitude) ->
                if (!started || kotlin.math.abs(longitude - previousLongitude) > 180) {
                    path.moveTo(longitude + 180, 90 - latitude)
                } else path.lineTo(longitude + 180, 90 - latitude)
                started = true
                previousLongitude = longitude
                var unwrapped = longitude
                ring.lastOrNull()?.let { previous ->
                    while (unwrapped - previous.first > 180) unwrapped -= 360
                    while (unwrapped - previous.first < -180) unwrapped += 360
                }
                ring.add(unwrapped to latitude)
            }
        }
        if (started) path.close()
        if (ring.size >= 3) onRing(ring)
        reader.endArray()
        return null
    }

    private fun representativePoint(ring: List<Pair<Float, Float>>): Pair<Double, Double>? {
        if (ring.isEmpty()) return null
        fun inside(x: Double, y: Double): Boolean {
            var result = false
            ring.indices.forEach { index ->
                val a = ring[index]; val b = ring[(index + 1) % ring.size]
                if ((a.second > y) != (b.second > y) &&
                    x < (b.first - a.first) * (y - a.second) / (b.second - a.second) + a.first) result = !result
            }
            return result
        }
        val west = ring.minOf { it.first }.toDouble(); val east = ring.maxOf { it.first }.toDouble()
        val south = ring.minOf { it.second }.toDouble(); val north = ring.maxOf { it.second }.toDouble()
        var best = (west + east) / 2 to (south + north) / 2
        if (!inside(best.first, best.second)) {
            var clearance = -1.0
            for (row in 0 until 16) for (column in 0 until 16) {
                val x = west + (column + 0.5) * (east - west) / 16
                val y = south + (row + 0.5) * (north - south) / 16
                if (!inside(x, y)) continue
                val distance = ring.indices.minOf { index ->
                    val a = ring[index]; val b = ring[(index + 1) % ring.size]
                    val dx = (b.first - a.first).toDouble(); val dy = (b.second - a.second).toDouble()
                    val t = if (dx * dx + dy * dy == 0.0) 0.0 else
                        (((x - a.first) * dx + (y - a.second) * dy) / (dx * dx + dy * dy)).coerceIn(0.0, 1.0)
                    val px = x - a.first - t * dx; val py = y - a.second - t * dy
                    px * px + py * py
                }
                if (distance > clearance) { clearance = distance; best = x to y }
            }
            if (clearance < 0) best = ring.first().let { it.first.toDouble() to it.second.toDouble() }
        }
        return ((best.first + 540) % 360 - 180) to best.second
    }
}

@Composable
fun TravelMiniMap(visited: Set<String>, modifier: Modifier, onReady: () -> Unit = {}) {
    val context = LocalContext.current
    var failed by remember { mutableStateOf(false) }
    val outlines by produceState<List<MapOutline>>(emptyList()) {
        value = withContext(Dispatchers.IO) {
            runCatching { MiniMapOutlines.load(context) }
                .onFailure { Log.e("TravelMap", "Cannot load travel summary map", it) }.getOrDefault(emptyList())
        }
        failed = value.isEmpty()
    }
    val land = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.22f)
    val highlight = MaterialTheme.colorScheme.onPrimaryContainer
    val ready by androidx.compose.runtime.rememberUpdatedState(onReady)
    androidx.compose.runtime.LaunchedEffect(outlines) {
        if (outlines.isNotEmpty()) {
            androidx.compose.runtime.withFrameNanos { }
            androidx.compose.runtime.withFrameNanos { }
            ready()
        }
    }
    if (failed) Text(stringResource(R.string.map_error))
    else Canvas(modifier) {
        scale(size.width / 360f, size.height / 180f, pivot = androidx.compose.ui.geometry.Offset.Zero) {
            outlines.forEach { drawPath(it.path, if (it.code in visited) highlight else land) }
        }
    }
}
