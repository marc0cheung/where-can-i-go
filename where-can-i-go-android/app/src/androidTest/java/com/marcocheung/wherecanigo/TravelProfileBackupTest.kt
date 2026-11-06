package com.marcocheung.wherecanigo

import android.content.Context
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.test.platform.app.InstrumentationRegistry
import com.marcocheung.wherecanigo.ui.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.Instant
import java.time.LocalDate

class TravelProfileBackupTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val day = LocalDate.of(2026, 4, 1)
    private fun local() = AppData("HKG", BundledRepository.loadPolicy(context, "HKG").entries, emptyList())
    private fun isolated(block: (Context, File) -> Unit) {
        val folder = File(context.cacheDir, "backup-test-${PersonalVisa.newId()}").apply { check(mkdirs()) }
        val wrapped = object : ContextWrapper(context) {
            override fun getFilesDir() = folder
        }
        try { block(wrapped, folder) } finally { check(folder.deleteRecursively()) }
    }

    @Test
    fun visitsCountDaysInclusivelyAndPreservePartialDates() {
        assertEquals(1L, Visit(countryCode = "JPN", startDate = day, endDate = day).dayCount)
        assertEquals(3L, Visit(countryCode = "JPN", startDate = day, endDate = day.plusDays(2)).dayCount)
        assertNull(Visit(countryCode = "JPN", startDate = day).dayCount)
        val visit = Visit(countryCode = "JPN", startDate = day, purpose = VisitPurpose.family, notes = "Trip")
        assertEquals(visit, Visit.fromJson(visit.toJson()))
        assertEquals(visit, Visit.fromJson(visit.toJson(true), true))
        assertEquals(VisitPurpose.other, VisitPurpose.decode("future-purpose"))
    }

    @Test
    fun wishlistStatisticsExcludeEstimatedDurationsAndCompletionKeepsId() {
        val estimated = PlannedTrip(countryCode = "JPN", durationMode = PlannedDurationMode.estimatedDays,
            estimatedDays = Long.MAX_VALUE, location = "Tokyo", notes = "Plan")
        val dated = PlannedTrip(countryCode = "FRA", durationMode = PlannedDurationMode.dates,
            startDate = day, endDate = day.plusDays(3))
        assertEquals(4L, TravelStats.plans(listOf(estimated, dated)).totalDays)
        assertEquals(1, TravelStats.plans(listOf(estimated, dated)).datedTrips)
        assertEquals(estimated.id, estimated.visitDraft.id)
        assertEquals("Tokyo", estimated.visitDraft.location)
        assertNull(estimated.visitDraft.startDate)
        assertEquals(estimated, PlannedTrip.fromJson(estimated.toJson(true), true))
        assertFalse(TravelDraft(countryCode = "JPN", durationMode = PlannedDurationMode.estimatedDays,
            estimatedDays = "9223372036854775808").canSavePlan)
        assertFalse(TravelDraft(countryCode = "JPN", startDate = day.plusDays(1), endDate = day).canSaveVisit)
    }

    @Test
    fun profileCropProducesSquare512PhotoAtClampedOffsets() {
        val image = Bitmap.createBitmap(2048, 1024, Bitmap.Config.ARGB_8888)
        image.eraseColor(android.graphics.Color.RED)
        try {
            val bytes = cropProfilePhoto(image, ProfilePhotoCrop(6f, 100f, -100f))
            val output = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            try {
                assertEquals(512, output.width); assertEquals(512, output.height)
                assertTrue(android.graphics.Color.red(output.getPixel(0, 0)) > 240)
                assertTrue(android.graphics.Color.red(output.getPixel(511, 511)) > 240)
            } finally { output.recycle() }
            val profile = UserProfile(" Name ", bytes, bytes, ProfilePhotoCrop(2f, 0.1f, -0.1f))
            val restored = UserProfile.fromJson(profile.toJson())
            assertEquals("Name", restored.name)
            assertArrayEquals(bytes, restored.photoSourceData)
            assertEquals(profile.photoCrop, restored.photoCrop)
        } finally { image.recycle() }
    }

    @Test
    fun miniMapParsesActualPolygonAndMultiPolygonDataset() {
        val outlines = MiniMapOutlines.load(context)
        assertTrue(outlines.size > 150)
        assertFalse(outlines.first { it.code == "JPN" }.path.isEmpty)
        assertFalse(outlines.first { it.code == "FRA" }.path.isEmpty)
        val france = requireNotNull(outlines.first { it.code == "FRA" }.marker)
        assertTrue(france.first in -6.0..10.0 && france.second in 40.0..52.0)
    }

    @Test
    fun portableExportRoundTripsAndMergeIsIdempotent() {
        val visit = Visit(countryCode = "JPN", startDate = day, endDate = day.plusDays(2))
        val plan = PlannedTrip(countryCode = "FRA", createdAt = Instant.parse("2026-01-01T12:00:00Z"))
        val data = local().copy(visits = JSONArray(listOf(visit.toJson())), plannedTrips = JSONArray(listOf(plan.toJson())),
            defaultVisas = local().defaultVisas.filterNot { it.countryCode == "FRA" })
        val (bytes, skipped) = UserDataBackup.export(context, data, UserProfile("Marco"), false, false)
        assertEquals(0, skipped)
        val document = UserDataBackup.decode(bytes.inputStream())
        assertEquals(day.toString(), document.json.getJSONArray("visits").getJSONObject(0).getString("startDate"))
        val first = UserDataBackup.plan(context, document, local(), UserProfile(), true)
        assertEquals(listOf(visit), first.data.visitRecords)
        assertEquals(listOf(plan), first.data.plannedTripRecords)
        assertFalse(first.data.defaultVisas.any { it.countryCode == "FRA" })
        assertEquals("Marco", first.profile.name)
        val second = UserDataBackup.plan(context, document, first.data, first.profile, false)
        assertEquals(1, second.data.visitRecords.size)
        assertEquals(1, second.data.plannedTripRecords.size)
        assertEquals(2, second.skippedRecords)
    }

    @Test
    fun completedVisitResolvesWishlistFromEitherDevice() {
        val plan = PlannedTrip(countryCode = "JPN")
        val visit = plan.visitDraft.copy(startDate = day)
        val data = local().copy(plannedTrips = JSONArray(listOf(plan.toJson())))
        val document = UserDataBackup.decode(UserDataBackup.export(context, data, UserProfile(), false, false).first.inputStream())
        val local = local().copy(visits = JSONArray(listOf(visit.toJson())))
        val result = UserDataBackup.plan(context, document, local, UserProfile(), false)
        assertEquals(listOf(visit), result.data.visitRecords)
        assertTrue(result.data.plannedTripRecords.isEmpty())
    }

    @Test
    fun backupRejectsFriendsDuplicatesInvalidDatesAndTamperedMedia() {
        val visit = Visit(countryCode = "JPN", startDate = day)
        val data = local().copy(visits = JSONArray(listOf(visit.toJson())))
        val root = JSONObject(UserDataBackup.export(context, data, UserProfile(), false, false).first.toString(Charsets.UTF_8))
        fun rejected(json: JSONObject) {
            assertThrows(Exception::class.java) { UserDataBackup.decode(json.toString().byteInputStream()) }
        }
        val friends = JSONObject(root.toString()).put("sharingIdentity", JSONObject())
        assertThrows(FriendsBackupUnsupported::class.java) { UserDataBackup.decode(friends.toString().byteInputStream()) }
        val duplicates = JSONObject(root.toString())
        duplicates.getJSONArray("visits").put(duplicates.getJSONArray("visits").getJSONObject(0))
        rejected(duplicates)
        val badDate = JSONObject(root.toString())
        badDate.getJSONArray("visits").getJSONObject(0).put("startDate", "2026-02-30")
        rejected(badDate)
        val badMedia = JSONObject(root.toString())
        badMedia.getJSONObject("profile").put("photo", JSONObject().put("fileName", "photo.jpg")
            .put("byteCount", 3).put("sha256", "invalid").put("data", "YWJj"))
        rejected(badMedia)
    }

    @Test
    fun durableJournalRollsBackBothFilesAfterInterruptedCommit() = isolated { _, folder ->
        val app = File(folder, "app_data.json")
        val profile = File(folder, "user_profile.json")
        app.writeText("{\"old\":1}"); profile.writeText("{\"name\":\"Old\"}")
        val blockedTemp = File(folder, "user_profile.json.tmp").apply { check(mkdir()) }
        val blocker = File(blockedTemp, "block").apply { writeText("block") }
        assertThrows(Exception::class.java) {
            LocalStore.commit(folder, JSONObject().put("new", 2), JSONObject().put("name", "New"))
        }
        assertTrue(File(folder, "data_transaction.json").exists())
        check(blocker.delete()); check(blockedTemp.delete())
        LocalStore.recover(folder)
        assertEquals(1, JSONObject(app.readText()).getInt("old"))
        assertEquals("Old", JSONObject(profile.readText()).getString("name"))
        assertFalse(File(folder, "data_transaction.json").exists())
        LocalStore.commit(folder, JSONObject().put("new", 2), JSONObject().put("name", "New"))
        assertEquals(2, JSONObject(app.readText()).getInt("new"))
    }
}
