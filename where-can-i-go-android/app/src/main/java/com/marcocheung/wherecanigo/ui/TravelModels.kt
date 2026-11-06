package com.marcocheung.wherecanigo.ui

import androidx.annotation.StringRes
import androidx.compose.runtime.saveable.listSaver
import com.marcocheung.wherecanigo.R
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit

enum class VisitPurpose(@param:StringRes val label: Int) {
    leisure(R.string.purpose_leisure), business(R.string.purpose_business), family(R.string.purpose_family),
    study(R.string.purpose_study), transit(R.string.purpose_transit), other(R.string.purpose_other);

    companion object {
        fun decode(value: String?) = if (value == null) leisure else entries.firstOrNull { it.name == value } ?: other
    }
}

enum class PlannedDurationMode(@param:StringRes val label: Int) {
    notSet(R.string.duration_not_set), estimatedDays(R.string.duration_estimate), dates(R.string.duration_dates);
    companion object {
        fun decode(value: String?) = entries.firstOrNull { it.name == value } ?: notSet
    }
}

data class Visit(
    val id: String = PersonalVisa.newId(),
    val countryCode: String,
    val startDate: LocalDate? = null,
    val endDate: LocalDate? = null,
    val purpose: VisitPurpose = VisitPurpose.leisure,
    val location: String? = null,
    val notes: String? = null,
) {
    val dayCount: Long? get() = if (startDate != null && endDate != null)
        ChronoUnit.DAYS.between(startDate, endDate).coerceAtLeast(0) + 1 else null

    fun toJson(portable: Boolean = false) = JSONObject().put("id", id).put("countryCode", countryCode)
        .putOpt("startDate", startDate?.let { if (portable) it.toString() else it.toIsoInstant() })
        .putOpt("endDate", endDate?.let { if (portable) it.toString() else it.toIsoInstant() })
        .put("purpose", purpose.name).putOpt("location", location?.trim()?.takeIf(String::isNotEmpty))
        .putOpt("notes", notes)

    companion object {
        fun fromJson(json: JSONObject, portable: Boolean = false) = Visit(
            id = json.getString("id"), countryCode = json.getString("countryCode"),
            startDate = json.nullableString("startDate")?.let { if (portable) LocalDate.parse(it) else parseIsoDate(it) },
            endDate = json.nullableString("endDate")?.let { if (portable) LocalDate.parse(it) else parseIsoDate(it) },
            purpose = VisitPurpose.decode(json.nullableString("purpose")), location = json.nullableString("location"),
            notes = json.nullableString("notes"),
        )
    }
}

data class PlannedTrip(
    val id: String = PersonalVisa.newId(),
    val countryCode: String,
    val createdAt: Instant = Instant.now(),
    val location: String? = null,
    val purpose: VisitPurpose = VisitPurpose.leisure,
    val notes: String? = null,
    val durationMode: PlannedDurationMode = PlannedDurationMode.notSet,
    val estimatedDays: Long? = null,
    val startDate: LocalDate? = null,
    val endDate: LocalDate? = null,
) {
    val plannedDayCount: Long? get() = when (durationMode) {
        PlannedDurationMode.notSet -> null
        PlannedDurationMode.estimatedDays -> estimatedDays?.takeIf { it > 0 }
        PlannedDurationMode.dates -> if (startDate != null && endDate != null && !endDate.isBefore(startDate))
            ChronoUnit.DAYS.between(startDate, endDate) + 1 else null
    }
    val visitDraft get() = Visit(id, countryCode, if (durationMode == PlannedDurationMode.dates) startDate else null,
        if (durationMode == PlannedDurationMode.dates) endDate else null, purpose, location, notes)

    fun toJson(portable: Boolean = false): JSONObject = visitDraft.toJson(portable).put("createdAt", createdAt.toString())
        .put("durationMode", durationMode.name).apply {
            if (durationMode == PlannedDurationMode.estimatedDays) putOpt("estimatedDays", estimatedDays)
        }

    companion object {
        fun fromJson(json: JSONObject, portable: Boolean = false): PlannedTrip {
            val visit = Visit.fromJson(json, portable)
            val mode = PlannedDurationMode.decode(json.nullableString("durationMode"))
            return PlannedTrip(visit.id, visit.countryCode, Instant.parse(json.getString("createdAt")),
                visit.location?.trim()?.takeIf(String::isNotEmpty), visit.purpose,
                visit.notes?.trim()?.takeIf(String::isNotEmpty), mode,
                if (mode == PlannedDurationMode.estimatedDays && !json.isNull("estimatedDays")) json.getLong("estimatedDays") else null,
                if (mode == PlannedDurationMode.dates) visit.startDate else null,
                if (mode == PlannedDurationMode.dates) visit.endDate else null)
        }
    }
}

data class TravelDraft(
    val id: String = PersonalVisa.newId(),
    val countryCode: String? = null,
    val createdAt: Instant = Instant.now(),
    val location: String = "",
    val purpose: VisitPurpose = VisitPurpose.leisure,
    val notes: String = "",
    val durationMode: PlannedDurationMode = PlannedDurationMode.notSet,
    val estimatedDays: String = "1",
    val startDate: LocalDate? = null,
    val endDate: LocalDate? = null,
) {
    val validDates get() = startDate == null || endDate == null || !endDate.isBefore(startDate)
    val canSaveVisit get() = countryCode != null && validDates
    val canSavePlan get() = countryCode != null && validDates &&
        (durationMode != PlannedDurationMode.estimatedDays || (estimatedDays.toLongOrNull() ?: 0) > 0)
    fun visit() = Visit(id, requireNotNull(countryCode), startDate, endDate, purpose,
        location.trim().takeIf(String::isNotEmpty), notes.takeIf { it.isNotBlank() })
    fun plan() = PlannedTrip(id, requireNotNull(countryCode), createdAt, location.trim().takeIf(String::isNotEmpty),
        purpose, notes.trim().takeIf(String::isNotEmpty), durationMode,
        if (durationMode == PlannedDurationMode.estimatedDays) estimatedDays.toLongOrNull() else null,
        if (durationMode == PlannedDurationMode.dates) startDate else null,
        if (durationMode == PlannedDurationMode.dates) endDate else null)

    companion object {
        fun from(visit: Visit) = TravelDraft(id = visit.id, countryCode = visit.countryCode, location = visit.location.orEmpty(),
            purpose = visit.purpose, notes = visit.notes.orEmpty(), startDate = visit.startDate, endDate = visit.endDate)
        fun from(plan: PlannedTrip) = TravelDraft(plan.id, plan.countryCode, plan.createdAt, plan.location.orEmpty(),
            plan.purpose, plan.notes.orEmpty(), plan.durationMode, plan.estimatedDays?.toString() ?: "1", plan.startDate, plan.endDate)
        val Saver = listSaver<TravelDraft, String>(
            save = { listOf(it.id, it.countryCode.orEmpty(), it.createdAt.toString(), it.location, it.purpose.name,
                it.notes, it.durationMode.name, it.estimatedDays, it.startDate?.toString().orEmpty(), it.endDate?.toString().orEmpty()) },
            restore = { TravelDraft(it[0], it[1].ifEmpty { null }, Instant.parse(it[2]), it[3], VisitPurpose.valueOf(it[4]),
                it[5], PlannedDurationMode.valueOf(it[6]), it[7], it[8].takeIf(String::isNotEmpty)?.let(LocalDate::parse),
                it[9].takeIf(String::isNotEmpty)?.let(LocalDate::parse)) },
        )
    }
}

data class TravelStats(val countryCodes: Set<String>, val tripCount: Int, val totalDays: Long,
    val continents: Set<Continent>, val firstTrip: LocalDate?, val lastTrip: LocalDate?, val datedTrips: Int) {
    companion object {
        fun visits(visits: List<Visit>) = build(visits.map { it.countryCode }, visits.map { it.dayCount }, visits.mapNotNull { it.startDate })
        fun plans(plans: List<PlannedTrip>) = build(plans.map { it.countryCode },
            plans.map { if (it.durationMode == PlannedDurationMode.dates) it.plannedDayCount else null }, emptyList())
        private fun build(codes: List<String>, days: List<Long?>, starts: List<LocalDate>) = TravelStats(
            codes.toSet(), codes.size, days.filterNotNull().fold(0L) { sum, day -> if (Long.MAX_VALUE - sum < day) Long.MAX_VALUE else sum + day },
            codes.mapNotNull(Continent::of).toSet(), starts.minOrNull(), starts.maxOrNull(), days.count { it != null })
    }
}

internal fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }
internal fun JSONArray.removingIds(ids: Set<String>) = JSONArray(objects().filterNot { it.getString("id") in ids })
internal fun JSONArray.upserting(id: String, json: JSONObject) = JSONArray(
    objects().filterNot { it.getString("id") == id } + json)
