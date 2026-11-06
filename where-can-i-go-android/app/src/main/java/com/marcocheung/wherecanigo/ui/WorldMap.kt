package com.marcocheung.wherecanigo.ui

import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import android.util.JsonReader
import android.util.JsonToken
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.IconButton
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.marcocheung.wherecanigo.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.style.layers.BackgroundLayer
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.FillLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.sources.GeoJsonSource
import org.json.JSONObject
import org.maplibre.android.style.layers.PropertyFactory
import java.io.IOException
import java.util.Locale

data class MapCountry(val code: String, val name: String)

/** A one-shot camera request; `id` makes repeated requests for the same country distinct. */
data class FlyRequest(val code: String, val id: Long = System.nanoTime())

private object CountryBounds {
    private var cache: Map<String, LatLngBounds>? = null

    /** Streams the GeoJSON so only four numbers per country stay in memory. */
    fun load(context: android.content.Context): Map<String, LatLngBounds> = cache ?: synchronized(this) {
        cache ?: buildMap {
            JsonReader(context.assets.open("world-countries.geojson").bufferedReader()).use { reader ->
                reader.beginObject()
                while (reader.hasNext()) {
                    if (reader.nextName() != "features") { reader.skipValue(); continue }
                    reader.beginArray()
                    while (reader.hasNext()) readFeature(reader)?.let { put(it.first, it.second) }
                    reader.endArray()
                }
                reader.endObject()
            }
        }.also { cache = it }
    }

    private fun readFeature(reader: JsonReader): Pair<String, LatLngBounds>? {
        var code: String? = null
        val box = DoubleArray(6) { if (it % 2 == 0) Double.MAX_VALUE else -Double.MAX_VALUE }
        reader.beginObject()
        while (reader.hasNext()) {
            when (reader.nextName()) {
                "properties" -> {
                    reader.beginObject()
                    while (reader.hasNext()) {
                        if (reader.nextName() == COUNTRY_CODE && reader.peek() == JsonToken.STRING) {
                            code = reader.nextString()
                        } else reader.skipValue()
                    }
                    reader.endObject()
                }
                "geometry" -> {
                    if (reader.peek() == JsonToken.NULL) { reader.nextNull(); continue }
                    reader.beginObject()
                    while (reader.hasNext()) {
                        if (reader.nextName() == "coordinates") readCoordinates(reader, box) else reader.skipValue()
                    }
                    reader.endObject()
                }
                else -> reader.skipValue()
            }
        }
        reader.endObject()
        if (code == null || box[0] == Double.MAX_VALUE) return null
        // box: minLat, maxLat, minLon, maxLon, minShiftedLon, maxShiftedLon (0..360, unwrapped for antimeridian countries)
        val (west, east) = if (box[3] - box[2] <= box[5] - box[4]) box[2] to box[3]
        else box[4] to box[5]
        return code to LatLngBounds.from(box[1], east, box[0], west)
    }

    private fun readCoordinates(reader: JsonReader, box: DoubleArray) {
        reader.beginArray()
        if (reader.peek() == JsonToken.NUMBER) {
            val lon = reader.nextDouble()
            val lat = reader.nextDouble()
            while (reader.hasNext()) reader.skipValue()
            val shifted = if (lon < 0) lon + 360 else lon
            box[0] = minOf(box[0], lat); box[1] = maxOf(box[1], lat)
            box[2] = minOf(box[2], lon); box[3] = maxOf(box[3], lon)
            box[4] = minOf(box[4], shifted); box[5] = maxOf(box[5], shifted)
        } else {
            while (reader.hasNext()) readCoordinates(reader, box)
        }
        reader.endArray()
    }
}

class MapCamera {
    var latitude by mutableDoubleStateOf(20.0)
    var longitude by mutableDoubleStateOf(15.0)
    var zoom by mutableDoubleStateOf(0.7)
    var bearing by mutableDoubleStateOf(0.0)

    companion object {
        val Saver = listSaver<MapCamera, Double>(
            save = { listOf(it.latitude, it.longitude, it.zoom, it.bearing) },
            restore = {
                MapCamera().apply {
                    latitude = it[0]
                    longitude = it[1]
                    zoom = it[2]
                    bearing = it[3]
                }
            },
        )
    }
}

private const val COUNTRY_CODE = "ISO3166-1-Alpha-3"
private const val STYLE = """{
  "version": 8,
  "sources": {
    "countries": {
      "type": "geojson",
      "data": "asset://world-countries.geojson",
      "attribution": "Natural Earth · Public domain / PDDL"
    }
  },
  "layers": [
    {"id":"ocean","type":"background","paint":{"background-color":"#d8e6f4"}},
    {"id":"land","type":"fill","source":"countries","paint":{"fill-color":"#7c8595"}},
    {"id":"visa-free","type":"fill","source":"countries","filter":["==","ISO3166-1-Alpha-3",""],
      "paint":{"fill-color":"#2e7d32"}},
    {"id":"visa-on-arrival","type":"fill","source":"countries","filter":["==","ISO3166-1-Alpha-3",""],
      "paint":{"fill-color":"#e65100"}},
    {"id":"my-visa","type":"fill","source":"countries","filter":["==","ISO3166-1-Alpha-3",""],
      "paint":{"fill-color":"#8cb894"}},
    {"id":"eta","type":"fill","source":"countries","filter":["==","ISO3166-1-Alpha-3",""],
      "paint":{"fill-color":"#0077b6"}},
    {"id":"borders","type":"line","source":"countries","paint":{"line-color":"#ffffff","line-width":0.7}},
    {"id":"selected","type":"line","source":"countries","filter":["==","ISO3166-1-Alpha-3",""],
      "paint":{"line-color":"#0b57d0","line-width":2.5}}
  ]
}"""

@Composable
fun WorldMap(
    camera: MapCamera,
    selectedCode: String?,
    categoryByCode: Map<String, VisaCategory>,
    onCountrySelected: (MapCountry) -> Unit,
    modifier: Modifier = Modifier,
    flyRequest: FlyRequest? = null,
    cameraBottomPadding: androidx.compose.ui.unit.Dp = 0.dp,
    visitedCodes: Set<String> = emptySet(),
    overlay: @Composable BoxScope.() -> Unit = {},
) {
    if (LocalInspectionMode.current) {
        Box(modifier) { Text(stringResource(R.string.map_preview)) }
        return
    }
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val onSelected by rememberUpdatedState(onCountrySelected)
    val selection by rememberUpdatedState(selectedCode)
    var loading by remember { mutableStateOf(true) }
    var rendered by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var retry by remember { mutableStateOf(0) }
    var countryNames by remember { mutableStateOf<Map<String, String>?>(null) }
    val currentLocale = LocalConfiguration.current.locales[0]
    val mapError by rememberUpdatedState(stringResource(R.string.map_error))
    val zoomInDescription = stringResource(R.string.zoom_in)
    val zoomOutDescription = stringResource(R.string.zoom_out)
    val colors = MaterialTheme.colorScheme
    val ocean = colors.surfaceContainerHigh.toArgb()
    val border = colors.surface.toArgb()
    val highlight = colors.primary.toArgb()
    var nativeMap by remember { mutableStateOf<MapLibreMap?>(null) }

    LaunchedEffect(retry, currentLocale) {
        try {
            countryNames = withContext(Dispatchers.IO) {
                // Let the native renderer parse geometry; a second Java copy exhausts small device heaps.
                context.assets.open("world-countries.geojson").use {
                    require(it.read() != -1) {
                        "Bundled country geometry is empty"
                    }
                }
                val data = context.assets.open("countries.json").bufferedReader().use {
                    JSONArray(it.readText())
                }
                buildMap {
                    for (index in 0 until data.length()) {
                        val country = data.getJSONObject(index)
                        val localized = Locale.Builder().setRegion(country.getString("iso2"))
                            .build().getDisplayCountry(currentLocale)
                        put(country.getString("code"), localized.ifBlank { country.getString("name") })
                    }
                }
            }
            error = null
        } catch (failure: IOException) {
            Log.e("WorldMap", "Cannot read bundled map", failure)
            error = mapError
            loading = false
        } catch (failure: IllegalArgumentException) {
            Log.e("WorldMap", "Invalid bundled geometry", failure)
            error = mapError
            loading = false
        } catch (failure: org.json.JSONException) {
            Log.e("WorldMap", "Invalid bundled country names", failure)
            error = mapError
            loading = false
        }
    }

    val mapView = remember(context, retry) {
        MapLibre.getInstance(context)
        MapView(context).apply { onCreate(null) }
    }
    LaunchedEffect(countryNames, selectedCode) {
        selectedCode?.let { code ->
            countryNames?.get(code)?.let { name -> onSelected(MapCountry(code, name)) }
        }
    }
    DisposableEffect(mapView, lifecycle) {
        var started = false
        var resumed = false
        fun syncLifecycle() {
            val shouldStart = lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
            val shouldResume = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
            if (resumed && !shouldResume) {
                mapView.onPause()
                resumed = false
            }
            if (started && !shouldStart) {
                mapView.onStop()
                started = false
            }
            if (!started && shouldStart) {
                mapView.onStart()
                started = true
            }
            if (!resumed && shouldResume) {
                mapView.onResume()
                resumed = true
            }
        }
        val observer = LifecycleEventObserver { _, _ -> syncLifecycle() }
        val memoryCallback = object : ComponentCallbacks2 {
            override fun onConfigurationChanged(newConfig: Configuration) = Unit
            override fun onLowMemory() = mapView.onLowMemory()
            override fun onTrimMemory(level: Int) {
                if (level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) mapView.onLowMemory()
            }
        }
        lifecycle.addObserver(observer)
        context.registerComponentCallbacks(memoryCallback)
        syncLifecycle()
        onDispose {
            lifecycle.removeObserver(observer)
            context.unregisterComponentCallbacks(memoryCallback)
            if (resumed) mapView.onPause()
            if (started) mapView.onStop()
            nativeMap = null
            mapView.onDestroy()
        }
    }

    LaunchedEffect(mapView, countryNames != null) {
        if (countryNames == null || error != null) return@LaunchedEffect
        loading = true
        rendered = false
        mapView.addOnDidFinishRenderingMapListener { fully ->
            if (fully) rendered = true
        }
        mapView.addOnDidFailLoadingMapListener { message ->
            Log.e("WorldMap", "Map loading failed: $message")
            error = mapError
            loading = false
        }
        mapView.getMapAsync { map ->
            nativeMap = map
            map.uiSettings.apply {
                isLogoEnabled = false
                isAttributionEnabled = false
                isTiltGesturesEnabled = false
            }
            map.cameraPosition = CameraPosition.Builder()
                .target(LatLng(camera.latitude, camera.longitude)).zoom(camera.zoom).bearing(camera.bearing).build()
            map.addOnCameraIdleListener {
                val position = map.cameraPosition
                position.target?.let {
                    camera.latitude = it.latitude
                    camera.longitude = it.longitude
                }
                camera.zoom = position.zoom
                camera.bearing = position.bearing
            }
            map.addOnMapClickListener { point ->
                val features = map.queryRenderedFeatures(map.projection.toScreenLocation(point), "visited-markers", "land")
                val country = features.firstOrNull {
                    it.hasProperty(COUNTRY_CODE) &&
                        countryNames?.containsKey(it.getStringProperty(COUNTRY_CODE)) == true
                }
                if (country != null) {
                    val code = country.getStringProperty(COUNTRY_CODE)
                    countryNames?.get(code)?.let { onSelected(MapCountry(code, it)) }
                    true
                } else false
            }
            map.setStyle(Style.Builder().fromJson(STYLE)) {
                loading = false
                error = null
            }
        }
    }
    LaunchedEffect(nativeMap, selectedCode, categoryByCode, ocean, border, highlight, loading) {
        nativeMap?.style?.let { style ->
            style.getLayerAs<BackgroundLayer>("ocean")?.setProperties(PropertyFactory.backgroundColor(ocean))
            style.getLayerAs<FillLayer>("land")?.setProperties(PropertyFactory.fillColor(VisaCategory.VisaRequired.color.toArgb()))
            mapOf(
                VisaCategory.VisaFree to "visa-free",
                VisaCategory.VisaOnArrival to "visa-on-arrival",
                VisaCategory.MyVisa to "my-visa",
                VisaCategory.Eta to "eta",
            ).forEach { (category, layerId) ->
                val codes = categoryByCode.filterValues { it == category }.keys
                val filter = if (codes.isEmpty()) {
                    Expression.eq(Expression.get(COUNTRY_CODE), Expression.literal(""))
                } else {
                    Expression.`in`(Expression.get(COUNTRY_CODE), Expression.literal(codes.toList()))
                }
                style.getLayerAs<FillLayer>(layerId)?.apply {
                    setProperties(PropertyFactory.fillColor(category.color.toArgb()))
                    setFilter(filter)
                }
            }
            style.getLayerAs<LineLayer>("borders")?.setProperties(PropertyFactory.lineColor(border))
            style.getLayerAs<LineLayer>("selected")?.apply {
                setProperties(PropertyFactory.lineColor(highlight))
                setFilter(Expression.eq(Expression.get(COUNTRY_CODE), Expression.literal(selection ?: "")))
            }
        }
    }

    LaunchedEffect(nativeMap, loading, visitedCodes, highlight, border) {
        val map = nativeMap ?: return@LaunchedEffect
        if (loading) return@LaunchedEffect
        try {
            val markers = if (visitedCodes.isEmpty()) emptyMap() else withContext(Dispatchers.IO) {
                MiniMapOutlines.load(context).associate { it.code to it.marker }
            }
            val features = JSONArray(visitedCodes.mapNotNull { code ->
                markers[code]?.let { (longitude, latitude) ->
                    JSONObject().put("type", "Feature").put("properties", JSONObject().put(COUNTRY_CODE, code))
                        .put("geometry", JSONObject().put("type", "Point")
                            .put("coordinates", JSONArray(listOf(longitude, latitude))))
                }
            })
            map.style?.let { style ->
                val points = JSONObject().put("type", "FeatureCollection").put("features", features).toString()
                val source = style.getSourceAs<GeoJsonSource>("visited-countries")
                if (source == null) style.addSource(GeoJsonSource("visited-countries", points)) else source.setGeoJson(points)
                if (style.getLayer("visited-markers") == null) style.addLayer(CircleLayer("visited-markers", "visited-countries"))
                style.getLayerAs<CircleLayer>("visited-markers")?.setProperties(
                    PropertyFactory.circleRadius(5f), PropertyFactory.circleColor(highlight),
                    PropertyFactory.circleStrokeColor(border), PropertyFactory.circleStrokeWidth(2f))
            }
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (failure: Exception) { AppState.get(context).reportError(R.string.map_error, failure) }
    }

    LaunchedEffect(nativeMap, flyRequest, loading) {
        val request = flyRequest ?: return@LaunchedEffect
        val map = nativeMap ?: return@LaunchedEffect
        if (loading) return@LaunchedEffect
        val bounds = runCatching { withContext(Dispatchers.IO) { CountryBounds.load(context) } }
            .onFailure { Log.e("WorldMap", "Cannot compute country bounds", it) }
            .getOrNull()?.get(request.code) ?: return@LaunchedEffect
        val density = context.resources.displayMetrics.density
        val padding = (48 * density).toInt()
        val bottom = (padding + cameraBottomPadding.value * density).toInt()
            .coerceAtMost((mapView.height * 0.65f).toInt()).coerceAtLeast(padding)
        map.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, padding, padding, padding, bottom), 1200)
    }

    Box(
        modifier.testTag("world-map").semantics {
            stateDescription = "${camera.latitude},${camera.longitude},${camera.zoom}"
        },
    ) {
        key(mapView) {
            AndroidView(factory = { mapView }, modifier = Modifier.fillMaxSize())
        }
        if (!loading && rendered && error == null) {
            Surface(
                modifier = Modifier.align(Alignment.TopEnd).padding(top = 12.dp, end = 12.dp)
                    .testTag("map-controls"),
                shape = RoundedCornerShape(16.dp),
            ) {
                Column {
                    IconButton(onClick = { nativeMap?.animateCamera(CameraUpdateFactory.zoomIn()) },
                        modifier = Modifier.testTag("map-zoom-in")) {
                        Text("+", modifier = Modifier.semantics {
                            contentDescription = zoomInDescription
                        })
                    }
                    IconButton(onClick = { nativeMap?.animateCamera(CameraUpdateFactory.zoomOut()) },
                        modifier = Modifier.testTag("map-zoom-out")) {
                        Text("−", modifier = Modifier.semantics {
                            contentDescription = zoomOutDescription
                        })
                    }
                    IconButton(onClick = {
                        nativeMap?.animateCamera(
                            CameraUpdateFactory.newCameraPosition(
                                CameraPosition.Builder().target(LatLng(20.0, 15.0))
                                    .zoom(0.7).bearing(0.0).build(),
                            ),
                        )
                    }, modifier = Modifier.testTag("map-reset")) {
                        Icon(
                            androidx.compose.ui.res.painterResource(R.drawable.ic_globe),
                            contentDescription = stringResource(R.string.world_reset),
                        )
                    }
                }
            }
        }
        overlay()
        if (loading || error != null) {
            Surface(
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 12.dp, start = 16.dp, end = 16.dp),
                shape = RoundedCornerShape(20.dp),
            ) {
                Column(
                    Modifier.padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (error != null) {
                        Text(error!!, modifier = Modifier.testTag("map-error"))
                        TextButton(onClick = {
                            countryNames = null
                            error = null
                            loading = true
                            retry++
                        }) { Text(stringResource(R.string.retry)) }
                    } else {
                        CircularProgressIndicator(Modifier.size(24.dp))
                        Text(stringResource(R.string.map_loading))
                    }
                }
            }
        }
    }
}
