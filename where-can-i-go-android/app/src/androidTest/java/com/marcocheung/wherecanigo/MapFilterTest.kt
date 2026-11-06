package com.marcocheung.wherecanigo

import androidx.test.platform.app.InstrumentationRegistry
import com.marcocheung.wherecanigo.ui.countryCodeFilter
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Test
import org.maplibre.android.MapLibre
import org.maplibre.android.style.layers.FillLayer

class MapFilterTest {
    @Test
    fun countryFiltersSerializeAndRoundTripThroughNativeLayers() {
        val cases = listOf(emptySet(), setOf("JPN"), linkedSetOf("JPN", "FRA", "DEU"))
        for (codes in cases) {
            val filter = countryCodeFilter(codes)
            val json = JSONArray(filter.toString())
            assertEquals(if (codes.isEmpty()) "==" else "in", json.getString(0))
            assertEquals("get", json.getJSONArray(1).getString(0))
            assertEquals("ISO3166-1-Alpha-3", json.getJSONArray(1).getString(1))
            if (codes.isEmpty()) {
                assertEquals("", json.getString(2))
            } else {
                val literal = json.getJSONArray(2)
                assertEquals("literal", literal.getString(0))
                val values = literal.getJSONArray(1)
                assertEquals(codes.toList(), (0 until values.length()).map(values::getString))
            }

            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.runOnMainSync {
                MapLibre.getInstance(instrumentation.targetContext)
                val layer = FillLayer("filter-regression", "countries")
                layer.setFilter(filter)
                assertEquals(filter.toString(), requireNotNull(layer.filter).toString())
            }
        }
    }
}
