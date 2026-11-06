package com.marcocheung.wherecanigo.ui

import androidx.compose.foundation.clickable
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.marcocheung.wherecanigo.R
import java.time.LocalDate

@Composable
fun MyVisasTab(state: AppState, retainDraftOnDispose: () -> Boolean) {
    val locale = currentLocale()
    val activity = LocalActivity.current
    var draftId by rememberSaveable { mutableStateOf(PersonalVisa.newId()) }
    var draft by rememberSaveable(stateSaver = VisaDraft.Saver) { mutableStateOf(VisaDraft()) }
    var error by rememberSaveable { mutableStateOf<Int?>(null) }
    var editingDraft by rememberSaveable { mutableStateOf(false) }
    var editingId by rememberSaveable { mutableStateOf<String?>(null) }
    var deletingId by rememberSaveable { mutableStateOf<String?>(null) }
    val editing = state.data.personalVisas.firstOrNull { it.id == editingId }
    val deleting = state.data.personalVisas.firstOrNull { it.id == deletingId }
    CleanupVisaAttachments(state, draftId) {
        if (activity?.isFinishing != true && retainDraftOnDispose()) draft.attachments else emptyList()
    }

    LaunchedEffect(state.pendingAddVisaCountryCode) {
        state.pendingAddVisaCountryCode?.let {
            draft = draft.copy(countryCode = it, coverage = VisaCoverage.IssuingCountry)
            state.pendingAddVisaCountryCode = null
        }
    }

    val canAdd = draft.countryCode != null && draft.isComplete
    val country = draft.countryCode?.let { state.countriesByCode[it] }
    fun validation(): Int? = when {
        draft.countryCode == null -> R.string.error_select_country
        draft.visaType.isBlank() || draft.duration.isBlank() || draft.expiryDate == null ||
            (draft.hasEffectiveDate && draft.effectiveDate == null) -> R.string.error_fill_fields
        !draft.hasValidPeriod -> R.string.error_effective_after
        else -> null
    }
    val visibleError = error?.takeIf { validation() != null }

    LazyColumn(
        Modifier.fillMaxSize().testTag("content-Visas"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "add") {
            Column(Modifier.padding(horizontal = 16.dp).padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.add_personal_visa), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ButtonCard(
                        title = stringResource(R.string.issuing_country),
                        body = country?.let { "${it.flag} ${it.localizedName(locale)}" },
                        tag = "draft-country",
                        modifier = Modifier.weight(1f),
                    ) { editingDraft = true }
                    val details = if (draft.duration.isNotBlank() && draft.expiryDate != null) {
                        "${draft.duration}\n${formatDate(draft.expiryDate!!)}"
                    } else null
                    ButtonCard(
                        title = stringResource(R.string.visa_details),
                        body = details,
                        tag = "draft-details",
                        modifier = Modifier.weight(1f),
                    ) { editingDraft = true }
                }
                visibleError?.let { ErrorText(stringResource(it)) }
                Button(
                    onClick = {
                        val problem = validation()
                        if (problem != null) {
                            error = problem
                        } else {
                            if (state.addPersonalVisa(draft.toVisa(draftId, draft.countryCode!!))) {
                                state.pruneAttachments(draftId, draft.attachments)
                                draft = VisaDraft()
                                draftId = PersonalVisa.newId()
                                error = null
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth().height(50.dp).testTag("add-visa"),
                    shape = MaterialTheme.shapes.extraLarge,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (canAdd) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHighest,
                        contentColor = if (canAdd) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
                ) {
                    AppIcon(R.drawable.ic_add, Modifier.size(20.dp))
                    Text(stringResource(R.string.add_visa), Modifier.padding(start = 8.dp), fontWeight = FontWeight.SemiBold)
                }
                Spacer(Modifier.height(4.dp))
                Text(stringResource(R.string.saved_personal_visas), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                if (state.data.personalVisas.isEmpty()) {
                    Text(
                        stringResource(R.string.no_personal_visas),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.testTag("no-visas"),
                    )
                }
            }
        }
        items(state.data.personalVisas, key = { it.id }) { visa ->
            SwipeAction(MaterialTheme.colorScheme.error, R.drawable.ic_delete, stringResource(R.string.delete), { deletingId = visa.id }) {
                SavedVisaRow(state, visa, onDelete = { deletingId = visa.id }) { editingId = visa.id }
            }
        }
        item(key = "bottom") { Spacer(Modifier.height(24.dp)) }
    }

    if (editingDraft) {
        VisaDetailsSheet(state, draftId, draft, onCancel = { editingDraft = false }) {
            draft = it
            editingDraft = false
            true
        }
    }
    editing?.let { visa ->
        VisaDetailsSheet(state, visa.id, VisaDraft.from(visa), onCancel = { editingId = null }) { updated ->
            val saved = state.updatePersonalVisa(updated.toVisa(visa.id, requireNotNull(updated.countryCode)))
            if (saved) editingId = null
            saved
        }
    }
    deleting?.let { visa ->
        val name = state.countriesByCode[visa.countryCode]?.localizedName(locale) ?: visa.countryCode
        AlertDialog(
            onDismissRequest = { deletingId = null },
            title = { Text(stringResource(R.string.delete_visa_title)) },
            text = { Text("$name · ${visa.visaType}\n\n${stringResource(R.string.delete_visa_body)}") },
            confirmButton = {
                TextButton(onClick = { if (state.removePersonalVisa(visa.id)) deletingId = null }, modifier = Modifier.testTag("confirm-delete")) {
                    Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { deletingId = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
private fun ButtonCard(title: String, body: String?, tag: String, modifier: Modifier, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = modifier.fillMaxHeight().testTag(tag),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            Text(
                body ?: stringResource(R.string.tap_to_edit),
                style = MaterialTheme.typography.bodySmall,
                color = if (body == null) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun SavedVisaRow(state: AppState, visa: PersonalVisa, onDelete: () -> Unit, onClick: () -> Unit) {
    val locale = currentLocale()
    val country = state.countriesByCode[visa.countryCode]
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Surface(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).testTag("visa-${visa.id}"),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${country?.flag.orEmpty()}  ${country?.localizedName(locale) ?: visa.countryCode}",
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                androidx.compose.material3.IconButton(onClick = onDelete, modifier = Modifier.testTag("delete-visa-${visa.id}")) {
                    androidx.compose.material3.Icon(androidx.compose.ui.res.painterResource(R.drawable.ic_delete),
                        contentDescription = stringResource(R.string.delete), tint = MaterialTheme.colorScheme.error)
                }
            }
            if (visa.coverage == VisaCoverage.SchengenArea) {
                Text(stringResource(R.string.schengen_area), style = MaterialTheme.typography.bodySmall, color = LocateBlue)
            }
            Text("${visa.visaType} · ${visa.duration}", style = MaterialTheme.typography.bodySmall, color = secondary)
            visa.effectiveDate?.let {
                Text(
                    stringResource(R.string.valid_from, formatDate(it)),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (it.isAfter(LocalDate.now())) WarningOrange else secondary,
                )
            }
            Text(
                stringResource(R.string.expires, formatDate(visa.expiryDate)),
                style = MaterialTheme.typography.bodySmall,
                color = visa.expiryColor(),
            )
            visa.notes?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = secondary, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** Port of iOS `VisaDetailsSheet`; edits a local copy and commits it on Done. */
@Composable
private fun VisaDetailsSheet(
    state: AppState,
    visaId: String,
    initial: VisaDraft,
    onCancel: () -> Unit,
    onDone: (VisaDraft) -> Boolean,
) {
    val locale = currentLocale()
    var draft by rememberSaveable(visaId, stateSaver = VisaDraft.Saver) { mutableStateOf(initial) }
    var picking by rememberSaveable { mutableStateOf(false) }
    var retained by rememberSaveable { mutableStateOf(initial.attachments) }
    CleanupVisaAttachments(state, visaId) { retained }
    val country = draft.countryCode?.let { state.countriesByCode[it] }
    FullScreenSheet(
        title = stringResource(R.string.visa_details),
        onCancel = onCancel,
        onDone = { if (onDone(draft)) retained = draft.attachments },
        doneEnabled = draft.countryCode != null && draft.isComplete,
        testTag = "visa-details-sheet",
    ) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column {
                SectionLabel(stringResource(R.string.issuing_country).uppercase(locale))
                Surface(
                    onClick = { picking = true },
                    shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    modifier = Modifier.testTag("visa-country"),
                ) {
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            country?.let { "${it.flag}  ${it.localizedName(locale)}" } ?: stringResource(R.string.select_a_country),
                            Modifier.weight(1f).padding(vertical = 16.dp),
                            color = if (country == null) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                        )
                        if (country != null) {
                            androidx.compose.material3.IconButton(onClick = { draft = draft.copy(countryCode = null, coverage = VisaCoverage.IssuingCountry) }) {
                                AppIcon(R.drawable.ic_clear, Modifier.size(18.dp))
                            }
                        }
                    }
                }
            }
            PersonalVisaFields(draft, visaId) { draft = it }
        }
    }
    if (picking) {
        CountryPickerSheet(
            state.countries,
            onSelect = {
                val coverage = if (it.code in VisaCoverage.schengenCountryCodes) draft.coverage else VisaCoverage.IssuingCountry
                draft = draft.copy(countryCode = it.code, coverage = coverage)
                picking = false
            },
            onCancel = { picking = false },
        )
    }
}
