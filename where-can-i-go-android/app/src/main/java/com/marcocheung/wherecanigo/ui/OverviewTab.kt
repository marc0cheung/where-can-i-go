package com.marcocheung.wherecanigo.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.rememberTextMeasurer
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

    val reportPeek = LocalPeekContentReporter.current
    val density = androidx.compose.ui.platform.LocalDensity.current
    val bottomPadding = LocalSheetBottomPadding.current
    val clearWidth by animateDpAsState(
        if (hasFilters) 48.dp else 0.dp,
        animationSpec = tween(220),
        label = "filter-clear-width",
    )
    Box(Modifier.fillMaxSize()) {
        // Short windows (landscape phones) scroll the stats horizontally to save height.
        val compact = androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp < 480
        LazyColumn(
            Modifier.fillMaxSize().testTag("country-list"),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = bottomPadding + 16.dp),
            verticalArrangement = Arrangement.spacedBy(GroupedListGap),
        ) {
            item(key = "header") {
                Column(
                    Modifier.testTag("content-Overview").padding(top = 4.dp, bottom = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
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
                            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp)
                                .onSizeChanged { reportPeek(with(density) { it.height.toDp() } + 4.dp) },
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) { stats.forEach { it(Modifier.width(140.dp)) } }
                    } else {
                        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(
                                Modifier.height(IntrinsicSize.Min)
                                    .onSizeChanged { reportPeek(with(density) { it.height.toDp() } + 4.dp) },
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) { stats.take(3).forEach { it(Modifier.weight(1f).fillMaxHeight()) } }
                            Row(
                                Modifier.height(IntrinsicSize.Min),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) { stats.drop(3).forEach { it(Modifier.weight(1f).fillMaxHeight()) } }
                        }
                    }
                    SearchField(search, { search = it }, Modifier.padding(horizontal = 16.dp))
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 16.dp).testTag("filter-row"),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        FilterMenu(
                            title = stringResource(R.string.entry),
                            icon = R.drawable.ic_doc,
                            count = categories.size,
                            active = categories.isNotEmpty(),
                            tag = "filter-entry",
                            modifier = Modifier.weight(1f),
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
                            modifier = Modifier.weight(1f),
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
                            modifier = Modifier.weight(1f),
                        ) {
                            RadioItem(stringResource(R.string.all_visit_statuses), visitStatus == null) { visitStatus = null }
                            HorizontalDivider()
                            VisitStatus.entries.forEach { status ->
                                RadioItem(stringResource(status.label), visitStatus == status) { visitStatus = status }
                            }
                        }
                        Box(Modifier.width(clearWidth).height(48.dp).clip(CircleShape)) {
                            if (hasFilters || clearWidth > 0.dp) IconButton(
                                onClick = clearFilters,
                                enabled = hasFilters,
                                modifier = Modifier.size(48.dp).alpha(clearWidth / 48.dp).testTag("clear-filters"),
                            ) {
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
            itemsIndexed(countries, key = { _, country -> country.code }) { index, country ->
                LocateSwipe(onLocate = { onLocate(country.code) }, shape = groupedShape(index, countries.size)) {
                    CountryRow(state, country, Modifier.clickable { onOpenPolicy(country.code) },
                        { onAddVisit(country.code) }, { onWishlist(country.code) }, { onLocate(country.code) })
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
                Column(Modifier.padding(horizontal = 16.dp).padding(top = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    state.bundledUpdatedAt?.let {
                        Text(
                            stringResource(R.string.policy_updated, formatUpdatedDate(it)),
                            modifier = Modifier.fillMaxWidth().testTag("policy-updated"),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                    androidx.compose.material3.OutlinedButton(
                        onClick = { confirmReset = true },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("reset-defaults"),
                    ) { Text(stringResource(R.string.reset_default_data)) }
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
        shape = CircleShape,
        colors = TextFieldDefaults.colors(
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
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
    val container = if (selected) color.copy(alpha = 0.14f).compositeOver(listItemColor()) else listItemColor()
    Surface(
        onClick = onClick,
        modifier = modifier.testTag("stat-$label").semantics { this.selected = selected },
        shape = RoundedCornerShape(20.dp),
        color = container,
        border = if (selected) BorderStroke(2.dp, color) else null,
    ) {
        Box {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text("$value", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.size(8.dp).clip(CircleShape).background(color))
                    Text(
                        stringResource(label),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (selected) {
                Icon(
                    painterResource(R.drawable.ic_check),
                    contentDescription = null,
                    tint = color,
                    modifier = Modifier.align(Alignment.TopEnd).padding(10.dp).size(16.dp),
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
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val label = if (count > 0) "$title $count" else title
    val labelStyle = MaterialTheme.typography.labelLarge
    val labelWidth = with(LocalDensity.current) {
        rememberTextMeasurer().measure(AnnotatedString(label), style = labelStyle, maxLines = 1).size.width.toDp()
    }
    BoxWithConstraints(modifier) {
        val iconWidth by animateDpAsState(
            if (maxWidth >= labelWidth + 54.dp) 22.dp else 0.dp,
            animationSpec = tween(220),
            label = "filter-icon-width",
        )
        Surface(
            onClick = { open = true },
            shape = RoundedCornerShape(16.dp),
            color = if (active) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent,
            border = if (active) null else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(tag).semantics { selected = active },
        ) {
            Row(
                Modifier.padding(horizontal = 6.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.width(iconWidth).height(18.dp).clip(RoundedCornerShape(0.dp))) {
                    AppIcon(icon, Modifier.size(18.dp).alpha(iconWidth / 22.dp))
                }
                Text(
                    label,
                    Modifier.weight(1f),
                    style = labelStyle,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.width(4.dp))
                AppIcon(R.drawable.ic_dropdown, Modifier.size(16.dp))
            }
        }
        AppDropdownMenu(expanded = open, onDismissRequest = { open = false }) { content() }
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
fun LocateSwipe(onLocate: () -> Unit, shape: Shape = MaterialTheme.shapes.large, content: @Composable () -> Unit) {
    SwipeAction(MaterialTheme.colorScheme.primary, R.drawable.ic_pin, stringResource(R.string.locate), onLocate, shape, content)
}

@Composable
fun SwipeAction(
    color: Color,
    icon: Int,
    description: String,
    onAction: () -> Unit,
    shape: Shape = MaterialTheme.shapes.large,
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
        modifier = Modifier.padding(horizontal = 16.dp).clip(shape).semantics {
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
private fun CountryRow(state: AppState, country: Country, modifier: Modifier, onVisit: () -> Unit, onWishlist: () -> Unit, onLocate: () -> Unit) {
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
        color = listItemColor(),
    ) {
        Row(
            Modifier.heightIn(min = 64.dp).padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(country.flag, fontSize = 20.sp)
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(country.localizedName(locale), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.size(8.dp).clip(CircleShape).background(eligibility.category.color))
                    Text(
                        subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = source?.expiryColor() ?: MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Box {
                IconButton(onClick = { menu = true }, modifier = Modifier.testTag("country-travel-menu-${country.code}")) {
                    Icon(painterResource(R.drawable.ic_more), stringResource(R.string.country_actions),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                AppDropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.locate_on_map)) },
                        leadingIcon = { AppIcon(R.drawable.ic_pin) },
                        modifier = Modifier.testTag("country-locate-${country.code}"),
                        onClick = { menu = false; onLocate() },
                    )
                    DropdownMenuItem(text = { Text(visitLabel) }, onClick = { menu = false; onVisit() })
                    DropdownMenuItem(text = { Text(wishlistLabel) }, onClick = { menu = false; onWishlist() })
                }
            }
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
