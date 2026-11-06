package com.marcocheung.wherecanigo

import android.os.SystemClock
import android.content.res.Configuration
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.test.platform.app.InstrumentationRegistry
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapView
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.Assume.assumeTrue

class InterfaceTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    @Before
    fun completePassportGate() {
        compose.waitForIdle()
        if (compose.onAllNodes(hasTestTag("passport-gate")).fetchSemanticsNodes().isNotEmpty()) {
            compose.onNodeWithTag("passport-HKG").performClick()
            compose.onNodeWithTag("use-passport").performClick()
            compose.onNodeWithTag("i-understand").performClick()
            compose.waitForIdle()
        }
    }

    @Test
    fun tabsChangePanelContent() {
        compose.onNodeWithTag("tab-Visas").performClick().assertIsSelected()
        expandIfCompact()
        compose.onNodeWithTag("content-Visas").assertIsDisplayed()
        compose.onNodeWithTag("tab-Travels").performClick().assertIsSelected()
        compose.onNodeWithTag("content-Travels").assertIsDisplayed()
        compose.onNodeWithTag("tab-Overview").performClick().assertIsSelected()
        compose.onNodeWithTag("content-Overview").assertIsDisplayed()
    }

    @Test
    fun appearanceFollowsSystemWithoutPanelControls() {
        compose.waitForIdle()
        compose.onNodeWithTag("appearance-menu").assertDoesNotExist()
        compose.onNodeWithTag("sheet-toggle").assertDoesNotExist()
        compose.onNodeWithTag("map-ready").assertDoesNotExist()
        compose.runOnUiThread {
            val darkTheme = compose.activity.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
            val controller = WindowCompat.getInsetsController(
                compose.activity.window,
                compose.activity.window.decorView,
            )
            assertEquals(!darkTheme, controller.isAppearanceLightStatusBars)
            assertEquals(!darkTheme, controller.isAppearanceLightNavigationBars)
        }
    }

    @Test
    fun selectedTabSurvivesActivityRecreation() {
        compose.onNodeWithTag("tab-Travels").performClick()
        compose.activityRule.scenario.recreate()
        compose.onNodeWithTag("tab-Travels").assertIsSelected()
    }

    @Test
    fun compactSheetCanExpandAndCollapse() {
        assumeTrue(
            compose.onAllNodes(hasTestTag("sheet-handle"))
                .fetchSemanticsNodes().isNotEmpty(),
        )
        expandIfCompact()
        compose.onNodeWithTag("content-Overview").assertIsDisplayed()
        compose.onNodeWithTag("sheet-handle").performSemanticsAction(SemanticsActions.Collapse) { it() }
        compose.onNodeWithTag("tab-Overview").assertIsDisplayed()
    }

    @Test
    fun searchFiltersCountryList() {
        expandIfCompact()
        compose.waitUntil(10_000) {
            compose.onAllNodes(hasTestTag("country-list")).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("country-search").performTextReplacement("Japan")
        compose.onNodeWithTag("result-count").assertIsDisplayed()
        compose.onNodeWithTag("country-list").performScrollToNode(hasTestTag("country-JPN"))
        compose.onNodeWithTag("country-JPN").assertIsDisplayed()
    }

    @Test
    fun passportIsInProfileAndSwitchingPreservesTheMapAndSearch() {
        waitForMap()
        expandIfCompact()
        compose.onNodeWithTag("country-search").performTextReplacement("Japan")
        val before = mapCamera()
        compose.onNodeWithTag("profile-button").performClick()
        compose.onNodeWithTag("menu-profile").performClick()
        compose.onNodeWithTag("page-profile").assertIsDisplayed()
        compose.onNodeWithTag("change-passport").performClick()
        compose.onNodeWithTag("passport-MAC").performClick()
        compose.onNodeWithTag("use-passport").performClick()
        compose.onNodeWithTag("profile-save").performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("country-search").assertTextContains("Japan")
        assertEquals(before, mapCamera())
        compose.onNodeWithTag("profile-button").performClick()
        compose.onNodeWithTag("menu-settings").performClick()
        compose.onNodeWithTag("page-settings").assertIsDisplayed()
        compose.onNodeWithTag("change-passport").assertDoesNotExist()
        compose.onNodeWithTag("page-back").performClick()
    }

    @Test
    fun diceOptionsAreNotInProfileMenu() {
        compose.onNodeWithTag("profile-button").performClick()
        compose.onNodeWithTag("menu-dice-options").assertDoesNotExist()
    }

    @Test
    fun profileCancelDiscardsNameAndPassportEdits() {
        val state = com.marcocheung.wherecanigo.ui.AppState.get(compose.activity)
        val original = state.profile.name
        val passport = state.data.passportCode
        compose.onNodeWithTag("profile-button").performClick()
        compose.onNodeWithTag("menu-profile").performClick()
        compose.onNodeWithTag("profile-name").performTextReplacement("Unsaved name")
        compose.onNodeWithTag("change-passport").performClick()
        compose.onNodeWithTag("passport-TWN").performClick()
        compose.onNodeWithTag("use-passport").performClick()
        compose.onNodeWithTag("page-back").performClick()
        assertEquals(original, state.profile.name)
        assertEquals(passport, state.data.passportCode)
    }

    @Test
    fun wishlistDraftSurvivesActivityRecreation() {
        compose.onNodeWithTag("tab-Travels").performClick()
        expandIfCompact()
        compose.onNodeWithTag("segment-Wishlist").performClick()
        compose.onNodeWithTag("travel-add").performClick()
        compose.onNodeWithTag("trip-notes").performScrollTo().performTextReplacement("Wishlist draft")
        compose.activityRule.scenario.recreate()
        compose.onNodeWithTag("trip-notes").performScrollTo().assertTextContains("Wishlist draft")
        compose.onNodeWithTag("sheet-cancel").performClick()
        compose.onNodeWithTag("segment-Wishlist").assertIsSelected()
    }

    @Test
    fun visaEditorDraftSurvivesActivityRecreation() {
        compose.onNodeWithTag("tab-Visas").performClick()
        expandIfCompact()
        compose.onNodeWithTag("draft-details").performClick()
        compose.onNodeWithTag("visa-type").performScrollTo().performTextReplacement("Multiple")
        compose.onNodeWithTag("visa-duration").performScrollTo().performTextReplacement("90 days")
        compose.activityRule.scenario.recreate()
        compose.onNodeWithTag("visa-details-sheet").assertIsDisplayed()
        compose.onNodeWithTag("visa-type").performScrollTo().assertTextContains("Multiple")
        compose.onNodeWithTag("visa-duration").performScrollTo().assertTextContains("90 days")
        compose.onNodeWithTag("sheet-cancel").performClick()
    }

    @Test
    fun offlineMapLoadsAndCameraResponds() {
        waitForMap()
        val before = mapCamera()
        compose.onNodeWithTag("map-zoom-in").performClick()
        compose.waitUntil(10_000) { mapCamera() != before }
        val zoomed = mapCamera()
        dragNativeMap()
        compose.waitUntil(10_000) { mapCamera() != zoomed }
        assertNotEquals(zoomed, mapCamera())
    }

    @Test
    fun mapCameraSurvivesActivityRecreation() {
        waitForMap()
        compose.onNodeWithTag("map-zoom-in").performClick()
        compose.waitUntil(10_000) { mapCamera().split(",").last().toDouble() > 0.8 }
        val before = mapCamera()
        compose.activityRule.scenario.recreate()
        waitForMap()
        val expected = before.split(",").map(String::toDouble)
        val restored = mapCamera().split(",").map(String::toDouble)
        expected.zip(restored).forEach { (saved, current) ->
            assertEquals(saved, current, 0.000001)
        }
    }

    @Test
    fun countryTapOpensDetailsAndReturnsToPanel() {
        waitForMap()
        var point: android.graphics.PointF? = null
        compose.runOnUiThread {
            fun findMap(view: View): MapView? {
                if (view is MapView) return view
                if (view is ViewGroup) {
                    for (index in 0 until view.childCount) {
                        findMap(view.getChildAt(index))?.let { return it }
                    }
                }
                return null
            }
            val view = requireNotNull(findMap(compose.activity.window.decorView))
            val screenOffset = IntArray(2)
            view.getLocationOnScreen(screenOffset)
            view.getMapAsync { map ->
                point = map.projection.toScreenLocation(LatLng(28.0, 2.0)).apply {
                    offset(screenOffset[0].toFloat(), screenOffset[1].toFloat())
                }
            }
        }
        compose.waitUntil(10_000) { point != null }
        val tap = requireNotNull(point)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val downTime = SystemClock.uptimeMillis()
        for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
            val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, tap.x, tap.y, 0)
            instrumentation.sendPointerSync(event)
            event.recycle()
            SystemClock.sleep(30)
        }
        compose.waitUntil(10_000) {
            compose.onAllNodes(hasTestTag("country-card"))
                .fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("country-card").assertIsDisplayed()
        compose.onNodeWithTag("country-close").performClick()
        compose.onNodeWithTag("content-Overview").assertIsDisplayed()
    }

    @Test
    fun gestureAreaMatchesNavigationSurfaceInCurrentSystemTheme() {
        compose.waitForIdle()
        SystemClock.sleep(300)
        var bottomInset = 0
        compose.runOnUiThread {
            bottomInset = ViewCompat.getRootWindowInsets(compose.activity.window.decorView)
                ?.getInsets(WindowInsetsCompat.Type.navigationBars())?.bottom ?: 0
        }
        assumeTrue(bottomInset > 0)
        val screenshot = requireNotNull(
            InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot(),
        )
        assertEquals(
            screenshot.getPixel(20, screenshot.height - bottomInset - 10),
            screenshot.getPixel(20, screenshot.height - 10),
        )
        screenshot.recycle()
    }

    private fun waitForMap() {
        compose.waitUntil(30_000) {
            compose.onAllNodes(hasTestTag("map-controls"))
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun mapCamera(): String =
        compose.onNodeWithTag("world-map").fetchSemanticsNode()
            .config[SemanticsProperties.StateDescription]

    private fun dragNativeMap() {
        // Native gesture recognition uses the device clock, not Compose's virtual animation clock.
        val bounds = compose.onNodeWithTag("world-map").fetchSemanticsNode().boundsInRoot
        val y = bounds.top + bounds.height * 0.35f
        val startX = bounds.left + bounds.width * 0.65f
        val endX = bounds.left + bounds.width * 0.25f
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val downTime = SystemClock.uptimeMillis()
        fun send(action: Int, x: Float) {
            val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, y, 0)
            instrumentation.sendPointerSync(event)
            event.recycle()
        }
        send(MotionEvent.ACTION_DOWN, startX)
        for (step in 1..20) {
            SystemClock.sleep(25)
            send(MotionEvent.ACTION_MOVE, startX + (endX - startX) * step / 20f)
        }
        send(MotionEvent.ACTION_UP, endX)
    }

    private fun expandIfCompact() {
        val handle = compose.onAllNodes(hasTestTag("sheet-handle")).fetchSemanticsNodes().firstOrNull()
        if (handle != null && SemanticsActions.Expand in handle.config) {
            compose.onNodeWithTag("sheet-handle").performSemanticsAction(SemanticsActions.Expand) { it() }
            compose.waitForIdle()
        }
    }
}
