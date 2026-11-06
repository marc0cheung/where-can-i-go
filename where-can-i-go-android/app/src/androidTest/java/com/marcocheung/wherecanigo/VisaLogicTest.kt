package com.marcocheung.wherecanigo

import android.content.ContextWrapper
import androidx.compose.runtime.saveable.SaverScope
import androidx.test.platform.app.InstrumentationRegistry
import com.marcocheung.wherecanigo.ui.AppData
import com.marcocheung.wherecanigo.ui.BundledRepository
import com.marcocheung.wherecanigo.ui.DefaultVisaEntry
import com.marcocheung.wherecanigo.ui.PersonalVisa
import com.marcocheung.wherecanigo.ui.SupportedPassports
import com.marcocheung.wherecanigo.ui.VisaAttachmentStore
import com.marcocheung.wherecanigo.ui.VisaCategory
import com.marcocheung.wherecanigo.ui.VisaCoverage
import com.marcocheung.wherecanigo.ui.VisaDraft
import com.marcocheung.wherecanigo.ui.VisaEligibility
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.LocalDate
import java.util.Locale

class VisaLogicTest {
    private val today = LocalDate.of(2026, 11, 6)

    private fun visa(
        id: String = PersonalVisa.newId(),
        country: String = "FRA",
        expiry: LocalDate = today.plusYears(1),
        effective: LocalDate? = null,
        coverage: VisaCoverage = VisaCoverage.SchengenArea,
    ) = PersonalVisa.create(id, country, "Multiple", "90 days", expiry, effective, "Notes",
        listOf("photo.jpg", "document.pdf"), coverage)

    @Test
    fun validityIncludesBothBoundaryDates() {
        val valid = visa(expiry = today, effective = today)
        assertTrue(valid.isValid(today))
        assertFalse(valid.isValid(today.plusDays(1)))
        assertFalse(valid.isValid(today.minusDays(1)))
    }

    @Test
    fun eligibilityPrefersDirectThenLaterExpiryAndNeverOverridesVisaFree() {
        val schengen = visa(id = "A", expiry = today.plusYears(2))
        val direct = visa(id = "B", country = "DEU", expiry = today.plusMonths(1))
        val expired = visa(id = "C", country = "DEU", expiry = today.minusDays(1))
        val future = visa(id = "D", country = "DEU", effective = today.plusDays(1))
        val all = listOf(schengen, direct, expired, future)
        assertEquals(direct, VisaEligibility.evaluate("DEU", VisaCategory.VisaRequired, all, today).sourceVisa)
        assertEquals(schengen, VisaEligibility.evaluate("ITA", VisaCategory.VisaRequired, all, today).sourceVisa)
        assertEquals(VisaCategory.VisaFree, VisaEligibility.evaluate("DEU", VisaCategory.VisaFree, all, today).category)
        assertEquals(VisaCategory.VisaRequired,
            VisaEligibility.evaluate("DEU", VisaCategory.VisaRequired, listOf(expired, future), today).category)
        assertFalse(VisaEligibility(VisaCategory.Eta, null).isAccessible)
    }

    @Test
    fun changingToNonSchengenCountryRemovesAreaCoverage() {
        val japanese = visa(country = "JPN")
        assertEquals(VisaCoverage.IssuingCountry, japanese.coverage)
        assertFalse(japanese.covers("FRA"))
        assertTrue(japanese.covers("JPN"))
    }

    @Test
    fun jsonRoundTripPreservesVisaAndDeferredTravelData() {
        val personal = visa(effective = today)
        val data = AppData("HKG", emptyList(), listOf(personal),
            JSONArray().put(JSONObject().put("countryCode", "JPN").put("notes", "Keep me")),
            JSONArray().put(JSONObject().put("countryCode", "ITA").put("futureField", "Keep me too")))
        val restored = AppData.fromJson(JSONObject(data.toJson().toString()))
        assertEquals(personal, restored.personalVisas.single())
        assertEquals(setOf("JPN"), restored.visitedCountryCodes)
        assertEquals(data.visits.toString(), restored.visits.toString())
        assertEquals(data.plannedTrips.toString(), restored.plannedTrips.toString())
        assertEquals(setOf("passportCode", "defaultVisas", "personalVisas", "visits", "plannedTrips"),
            data.toJson().keys().asSequence().toSet())
    }

    @Test
    fun policyJsonKeepsExplicitNullsAndMigratesLegacyRemarksLikeIos() {
        val explicit = DefaultVisaEntry("JPN", VisaCategory.VisaFree, "30 days (single entry)", null)
        assertTrue(explicit.toJson().has("remark"))
        assertEquals(explicit, DefaultVisaEntry.fromJson(explicit.toJson()))
        val legacy = explicit.toJson().apply { remove("remark") }
        val restored = DefaultVisaEntry.fromJson(legacy)
        assertEquals("30 days", restored.duration)
        assertEquals("(single entry)", restored.remark)
    }

    @Test
    fun draftRestorationIncludesDatesCoverageAndAttachments() {
        val draft = VisaDraft.from(visa(effective = today))
        val scope = object : SaverScope {
            override fun canBeSaved(value: Any) = true
        }
        val saved = with(VisaDraft.Saver) { scope.save(draft) }
        assertEquals(draft, VisaDraft.Saver.restore(requireNotNull(saved)))
        assertTrue(draft.isComplete)
        assertFalse(draft.copy(effectiveDate = null).isComplete)
        assertFalse(draft.copy(effectiveDate = today.plusYears(2)).isComplete)
        assertTrue(draft.copy(hasEffectiveDate = false, effectiveDate = null).isComplete)
    }

    @Test
    fun bundledPoliciesUseTheSharedIosSchema() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val countries = BundledRepository.loadCountries(context, Locale.ENGLISH).map { it.code }.toSet()
        SupportedPassports.forEach { code ->
            val policy = BundledRepository.loadPolicy(context, code)
            assertTrue(policy.entries.isNotEmpty())
            assertEquals(policy.entries.size, policy.entries.map { it.countryCode }.toSet().size)
            assertTrue(policy.entries.all { it.countryCode in countries })
        }
        assertTrue(BundledRepository.loadAirlines(context).isNotEmpty())
    }

    @Test
    fun attachmentPruningKeepsOnlyCommittedFiles() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(base.cacheDir, "visa-test-${PersonalVisa.newId()}").apply { mkdirs() }
        val context = object : ContextWrapper(base) {
            override fun getFilesDir(): File = root
        }
        val id = PersonalVisa.newId()
        try {
            val kept = VisaAttachmentStore.save(context, byteArrayOf(1), "jpg", id)
            val discarded = VisaAttachmentStore.save(context, byteArrayOf(2), "pdf", id)
            VisaAttachmentStore.prune(context, id, setOf(kept))
            assertTrue(VisaAttachmentStore.file(context, kept, id).exists())
            assertFalse(VisaAttachmentStore.file(context, discarded, id).exists())
        } finally {
            VisaAttachmentStore.deleteFolder(context, id)
            File(root, "visa_attachments").delete()
            root.delete()
        }
    }
}
