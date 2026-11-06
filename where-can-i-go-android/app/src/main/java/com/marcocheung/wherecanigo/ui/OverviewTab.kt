package com.marcocheung.wherecanigo.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.marcocheung.wherecanigo.R
import kotlinx.coroutines.launch

private val AccessibleCategories = setOf(
    VisaCategory.VisaFree, VisaCategory.VisaOnArrival, VisaCategory.Eta, VisaCategory.MyVisa,
)

private enum class VisitStatus(val label: Int) { Visited(R.string.visited), NotVisited(R.string.not_visited) }

@Composable
fun OverviewTab(
    state: AppState,
    onOpenPolicy: (String) -> Unit,
    onLocate: (String) -> Unit,
    onAddVisit: (String) -> Unit,
    onWishlist: (String) -> Unit,
) {
    val locale = currentLocale()
    var search by rememberSaveable { mutableStateOf("") }
    var categories by rememberSaveable { mutableStateOf(emptySet<VisaCategory>()) }
    var continents by rememberSaveable { mutableStateOf(emptySet<Continent>()) }
    var visitStatus by rememberSaveable { mutableStateOf<VisitStatus?>(null) }
    var confirmReset by remember { mutableStateOf(false) }
    val data = state.data
    val hasFilters = categories.isNotEmpty() || continents.isNotEmpty() || visitStatus != null
    val vf = data.defaultVisas.count { it.category == VisaCategory.VisaFree }
    val voa = data.defaultVisas.count { it.category == VisaCategory.VisaOnArrival }
    val eta = data.defaultVisas.count { it.category == VisaCategory.Eta }
    val mine = data.personalVisas.size
    val visited = data.visitedCountryCodes
    val countries = state.countries.filter { country ->
        val continent = Continent.of(country.code)
        country.matches(search.trim(), locale) &&
            (categories.isEmpty() || state.eligibility(country.code).category in categories) &&
            (continents.isEmpty() || continent in continents) &&
            (visitStatus == null ||
                visitStatus == (if (country.code in visited) VisitStatus.Visited else VisitStatus.NotVisited))
    }
    fun toggle(category: VisaCategory) {
        categories = if (category in categories) categories - category else categories + category
    }
    val clearFilters = {
        categories = emptySet()
        continents = emptySet()
        visitStatus = null
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val compact = maxHeight < 430.dp
        LazyColumn(
            Modifier.fillMaxSize().testTag("country-list"),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item(key = "header") {
                Column(Modifier.testTag("content-Overview"), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Spacer(Modifier)
                    val stats: List<@Composable RowScope.(Modifier) -> Unit> = listOf(
                        { m -> StatCard(vf, R.string.visa_free, VisaCategory.VisaFree.color, VisaCategory.VisaFree in categories, m) { toggle(VisaCategory.VisaFree) } },
                        { m -> StatCard(voa, R.string.visa_on_arrival, VisaCategory.VisaOnArrival.color, VisaCategory.VisaOnArrival in categories, m) { toggle(VisaCategory.VisaOnArrival) } },
                        { m -> StatCard(eta, R.string.eta, VisaCategory.Eta.color, VisaCategory.Eta in categories, m) { toggle(VisaCategory.Eta) } },
                        { m -> StatCard(mine, R.string.my_visas, VisaCategory.MyVisa.color, VisaCategory.MyVisa in categories, m) { toggle(VisaCategory.MyVisa) } },
                        { m ->
                            val selected = categories == AccessibleCategories
                            StatCard(vf + voa + eta + mine, R.string.total_accessible, MaterialTheme.colorScheme.onSurface, selected, m) {
                                categories = if (selected) emptySet() else AccessibleCategories
                            }
                        },
                    )
                    if (compact) {
                        Row(
                            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) { stats.forEach { it(Modifier.width(152.dp)) } }
                    } else {
                        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { stats.take(3).forEach { it(Modifier.weight(1f)) } }
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { stats.drop(3).forEach { it(Modifier.weight(1f)) } }
                        }
                    }
                    SearchField(search, { search = it }, Modifier.padding(horizontal = 16.dp))
                    FlowRow(
                        Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        FilterMenu(
                            title = stringResource(R.string.entry),
                            icon = R.drawable.ic_doc,
                            count = categories.size,
                            active = categories.isNotEmpty(),
                            tag = "filter-entry",
                        ) {
                            CheckItem(stringResource(R.string.all_entry_requirements), categories.isEmpty()) { categories = emptySet() }
                            HorizontalDivider()
                            VisaCategory.entries.forEach { category ->
                                val label = if (category == VisaCategory.MyVisa) R.string.my_visas else category.label
                                CheckItem(stringResource(label), category in categories) { toggle(category) }
                            }
                        }
                        FilterMenu(
                            title = stringResource(R.string.continent),
                            icon = R.drawable.ic_globe,
                            count = continents.size,
                            active = continents.isNotEmpty(),
                            tag = "filter-continent",
                        ) {
                            CheckItem(stringResource(R.string.all_continents), continents.isEmpty()) { continents = emptySet() }
                            HorizontalDivider()
                            Continent.entries.forEach { continent ->
                                CheckItem(stringResource(continent.label), continent in continents) {
                                    continents = if (continent in continents) continents - continent else continents + continent
                                }
                            }
                        }
                        FilterMenu(
                            title = stringResource(visitStatus?.label ?: R.string.visited_q),
                            icon = R.drawable.ic_pin,
                            count = 0,
                            active = visitStatus != null,
                            tag = "filter-visited",
                        ) {
                            RadioItem(stringResource(R.string.all_visit_statuses), visitStatus == null) { visitStatus = null }
                            HorizontalDivider()
                            VisitStatus.entries.forEach { status ->
                                RadioItem(stringResource(status.label), visitStatus == status) { visitStatus = status }
                            }
                        }
                        if (hasFilters) {
                            IconButton(onClick = clearFilters, modifier = Modifier.testTag("clear-filters")) {
                                Icon(
                                    painterResource(R.drawable.ic_close),
                                    contentDescription = stringResource(R.string.clear_filters),
                                    modifier = Modifier.size(16.dp),
                                )
                            }
                        }
                    }
                    if (hasFilters || search.isNotEmpty()) {
                        Text(
                            stringResource(R.string.countries_count, countries.size),
                            modifier = Modifier.padding(horizontal = 16.dp).testTag("result-count"),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            items(countries, key = { it.code }) { country ->
                LocateSwipe(onLocate = { onLocate(country.code) }) {
                    CountryRow(state, country, Modifier.clickable { onOpenPolicy(country.code) },
                        { onAddVisit(country.code) }, { onWishlist(country.code) })
                }
            }
            if (countries.isEmpty() && state.countries.isNotEmpty()) item(key = "empty") {
                Column(
                    Modifier.fillMaxWidth().padding(24.dp).testTag("no-matches"),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    AppIcon(R.drawable.ic_search, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(R.string.no_matching_countries), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Button(
                        onClick = { search = ""; clearFilters() },
                    ) { Text(stringResource(R.string.clear_search_filters), fontWeight = FontWeight.SemiBold) }
                }
            }
            if (search.isEmpty() && !hasFilters) item(key = "footer") {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    state.bundledUpdatedAt?.let {
                        Text(
                            stringResource(R.string.policy_updated, formatUpdatedDate(it)),
                            modifier = Modifier.fillMaxWidth().testTag("policy-updated"),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                    Surface(
                        onClick = { confirmReset = true },
                        shape = RoundedCornerShape(10.dp),
                        color = MaterialTheme.colorScheme.surfaceContainerHigh,
                        modifier = Modifier.fillMaxWidth().testTag("reset-defaults"),
                    ) {
                        Text(
                            stringResource(R.string.reset_default_data),
                            modifier = Modifier.padding(16.dp),
                            fontWeight = FontWeight.Bold,
                            textAlign = TextAlign.Center,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                    Spacer(Modifier)
                }
            }
        }
    }
    if (confirmReset) {
        AlertDialog(
            onDismissRequest = { confirmReset = false },
            text = { Text(stringResource(R.string.reset_confirm)) },
            confirmButton = {
                TextButton(onClick = { if (state.resetDefaultsToBundled()) confirmReset = false }, modifier = Modifier.testTag("confirm-reset")) {
                    Text(stringResource(R.string.reset), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmReset = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
fun SearchField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth().testTag("country-search"),
        placeholder = { Text(stringResource(R.string.search_countries)) },
        leadingIcon = { AppIcon(R.drawable.ic_search, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
        trailingIcon = if (value.isNotEmpty()) {
            { IconButton(onClick = { onValueChange("") }) { AppIcon(R.drawable.ic_clear, Modifier.size(18.dp)) } }
        } else null,
        singleLine = true,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search, autoCorrectEnabled = false),
        shape = RoundedCornerShape(10.dp),
        colors = TextFieldDefaults.colors(
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
        ),
    )
}

@Composable
private fun StatCard(
    value: Int,
    label: Int,
    color: Color,
    selected: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        modifier = modifier.testTag("stat-$label").semantics { this.selected = selected },
        shape = MaterialTheme.shapes.large,
        color = if (selected) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerLow,
        border = BorderStroke(if (selected) 2.dp else 1.dp, color),
    ) {
        Box {
            Column(
                Modifier.fillMaxWidth().padding(vertical = 16.dp, horizontal = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text("$value", fontSize = 32.sp, fontWeight = FontWeight.Bold)
                Text(
                    stringResource(label),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
            if (selected) {
                Icon(
                    painterResource(R.drawable.ic_check),
                    contentDescription = null,
                    tint = color,
                    modifier = Modifier.align(Alignment.TopEnd).padding(6.dp).size(14.dp),
                )
            }
        }
    }
}

@Composable
private fun FilterMenu(
    title: String,
    icon: Int,
    count: Int,
    active: Boolean,
    tag: String,
    content: @Composable () -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        FilterChip(
            selected = active,
            onClick = { open = true },
            label = { Text(if (count > 0) "$title $count" else title) },
            leadingIcon = { AppIcon(icon, Modifier.size(18.dp)) },
            trailingIcon = { AppIcon(R.drawable.ic_dropdown, Modifier.size(18.dp)) },
            modifier = Modifier.testTag(tag),
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) { content() }
    }
}

@Composable
private fun CheckItem(text: String, checked: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(text) },
        onClick = onClick,
        leadingIcon = { Checkbox(checked = checked, onCheckedChange = null) },
    )
}

@Composable
private fun RadioItem(text: String, selected: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(text) },
        onClick = onClick,
        leadingIcon = { RadioButton(selected = selected, onClick = null) },
    )
}

/** Trailing swipe action that triggers instead of dismissing, like iOS `swipeActions`. */
@Composable
fun LocateSwipe(onLocate: () -> Unit, content: @Composable () -> Unit) {
    SwipeAction(MaterialTheme.colorScheme.primary, R.drawable.ic_pin, stringResource(R.string.locate), onLocate, content)
}

@Composable
fun SwipeAction(
    color: Color,
    icon: Int,
    description: String,
    onAction: () -> Unit,
    content: @Composable () -> Unit,
) {
    val action by rememberUpdatedState(onAction)
    val swipe = rememberSwipeToDismissBoxState()
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    SwipeToDismissBox(
        state = swipe,
        enableDismissFromStartToEnd = false,
        onDismiss = {
            if (it == SwipeToDismissBoxValue.EndToStart) action()
            scope.launch { swipe.reset() }
        },
        modifier = Modifier.padding(horizontal = 16.dp).clip(MaterialTheme.shapes.large).semantics {
            customActions = listOf(CustomAccessibilityAction(description) { action(); true })
        },
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(color).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(painterResource(icon), contentDescription = description, tint = Color.White)
            }
        },
    ) { content() }
}

@Composable
private fun CountryRow(state: AppState, country: Country, modifier: Modifier, onVisit: () -> Unit, onWishlist: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val visitLabel = stringResource(R.string.log_visit)
    val wishlistLabel = stringResource(if (state.data.plannedTripRecords.any { it.countryCode == country.code })
        R.string.review_wishlist else R.string.add_wishlist)
    val locale = currentLocale()
    val eligibility = state.eligibility(country.code)
    val entry = state.data.defaultVisas.firstOrNull { it.countryCode == country.code }
    val remark = if (entry?.remark?.isNotBlank() == true) " - ${stringResource(R.string.see_remark)}" else ""
    val source = eligibility.sourceVisa
    val subtitle = when {
        source != null -> {
            val label = if (source.coverage == VisaCoverage.SchengenArea) {
                stringResource(
                    R.string.schengen_issued_by,
                    state.countriesByCode[source.countryCode]?.localizedName(locale) ?: source.countryCode,
                )
            } else source.visaType
            "$label · ${source.duration} · ${stringResource(R.string.expires, formatDate(source.expiryDate))}$remark"
        }
        entry != null -> stringResource(entry.category.label) +
            (entry.duration?.takeIf { it.isNotEmpty() }?.let { " – $it" } ?: "") + remark
        else -> stringResource(R.string.visa_required)
    }
    Surface(
        modifier = Modifier.fillMaxWidth().testTag("country-${country.code}").then(modifier).semantics {
            customActions = listOf(CustomAccessibilityAction(visitLabel) { onVisit(); true },
                CustomAccessibilityAction(wishlistLabel) { onWishlist(); true })
        },
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(country.flag, fontSize = 28.sp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(country.localizedName(locale), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = source?.expiryColor() ?: MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Box {
                IconButton(onClick = { menu = true }, modifier = Modifier.testTag("country-travel-menu-${country.code}")) {
                    Icon(painterResource(R.drawable.ic_more), stringResource(R.string.country_actions))
                }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem(text = { Text(visitLabel) }, onClick = { menu = false; onVisit() })
                    DropdownMenuItem(text = { Text(wishlistLabel) }, onClick = { menu = false; onWishlist() })
                }
            }
            Box(Modifier.size(10.dp).clip(CircleShape).background(eligibility.category.color))
        }
    }
}

@Composable
fun TravelWarningNotice(modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        AppIcon(R.drawable.ic_warning, Modifier.size(16.dp), tint = WarningOrange)
        Text(stringResource(R.string.travel_warning_body), style = MaterialTheme.typography.bodySmall, color = WarningOrange)
    }
}

/** Port of iOS `EntryPolicySheet`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EntryPolicySheet(state: AppState, initialCode: String, onDismiss: () -> Unit) {
    val locale = currentLocale()
    var code by rememberSaveable { mutableStateOf(initialCode) }
    var picking by rememberSaveable { mutableStateOf(false) }
    val originalEntry = state.data.defaultVisas.firstOrNull { it.countryCode == code }
    val originalVisa = state.data.personalVisas.firstOrNull { it.countryCode == code }
    var category by rememberSaveable(code) { mutableStateOf(originalEntry?.category ?: VisaCategory.VisaRequired) }
    var duration by rememberSaveable(code) { mutableStateOf(originalEntry?.duration.orEmpty()) }
    var remark by rememberSaveable(code) { mutableStateOf(originalEntry?.remark.orEmpty()) }
    var draft by rememberSaveable(code, stateSaver = VisaDraft.Saver) {
        mutableStateOf(originalVisa?.let(VisaDraft::from) ?: VisaDraft(countryCode = code))
    }
    if (originalVisa != null) CleanupVisaAttachments(state, originalVisa.id) { originalVisa.attachmentFileNames }
    val visa = draft
    val hasPolicyChanges = category != (originalEntry?.category ?: VisaCategory.VisaRequired) ||
        duration != originalEntry?.duration.orEmpty() || remark != originalEntry?.remark.orEmpty()
    val hasVisaChanges = originalVisa != null && visa != VisaDraft.from(originalVisa)
    val visaValid = originalVisa == null || visa.isComplete
    val country = state.countriesByCode[code]

    FullScreenSheet(
        title = stringResource(R.string.entry_policy),
        onCancel = onDismiss,
        onDone = {
            if (!hasPolicyChanges && !hasVisaChanges) {
                onDismiss()
            } else {
                val entry = if (!hasPolicyChanges) originalEntry else if (category == VisaCategory.VisaRequired) null else {
                    DefaultVisaEntry(code, category, duration.ifEmpty { null }, remark.takeIf { it.isNotBlank() })
                }
                val updatedVisa = if (hasVisaChanges && originalVisa != null) visa.toVisa(originalVisa.id, code) else null
                if (state.saveEntryPolicy(code, entry, updatedVisa)) onDismiss()
            }
        },
        doneEnabled = !hasVisaChanges || visaValid,
        testTag = "entry-policy-sheet",
    ) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column {
                SectionLabel(stringResource(R.string.country_caps))
                Surface(
                    onClick = { picking = true },
                    shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    modifier = Modifier.testTag("policy-country"),
                ) {
                    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(country?.let { "${it.flag}  ${it.localizedName(locale)}" } ?: stringResource(R.string.select_a_country), Modifier.weight(1f))
                        AppIcon(R.drawable.ic_chevron_right, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            Column {
                SectionLabel(stringResource(R.string.entry_policy_type))
                val options = listOf(
                    VisaCategory.VisaRequired to R.string.visa_required,
                    VisaCategory.VisaFree to R.string.visa_free,
                    VisaCategory.VisaOnArrival to R.string.voa,
                    VisaCategory.Eta to R.string.eta_short,
                )
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    options.forEachIndexed { index, (value, label) ->
                        SegmentedButton(
                            selected = category == value,
                            onClick = { category = value },
                            shape = SegmentedButtonDefaults.itemShape(index, options.size),
                            modifier = Modifier.testTag("policy-${value.jsonValue}"),
                            icon = {},
                        ) { Text(stringResource(label), maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    }
                }
            }
            Column {
                SectionLabel(stringResource(R.string.duration_caps))
                FormCard { FormTextField(duration, { duration = it }, stringResource(R.string.duration_hint), Modifier.testTag("policy-duration"), clearable = true) }
            }
            Column {
                SectionLabel(stringResource(R.string.remark_caps))
                FormCard { FormTextField(remark, { remark = it }, stringResource(R.string.remark_hint), Modifier.testTag("policy-remark"), singleLine = false) }
            }
            if (originalEntry != null && originalEntry == state.bundledEntry(code)) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    state.bundledUpdatedAt?.let {
                        Text(
                            stringResource(R.string.policy_updated, formatUpdatedDate(it)),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    TravelWarningNotice()
                }
            }
            if (originalEntry != null) {
                TextButton(
                    onClick = { if (state.removeDefaultVisa(code)) onDismiss() },
                    modifier = Modifier.testTag("remove-policy"),
                ) { Text(stringResource(R.string.remove_policy), color = MaterialTheme.colorScheme.error) }
            }
            if (originalVisa != null) {
                HorizontalDivider()
                Text(stringResource(R.string.personal_visa), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                PersonalVisaFields(visa, originalVisa.id) { draft = it }
                if (hasVisaChanges && !visaValid) {
                    ErrorText(stringResource(R.string.fill_enabled_dates))
                }
            }
        }
    }
    if (picking) {
        CountryPickerSheet(state.countries, onSelect = { code = it.code; picking = false }, onCancel = { picking = false })
    }
}

@Composable
fun ErrorText(message: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        AppIcon(R.drawable.ic_warning, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.error)
        Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, modifier = Modifier.testTag("error-text"))
    }
}
