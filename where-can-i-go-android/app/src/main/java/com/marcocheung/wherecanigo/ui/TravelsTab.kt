package com.marcocheung.wherecanigo.ui

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.marcocheung.wherecanigo.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate

@Composable
fun TravelsTab(state: AppState) {
    var wishlist by rememberSaveable { mutableStateOf(false) }
    var editorKey by rememberSaveable { mutableStateOf<String?>(null) }
    var initialCountry by rememberSaveable { mutableStateOf<String?>(null) }
    var detailCountry by rememberSaveable { mutableStateOf<String?>(null) }
    var summary by rememberSaveable { mutableStateOf(false) }
    var deleteCountry by rememberSaveable { mutableStateOf<String?>(null) }
    val locale = currentLocale()
    val visits = state.data.visitRecords
    val plans = state.data.plannedTripRecords
    LaunchedEffect(state.pendingAddVisitCountryCode, state.pendingAddWishlistCountryCode, state.pendingReviewWishlistCountryCode) {
        state.pendingAddVisitCountryCode?.let {
            wishlist = false; initialCountry = it; editorKey = PersonalVisa.newId(); state.pendingAddVisitCountryCode = null
        }
        state.pendingAddWishlistCountryCode?.let {
            wishlist = true; initialCountry = it; editorKey = PersonalVisa.newId(); state.pendingAddWishlistCountryCode = null
        }
        state.pendingReviewWishlistCountryCode?.let {
            wishlist = true; detailCountry = it; state.pendingReviewWishlistCountryCode = null
        }
    }
    val grouped = if (wishlist) plans.groupingBy { it.countryCode }.eachCount() else visits.groupingBy { it.countryCode }.eachCount()
    val latest = visits.groupBy { it.countryCode }.mapValues { (_, rows) -> rows.mapNotNull { it.startDate }.maxOrNull() }
    val countries = grouped.keys.map { code -> state.countriesByCode[code] ?: Country(code, "", code, "") }
        .sortedBy { it.localizedName(locale) }.let {
        if (wishlist) it else it.sortedWith(compareByDescending<Country> { country -> latest[country.code] }
            .thenBy { country -> country.localizedName(locale) })
    }
    LazyColumn(Modifier.fillMaxSize().testTag("content-Travels"), contentPadding = PaddingValues(vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                TravelSegments(wishlist) { wishlist = it }
                Text(stringResource(if (wishlist) R.string.where_want else R.string.where_been),
                    style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                TravelSummaryCard(state, wishlist, Modifier.testTag("travel-summary")
                    .then(if (!wishlist) Modifier.clickable { summary = true } else Modifier))
                Button(onClick = { initialCountry = null; editorKey = PersonalVisa.newId() },
                    modifier = Modifier.fillMaxWidth().testTag("travel-add")) {
                    AppIcon(R.drawable.ic_add, Modifier.size(20.dp))
                    Text(stringResource(if (wishlist) R.string.add_wishlist else R.string.log_visit), Modifier.padding(start = 8.dp))
                }
                if (countries.isNotEmpty()) SectionLabel(stringResource(R.string.travel_countries))
            }
        }
        items(countries, key = { it.code }) { country ->
            SwipeAction(MaterialTheme.colorScheme.error, R.drawable.ic_delete,
                stringResource(if (wishlist) R.string.delete_all_plans else R.string.delete_all_visits),
                { deleteCountry = country.code }) {
                Surface(onClick = { detailCountry = country.code }, color = MaterialTheme.colorScheme.surfaceContainerLow,
                    modifier = Modifier.fillMaxWidth().testTag("travel-country-${country.code}")) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(country.flag, style = MaterialTheme.typography.headlineMedium)
                        Column(Modifier.weight(1f)) {
                            Text(country.localizedName(locale), fontWeight = FontWeight.SemiBold)
                            Text(stringResource(if (wishlist) R.string.planned_count else R.string.trips_count, grouped.getValue(country.code)),
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (wishlist && country.code in state.data.visitedCountryCodes) Icon(painterResource(R.drawable.ic_check),
                            stringResource(R.string.visited_before), tint = MaterialTheme.colorScheme.primary)
                        AppIcon(R.drawable.ic_chevron_right, Modifier.size(16.dp))
                    }
                }
            }
        }
        if (countries.isEmpty()) item {
            Column(Modifier.fillMaxWidth().padding(32.dp).testTag("travel-empty"), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                AppIcon(R.drawable.ic_travel, Modifier.size(40.dp))
                Text(stringResource(if (wishlist) R.string.empty_wishlist else R.string.no_visits))
                if (!wishlist) Text(stringResource(R.string.no_visits_hint), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
    editorKey?.let { id ->
        key(id) { TravelEditorSheet(state, wishlist, initial = TravelDraft(id = id, countryCode = initialCountry),
            onDismiss = { editorKey = null }) }
    }
    detailCountry?.let { code ->
        CountryTravelSheet(state, code, wishlist) { detailCountry = null }
    }
    deleteCountry?.let { code ->
        DeleteTravelCountryDialog(state, code, wishlist) { deleteCountry = null }
    }
    if (summary) TravelSummarySheet(state) { summary = false }
}

@Composable
private fun TravelSegments(wishlist: Boolean, onSelect: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf(false to R.string.been, true to R.string.wishlist).forEach { (value, label) ->
            FilterChip(selected = wishlist == value, onClick = { onSelect(value) },
                label = { Text(stringResource(label)) }, modifier = Modifier.weight(1f).testTag(if (value) "segment-Wishlist" else "segment-Been"))
        }
    }
}

@Composable
private fun TravelSummaryCard(state: AppState, wishlist: Boolean, modifier: Modifier = Modifier, detailed: Boolean = false,
    onMapReady: () -> Unit = {}) {
    val stats = if (wishlist) TravelStats.plans(state.data.plannedTripRecords) else TravelStats.visits(state.data.visitRecords)
    Surface(modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.primaryContainer, contentColor = MaterialTheme.colorScheme.onPrimaryContainer) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (detailed) TravelMiniMap(stats.countryCodes, Modifier.fillMaxWidth().height(160.dp), onMapReady)
            Text(stringResource(if (wishlist) R.string.wishlist else R.string.where_been), fontWeight = FontWeight.SemiBold)
            Row(Modifier.fillMaxWidth()) {
                SummaryNumber(stats.countryCodes.size.toString(), stringResource(R.string.travel_countries), Modifier.weight(1f))
                SummaryNumber(stats.tripCount.toString(), stringResource(R.string.travel_trips), Modifier.weight(1f))
            }
            val flags = state.countries.filter { it.code in stats.countryCodes }.map { it.flag }.sorted()
            if (flags.isNotEmpty()) Text(flags.take(if (detailed) 30 else 8).joinToString(" ") +
                if (!detailed && flags.size > 8) " +${flags.size - 8}" else "")
            Row(Modifier.fillMaxWidth()) {
                SummaryNumber(stats.continents.size.toString(), stringResource(R.string.continents), Modifier.weight(1f))
                SummaryNumber(if (wishlist && stats.tripCount > 0 && stats.datedTrips == 0) "–" else stats.totalDays.toString(),
                    stringResource(if (wishlist) R.string.days_planned else R.string.travel_days), Modifier.weight(1f))
            }
            if (detailed) {
                stats.firstTrip?.let { Text("${stringResource(R.string.first_trip)}: ${formatDate(it)}") }
                stats.lastTrip?.let { Text("${stringResource(R.string.latest_trip)}: ${formatDate(it)}") }
                Text(stringResource(R.string.tracked_with), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun SummaryNumber(value: String, label: String, modifier: Modifier) {
    Column(modifier) {
        Text(value, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
        Text(label, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun TravelSummarySheet(state: AppState, onDismiss: () -> Unit) {
    val layer = rememberGraphicsLayer()
    val scope = rememberCoroutineScope()
    var sharing by remember { mutableStateOf(false) }
    var mapReady by remember { mutableStateOf(false) }
    FullScreenSheet(stringResource(R.string.where_been), onDismiss, null, testTag = "travel-summary-sheet") {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            TravelSummaryCard(state, false, Modifier.widthIn(max = 400.dp).drawWithContent {
                layer.record { this@drawWithContent.drawContent() }
                drawLayer(layer)
            }, detailed = true, onMapReady = { mapReady = true })
            Button(enabled = !sharing && mapReady, onClick = {
                sharing = true
                scope.launch {
                    try {
                        val bitmap = layer.toImageBitmap().asAndroidBitmap()
                        val file = withContext(Dispatchers.IO) {
                            val folder = File(state.appContext.cacheDir, "shares").apply {
                                if (!isDirectory && !mkdirs()) throw java.io.IOException("Cannot create share folder")
                            }
                            File(folder, "travel-summary-${PersonalVisa.newId()}.png").apply {
                                outputStream().use { if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) throw java.io.IOException("Cannot create summary") }
                            }
                        }
                        val uri = FileProvider.getUriForFile(state.appContext, "${state.appContext.packageName}.files", file)
                        state.appContext.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                            type = "image/png"; putExtra(Intent.EXTRA_STREAM, uri)
                            clipData = android.content.ClipData.newRawUri("Travel summary", uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } catch (cancelled: kotlinx.coroutines.CancellationException) {
                        throw cancelled
                    } catch (failure: Exception) {
                        state.reportError(R.string.share_error, failure)
                    } finally { sharing = false }
                }
            }) { Text(stringResource(R.string.share_summary)) }
        }
    }
}

@Composable
fun CountryTravelSheet(state: AppState, code: String, wishlist: Boolean, onDismiss: () -> Unit) {
    val country = state.countriesByCode[code] ?: Country(code, "", code, "")
    var editingId by rememberSaveable { mutableStateOf<String?>(null) }
    var addingId by rememberSaveable { mutableStateOf<String?>(null) }
    var completingId by rememberSaveable { mutableStateOf<String?>(null) }
    var deleteAll by rememberSaveable { mutableStateOf(false) }
    val visits = state.data.visitRecords.filter { it.countryCode == code }.sortedByDescending { it.startDate }
    val plans = state.data.plannedTripRecords.filter { it.countryCode == code }.sortedWith(
        compareByDescending<PlannedTrip> { it.createdAt }.thenBy { it.id })
    val count = if (wishlist) plans.size else visits.size
    FullScreenSheet(country.localizedName(currentLocale()), onDismiss, onDismiss, testTag = "country-travel-sheet") {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${country.flag} ${country.localizedName(currentLocale())}", style = MaterialTheme.typography.headlineSmall)
                    Text(stringResource(if (wishlist) R.string.planned_count else R.string.trips_count, count) +
                        if (!wishlist) " · ${stringResource(R.string.days_count, visits.sumOf { it.dayCount ?: 0 })}" else "")
                    Button(onClick = { addingId = PersonalVisa.newId() }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(if (wishlist) R.string.add_plan else R.string.add_visit))
                    }
                }
            }
            if (wishlist) items(plans, key = { it.id }) { plan ->
                TravelRecordRow(plan.id, plan.location ?: country.localizedName(currentLocale()), planDuration(plan), plan.purpose, plan.notes,
                    onEdit = { editingId = plan.id }, onDelete = {
                        if (state.removePlans(setOf(plan.id)) && count == 1) onDismiss()
                    }, onComplete = { completingId = plan.id })
            } else items(visits, key = { it.id }) { visit ->
                TravelRecordRow(visit.id, visit.location ?: tripDateRange(visit.startDate, visit.endDate),
                    if (visit.location != null) tripDateRange(visit.startDate, visit.endDate) else
                        visit.dayCount?.let { stringResource(R.string.days_count, it) }.orEmpty(),
                    visit.purpose, visit.notes, onEdit = { editingId = visit.id }, onDelete = {
                        if (state.removeVisits(setOf(visit.id)) && count == 1) onDismiss()
                    })
            }
            if (count > 0) item {
                TextButton(onClick = { deleteAll = true }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(if (wishlist) R.string.delete_all_plans else R.string.delete_all_visits),
                        color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
    addingId?.let { id ->
        key(id) { TravelEditorSheet(state, wishlist, TravelDraft(id = id, countryCode = code)) { addingId = null } }
    }
    editingId?.let { id ->
        val draft = if (wishlist) plans.firstOrNull { it.id == id }?.let(TravelDraft::from)
            else visits.firstOrNull { it.id == id }?.let(TravelDraft::from)
        draft?.let { key(id) { TravelEditorSheet(state, wishlist, it, existing = true, onDismiss = {
            editingId = null
            if ((if (wishlist) state.data.plannedTripRecords.map { row -> row.countryCode } else state.data.visitRecords.map { row -> row.countryCode }).none { it == code }) onDismiss()
        }) } }
    }
    completingId?.let { id ->
        plans.firstOrNull { it.id == id }?.let { plan ->
            TravelEditorSheet(state, false, TravelDraft.from(plan.visitDraft), completingPlanId = id) {
                completingId = null
                if (state.data.plannedTripRecords.none { it.countryCode == code }) onDismiss()
            }
        }
    }
    if (deleteAll) DeleteTravelCountryDialog(state, code, wishlist, onDeleted = onDismiss) { deleteAll = false }
}

@Composable
private fun TravelRecordRow(id: String, title: String, subtitle: String, purpose: VisitPurpose, notes: String?,
    onEdit: () -> Unit, onDelete: () -> Unit, onComplete: (() -> Unit)? = null) {
    SwipeAction(MaterialTheme.colorScheme.error, R.drawable.ic_delete, stringResource(R.string.delete), onDelete) {
        Surface(onClick = onEdit, modifier = Modifier.fillMaxWidth().testTag("trip-$id"), color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, fontWeight = FontWeight.SemiBold)
                if (subtitle.isNotBlank()) Text(subtitle, style = MaterialTheme.typography.bodySmall)
                Text(stringResource(purpose.label), style = MaterialTheme.typography.labelMedium)
                notes?.takeIf(String::isNotBlank)?.let { Text(it, style = MaterialTheme.typography.bodySmall, maxLines = 2) }
                Row {
                    if (onComplete != null) TextButton(onClick = onComplete) { Text(stringResource(R.string.mark_completed)) }
                    TextButton(onClick = onDelete) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) }
                }
            }
        }
    }
}

@Composable
private fun DeleteTravelCountryDialog(state: AppState, code: String, wishlist: Boolean,
    onDeleted: () -> Unit = {}, onDismiss: () -> Unit) {
    val ids = if (wishlist) state.data.plannedTripRecords.filter { it.countryCode == code }.map { it.id }.toSet()
        else state.data.visitRecords.filter { it.countryCode == code }.map { it.id }.toSet()
    val country = state.countriesByCode[code]?.localizedName(currentLocale()) ?: code
    AlertDialog(onDismissRequest = onDismiss,
        title = { Text(stringResource(if (wishlist) R.string.delete_all_plans_title else R.string.delete_all_visits_title)) },
        text = { Text(stringResource(if (wishlist) R.string.delete_plans_body else R.string.delete_visits_body, ids.size, country)) },
        confirmButton = { TextButton(onClick = {
            if (if (wishlist) state.removePlans(ids) else state.removeVisits(ids)) { onDismiss(); onDeleted() }
        }) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } })
}

@Composable
fun TravelEditorSheet(state: AppState, wishlist: Boolean, initial: TravelDraft, existing: Boolean = false,
    completingPlanId: String? = null, onDismiss: () -> Unit) {
    var draft by rememberSaveable(initial.id, stateSaver = TravelDraft.Saver) { mutableStateOf(initial) }
    var picking by rememberSaveable { mutableStateOf(false) }
    var completing by rememberSaveable { mutableStateOf(false) }
    val title = when {
        completingPlanId != null -> R.string.complete_trip
        wishlist && existing -> R.string.edit_plan
        wishlist -> R.string.add_wishlist
        existing -> R.string.edit_visit
        else -> R.string.log_visit
    }
    FullScreenSheet(stringResource(title), onDismiss, onDone = {
        val saved = when {
            completingPlanId != null -> state.completePlannedTrip(completingPlanId, draft.visit())
            wishlist -> state.savePlannedTrip(draft.plan())
            else -> state.saveVisit(draft.visit())
        }
        if (saved) onDismiss()
    }, doneEnabled = if (wishlist) draft.canSavePlan else draft.canSaveVisit, testTag = "travel-editor") {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            TravelCountryField(state, draft.countryCode) { picking = true }
            Column {
                SectionLabel(stringResource(R.string.location_optional))
                FormCard { FormTextField(draft.location, { draft = draft.copy(location = it) },
                    stringResource(R.string.location_hint), Modifier.testTag("trip-location"), clearable = true) }
            }
            Column {
                SectionLabel(stringResource(R.string.purpose))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    VisitPurpose.entries.forEach { purpose ->
                        FilterChip(selected = draft.purpose == purpose, onClick = { draft = draft.copy(purpose = purpose) },
                            label = { Text(stringResource(purpose.label)) }, modifier = Modifier.testTag("purpose-${purpose.name}"))
                    }
                }
            }
            if (wishlist) {
                SectionLabel(stringResource(R.string.trip_duration))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    PlannedDurationMode.entries.forEach { mode ->
                        FilterChip(selected = draft.durationMode == mode, onClick = {
                            if (draft.durationMode != mode) draft = draft.copy(durationMode = mode,
                                estimatedDays = if (mode == PlannedDurationMode.estimatedDays) "1" else "", startDate = null, endDate = null)
                        }, label = { Text(stringResource(mode.label)) }, modifier = Modifier.testTag("duration-${mode.name}"))
                    }
                }
                if (draft.durationMode == PlannedDurationMode.estimatedDays) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedTextField(draft.estimatedDays, { draft = draft.copy(estimatedDays = it) },
                            label = { Text(stringResource(R.string.estimated_days)) }, singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.weight(1f).testTag("estimated-days"))
                        IconButton(enabled = (draft.estimatedDays.toLongOrNull() ?: 1) > 1,
                            onClick = { draft = draft.copy(estimatedDays = maxOf(1, (draft.estimatedDays.toLongOrNull() ?: 1) - 1).toString()) }) {
                            Text("−", modifier = Modifier.semantics { contentDescription = state.appContext.getString(R.string.decrease_days) })
                        }
                        IconButton(enabled = draft.estimatedDays.toLongOrNull() != Long.MAX_VALUE,
                            onClick = { draft = draft.copy(estimatedDays = maxOf(1, (draft.estimatedDays.toLongOrNull() ?: 0) + 1).toString()) }) {
                            Icon(painterResource(R.drawable.ic_add), stringResource(R.string.increase_days))
                        }
                    }
                    if ((draft.estimatedDays.toLongOrNull() ?: 0) <= 0) ErrorText(stringResource(R.string.positive_days))
                }
            }
            if (!wishlist || draft.durationMode == PlannedDurationMode.dates) {
                FormCard {
                    DateInputRow(stringResource(R.string.start_date), draft.startDate, { draft = draft.copy(startDate = it) },
                        stringResource(R.string.clear_start), maxDate = draft.endDate, testTag = "trip-start")
                    DateInputRow(stringResource(R.string.end_date), draft.endDate, { draft = draft.copy(endDate = it) },
                        stringResource(R.string.clear_end), minDate = draft.startDate,
                        defaultDate = draft.startDate ?: LocalDate.now(), testTag = "trip-end")
                }
                if (!draft.validDates) ErrorText(stringResource(R.string.date_order_error))
                else if (wishlist && draft.countryCode != null) draft.plan().plannedDayCount?.let {
                    Text(stringResource(R.string.days_count, it), style = MaterialTheme.typography.bodySmall)
                }
            }
            Column {
                SectionLabel(stringResource(R.string.notes_optional))
                FormCard { FormTextField(draft.notes, { draft = draft.copy(notes = it) }, stringResource(R.string.remark_hint),
                    Modifier.testTag("trip-notes"), singleLine = false) }
            }
            if (existing) {
                if (wishlist) TextButton(enabled = draft.canSavePlan, onClick = { completing = true }) {
                    Text(stringResource(R.string.mark_completed))
                }
                TextButton(onClick = {
                    if (if (wishlist) state.removePlans(setOf(draft.id)) else state.removeVisits(setOf(draft.id))) onDismiss()
                }) { Text(stringResource(if (wishlist) R.string.delete_plan else R.string.delete_visit), color = MaterialTheme.colorScheme.error) }
            }
        }
    }
    if (picking) CountryPickerSheet(state.countries, { draft = draft.copy(countryCode = it.code); picking = false }, { picking = false })
    if (completing) TravelEditorSheet(state, false, TravelDraft.from(draft.plan().visitDraft), completingPlanId = draft.id) {
        completing = false
        if (state.data.plannedTripRecords.none { it.id == draft.id }) onDismiss()
    }
}

@Composable
fun TravelCountryField(state: AppState, code: String?, onClick: () -> Unit) {
    Column {
        SectionLabel(stringResource(R.string.country_caps))
        Surface(onClick = onClick, modifier = Modifier.fillMaxWidth().testTag("trip-country"),
            shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerHigh) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(state.countriesByCode[code]?.let { "${it.flag} ${it.localizedName(currentLocale())}" }
                    ?: code ?: stringResource(R.string.select_a_country), Modifier.weight(1f))
                AppIcon(R.drawable.ic_chevron_right)
            }
        }
    }
}

@Composable
fun tripDateRange(start: LocalDate?, end: LocalDate?): String = when {
    start != null && end != null -> "${formatDate(start)} – ${formatDate(end)}"
    start != null -> formatDate(start)
    end != null -> stringResource(R.string.until_date, formatDate(end))
    else -> stringResource(R.string.no_dates)
}

@Composable
private fun planDuration(plan: PlannedTrip): String = when (plan.durationMode) {
    PlannedDurationMode.notSet -> stringResource(R.string.no_duration)
    PlannedDurationMode.estimatedDays -> plan.plannedDayCount?.let { stringResource(R.string.estimated_count, it) }
        ?: stringResource(R.string.no_duration)
    PlannedDurationMode.dates -> if (plan.startDate == null && plan.endDate == null) stringResource(R.string.no_duration)
        else tripDateRange(plan.startDate, plan.endDate)
}
