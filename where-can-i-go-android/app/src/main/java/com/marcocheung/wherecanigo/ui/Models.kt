package com.marcocheung.wherecanigo.ui

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.ui.graphics.Color
import com.marcocheung.wherecanigo.R
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

val SupportedPassports = setOf("CHN", "HKG", "MAC", "TWN")

enum class VisaCategory(
    val jsonValue: String,
    @param:StringRes val label: Int,
    val color: Color,
) {
    VisaFree("visa_free", R.string.visa_free, Color(0.16f, 0.42f, 0.42f)),
    VisaOnArrival("visa_on_arrival", R.string.visa_on_arrival, Color(0.28f, 0.55f, 0.55f)),
    Eta("eta", R.string.eta, Color(0.38f, 0.62f, 0.68f)),
    MyVisa("my_visa", R.string.my_visa, Color(0.55f, 0.72f, 0.58f)),
    VisaRequired("visa_required", R.string.visa_required, Color(0.85f, 0.85f, 0.85f)),
    ;

    companion object {
        fun fromJson(value: String): VisaCategory =
            entries.firstOrNull { it.jsonValue == value } ?: throw JSONException("Unknown category: $value")
    }
}

enum class Continent(@param:StringRes val label: Int) {
    Africa(R.string.africa),
    Asia(R.string.asia),
    Europe(R.string.europe),
    NorthAmerica(R.string.north_america),
    SouthAmerica(R.string.south_america),
    Oceania(R.string.oceania),
    ;

    companion object {
        private val lookup: Map<String, Continent> = buildMap {
            fun add(continent: Continent, codes: String) = codes.split(",").forEach { put(it, continent) }
            add(Africa, "DZA,AGO,BEN,BWA,BFA,BDI,CPV,CMR,CAF,TCD,COM,COG,COD,DJI,EGY,GNQ,ERI,SWZ,ETH,GAB,GMB,GHA,GIN,GNB,CIV,KEN,LSO,LBR,LBY,MDG,MWI,MLI,MRT,MUS,MAR,MOZ,NAM,NER,NGA,RWA,STP,SEN,SYC,SLE,SOM,ZAF,SSD,SDN,TZA,TGO,TUN,UGA,ZMB,ZWE")
            add(Asia, "AFG,ARM,AZE,BHR,BGD,BTN,BRN,KHM,CHN,CYP,GEO,IND,IDN,IRN,IRQ,ISR,JPN,JOR,KAZ,KWT,KGZ,LAO,LBN,MYS,MDV,MNG,MMR,NPL,PRK,OMN,PAK,PSE,PHL,QAT,SAU,SGP,KOR,LKA,SYR,TWN,TJK,THA,TLS,TUR,TKM,ARE,UZB,VNM,YEM")
            add(Europe, "ALB,AND,AUT,BLR,BEL,BIH,BGR,HRV,CZE,DNK,EST,FIN,FRA,DEU,GRC,HUN,ISL,IRL,ITA,XKX,LVA,LIE,LTU,LUX,MLT,MDA,MCO,MNE,NLD,MKD,NOR,POL,PRT,ROU,RUS,SMR,SRB,SVK,SVN,ESP,SWE,CHE,UKR,GBR,VAT")
            add(NorthAmerica, "ATG,BHS,BRB,BLZ,CAN,CRI,CUB,DMA,DOM,SLV,GRD,GTM,HTI,HND,JAM,MEX,NIC,PAN,KNA,LCA,VCT,TTO,USA")
            add(SouthAmerica, "ARG,BOL,BRA,CHL,COL,ECU,GUY,PRY,PER,SUR,URY,VEN")
            add(Oceania, "AUS,FJI,KIR,MHL,FSM,NRU,NZL,PLW,PNG,WSM,SLB,TON,TUV,VUT")
        }

        /** Same fallback as iOS: HKG and MAC count as Asia. */
        fun of(code: String): Continent? =
            lookup[code.uppercase()] ?: if (code == "HKG" || code == "MAC") Asia else null
    }
}

data class Country(
    val code: String,
    val iso2: String,
    val name: String,
    val flag: String,
) {
    fun localizedName(locale: Locale): String =
        Locale.Builder().setRegion(iso2).build().getDisplayCountry(locale).ifBlank { name }

    fun matches(search: String, locale: Locale): Boolean =
        search.isBlank() || localizedName(locale).contains(search, ignoreCase = true) ||
            name.contains(search, ignoreCase = true)
}

data class DefaultVisaEntry(
    val countryCode: String,
    val category: VisaCategory,
    val duration: String?,
    val remark: String?,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("countryCode", countryCode)
        .put("category", category.jsonValue)
        .put("duration", duration ?: JSONObject.NULL)
        .put("remark", remark ?: JSONObject.NULL)

    companion object {
        private val durationPrefix = Regex(
            """^(?:(?:up to|maximum) )?\d+(?: to \d+)? (?:days?|weeks?|months?)(?: to \d+ (?:days?|weeks?|months?))?(?: within \d+ (?:days?|months?)| per (?:visit|calendar year))?(?![a-z])""",
            RegexOption.IGNORE_CASE,
        )

        fun fromJson(json: JSONObject): DefaultVisaEntry {
            val stored = json.nullableString("duration")
            val (duration, remark) = if (json.has("remark")) stored to json.nullableString("remark")
                else splitLegacyDuration(stored)
            return DefaultVisaEntry(json.getString("countryCode"), VisaCategory.fromJson(json.getString("category")), duration, remark)
        }

        private fun splitLegacyDuration(value: String?): Pair<String?, String?> {
            if (value.isNullOrEmpty()) return value to null
            when (value) {
                "Home Sweet Home" -> return null to value
                "2 weeks (single entry) or 1 month (multiple entry)" -> return "2 weeks or 1 month" to value
                "45 days under Guam-CNMI waiver with prior authorization and direct Taiwan flight; or 90 days with ESTA" ->
                    return "45 days or 90 days" to value
                "Conditional visa-free: 30 days for tourist groups of 5+ with prepaid hotel and return tickets" ->
                    return "30 days" to value
            }
            val durations = mutableListOf<String>()
            val remarks = mutableListOf<String>()
            val parts = value.split(";")
            parts.map(String::trim).filter(String::isNotEmpty).forEach { text ->
                val prefix = durationPrefix.find(text)
                when {
                    text.equals("varies", true) || text.equals("stay varies", true) -> durations.add("varies")
                    prefix != null -> {
                        durations.add(prefix.value)
                        text.substring(prefix.value.length).trim().takeIf(String::isNotEmpty)?.let(remarks::add)
                    }
                    else -> remarks.add(text)
                }
            }
            if (durations.isEmpty() && parts.size == 1 && !value.contains("required", true)) return value to null
            return durations.takeIf { it.isNotEmpty() }?.joinToString("; ") to
                remarks.takeIf { it.isNotEmpty() }?.joinToString("; ")
        }
    }
}

data class BundledEntryPolicy(val updatedAt: LocalDate?, val entries: List<DefaultVisaEntry>)

enum class VisaCoverage(val jsonValue: String) {
    IssuingCountry("issuing_country"),
    SchengenArea("schengen_area"),
    ;

    companion object {
        val schengenCountryCodes = setOf(
            "AUT", "BEL", "BGR", "HRV", "CZE", "DNK", "EST", "FIN", "FRA", "DEU",
            "GRC", "HUN", "ISL", "ITA", "LVA", "LIE", "LTU", "LUX", "MLT", "NLD",
            "NOR", "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE", "CHE",
        )
    }
}

data class PersonalVisa(
    val id: String,
    val countryCode: String,
    val visaType: String,
    val duration: String,
    val expiryDate: LocalDate,
    val effectiveDate: LocalDate? = null,
    val notes: String? = null,
    val attachmentFileNames: List<String> = emptyList(),
    val coverage: VisaCoverage = VisaCoverage.IssuingCountry,
) {
    fun covers(code: String): Boolean =
        countryCode == code || (coverage == VisaCoverage.SchengenArea && code in VisaCoverage.schengenCountryCodes)

    fun isValid(on: LocalDate): Boolean = !expiryDate.isBefore(on) && (effectiveDate?.let { !it.isAfter(on) } ?: true)

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("countryCode", countryCode)
        put("visaType", visaType)
        put("duration", duration)
        put("expiryDate", expiryDate.toIsoInstant())
        effectiveDate?.let { put("effectiveDate", it.toIsoInstant()) }
        notes?.let { put("notes", it) }
        put("attachmentFileNames", JSONArray(attachmentFileNames))
        put("coverage", coverage.jsonValue)
    }

    companion object {
        fun newId(): String = UUID.randomUUID().toString().uppercase()

        fun create(
            id: String,
            countryCode: String,
            visaType: String,
            duration: String,
            expiryDate: LocalDate,
            effectiveDate: LocalDate?,
            notes: String?,
            attachmentFileNames: List<String>,
            coverage: VisaCoverage,
        ) = PersonalVisa(
            id, countryCode, visaType, duration, expiryDate, effectiveDate, notes, attachmentFileNames,
            if (countryCode in VisaCoverage.schengenCountryCodes) coverage else VisaCoverage.IssuingCountry,
        )

        fun fromJson(json: JSONObject): PersonalVisa {
            val names = json.optJSONArray("attachmentFileNames")
            return create(
                id = json.getString("id"),
                countryCode = json.getString("countryCode"),
                visaType = json.getString("visaType"),
                duration = json.getString("duration"),
                expiryDate = parseIsoDate(json.getString("expiryDate")),
                effectiveDate = json.nullableString("effectiveDate")?.let(::parseIsoDate),
                notes = json.nullableString("notes"),
                attachmentFileNames = names?.let { array -> List(array.length()) { array.getString(it) } }.orEmpty(),
                coverage = VisaCoverage.entries.firstOrNull { it.jsonValue == json.optString("coverage") }
                    ?: VisaCoverage.IssuingCountry,
            )
        }
    }
}

/** Mirrors iOS `AppData`; travel arrays retain the native JSON date representation. */
data class AppData(
    val passportCode: String,
    val defaultVisas: List<DefaultVisaEntry>,
    val personalVisas: List<PersonalVisa>,
    val visits: JSONArray = JSONArray(),
    val plannedTrips: JSONArray = JSONArray(),
) {
    val visitRecords get() = visits.objects().map { Visit.fromJson(it) }
    val plannedTripRecords get() = plannedTrips.objects().map { PlannedTrip.fromJson(it) }
    val visitedCountryCodes: Set<String>
        get() = (0 until visits.length()).mapNotNull { visits.optJSONObject(it)?.optString("countryCode") }.toSet()

    fun toJson(): JSONObject = JSONObject()
        .put("passportCode", passportCode)
        .put("defaultVisas", JSONArray(defaultVisas.map { it.toJson() }))
        .put("personalVisas", JSONArray(personalVisas.map { it.toJson() }))
        .put("visits", visits)
        .put("plannedTrips", plannedTrips)

    companion object {
        fun fromJson(json: JSONObject): AppData {
            val defaults = json.getJSONArray("defaultVisas")
            val personal = json.getJSONArray("personalVisas")
            return AppData(
                passportCode = json.getString("passportCode"),
                defaultVisas = List(defaults.length()) { DefaultVisaEntry.fromJson(defaults.getJSONObject(it)) },
                personalVisas = List(personal.length()) { PersonalVisa.fromJson(personal.getJSONObject(it)) },
                visits = json.optJSONArray("visits") ?: JSONArray(),
                plannedTrips = json.optJSONArray("plannedTrips") ?: JSONArray(),
            ).also { it.visitRecords; it.plannedTripRecords }
        }
    }
}

/** Port of iOS `VisaEligibility`. */
data class VisaEligibility(val category: VisaCategory, val sourceVisa: PersonalVisa?) {
    val isAccessible: Boolean
        get() = category == VisaCategory.VisaFree || category == VisaCategory.VisaOnArrival ||
            category == VisaCategory.MyVisa

    companion object {
        fun evaluate(
            countryCode: String,
            defaultCategory: VisaCategory,
            personalVisas: List<PersonalVisa>,
            date: LocalDate,
        ): VisaEligibility {
            if (defaultCategory == VisaCategory.VisaFree) return VisaEligibility(VisaCategory.VisaFree, null)
            val source = personalVisas
                .filter { it.covers(countryCode) && it.isValid(date) }
                .sortedWith(
                    compareBy<PersonalVisa> { it.countryCode != countryCode }
                        .thenByDescending { it.expiryDate }
                        .thenBy { it.id },
                )
                .firstOrNull()
            return VisaEligibility(if (source == null) defaultCategory else VisaCategory.MyVisa, source)
        }
    }
}

data class Airline(val id: String, val name: String, val destinationCountryCodes: Set<String>)

object BundledRepository {
    fun loadCountries(context: Context, locale: Locale): List<Country> {
        val data = context.assets.open("countries.json").bufferedReader().use { JSONArray(it.readText()) }
        return List(data.length()) {
            val country = data.getJSONObject(it)
            Country(
                code = country.getString("code"),
                iso2 = country.getString("iso2"),
                name = country.getString("name"),
                flag = country.getString("flag"),
            )
        }.sortedBy { it.localizedName(locale).lowercase(locale) }
    }

    fun loadPolicy(context: Context, passportCode: String): BundledEntryPolicy {
        val root = context.assets.open("default_visas_$passportCode.json")
            .bufferedReader().use { JSONObject(it.readText()) }
        val entries = root.getJSONArray("entries")
        return BundledEntryPolicy(
            updatedAt = root.nullableString("updatedAt")?.let(::parseIsoDateUtc),
            entries = List(entries.length()) { DefaultVisaEntry.fromJson(entries.getJSONObject(it)) },
        )
    }

    /** Mirrors iOS `AirlineRepository.decode` validation. */
    fun loadAirlines(context: Context): List<Airline> {
        val data = context.assets.open("airline_destinations.json").bufferedReader().use { JSONArray(it.readText()) }
        val airlines = List(data.length()) {
            val item = data.getJSONObject(it)
            val codes = item.getJSONArray("destinationCountryCodes")
            Airline(
                id = item.getString("id"),
                name = item.getString("name"),
                destinationCountryCodes = List(codes.length()) { index -> codes.getString(index) }.toSet(),
            )
        }
        val valid = airlines.isNotEmpty() && airlines.map { it.id }.toSet().size == airlines.size &&
            airlines.all { airline ->
                airline.id.isNotEmpty() && airline.name.isNotEmpty() && airline.destinationCountryCodes.isNotEmpty() &&
                    airline.destinationCountryCodes.all { code -> code.length == 3 && code.all { it in 'A'..'Z' } }
            }
        if (!valid) throw JSONException("Airlines must have unique IDs, names, and ISO3 destinations.")
        return airlines
    }
}

internal fun JSONObject.nullableString(key: String): String? = if (isNull(key)) null else getString(key)


internal fun parseIsoDate(value: String): LocalDate =
    Instant.parse(value).atZone(ZoneId.systemDefault()).toLocalDate()

private fun parseIsoDateUtc(value: String): LocalDate =
    runCatching { Instant.parse(value).atZone(ZoneId.of("UTC")).toLocalDate() }
        .getOrElse { LocalDate.parse(value.take(10)) }

internal fun LocalDate.toIsoInstant(): String = atStartOfDay(ZoneId.systemDefault()).toInstant().toString()
