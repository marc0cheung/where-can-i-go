package com.marcocheung.wherecanigo.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.marcocheung.wherecanigo.R

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Page(title: String, onBack: () -> Unit, tag: String, content: @Composable () -> Unit) {
    BackHandler(onBack = onBack)
    Scaffold(
        modifier = Modifier.testTag(tag),
        topBar = {
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack, modifier = Modifier.testTag("page-back")) {
                        AppIcon(R.drawable.ic_close)
                    }
                },
            )
        },
    ) { padding -> Box(Modifier.padding(padding).fillMaxSize()) { content() } }
}

@Composable
fun ProfilePage(state: AppState, onBack: () -> Unit) {
    ProfileEditorPage(state, onBack)
}

@Composable
fun SettingsPage(state: AppState, onBack: () -> Unit) {
    AppSettingsPage(state, onBack)
}

/** First-launch gate: passport picker, then the Before You Travel notice. */
@Composable
fun PassportGate(state: AppState) {
    var picked by rememberSaveable { mutableStateOf<String?>(null) }
    Surface(Modifier.fillMaxSize().testTag("passport-gate")) {
        Box(Modifier.safeDrawingPadding(), contentAlignment = Alignment.TopCenter) {
            Box(Modifier.widthIn(max = 560.dp)) {
                val code = picked
                if (code == null) {
                    PassportPicker(state, initial = null, showWelcome = true) { picked = it }
                } else {
                    BeforeYouTravel { state.completePassportSelection(code) }
                }
            }
        }
    }
}

@Composable
fun PassportPicker(state: AppState, initial: String?, showWelcome: Boolean, onUse: (String) -> Unit) {
    val locale = currentLocale()
    var search by rememberSaveable { mutableStateOf("") }
    var selected by rememberSaveable { mutableStateOf(initial) }
    val matches = state.countries.filter { it.matches(search.trim(), locale) }
    val (supported, others) = matches.partition { it.code in SupportedPassports }
    Column(Modifier.fillMaxSize()) {
        if (showWelcome) {
            Column(Modifier.padding(horizontal = 20.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.welcome), fontSize = 30.sp, fontWeight = FontWeight.Bold)
                Text(stringResource(R.string.select_passport_prompt), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        SearchField(search, { search = it }, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
        LazyColumn(Modifier.weight(1f)) {
            if (supported.isNotEmpty()) item(key = "h1") { PickerHeader(stringResource(R.string.supported_passports)) }
            items(supported, key = { it.code }) { country ->
                PassportRow(country, selected == country.code, enabled = true) { selected = country.code }
            }
            if (others.isNotEmpty()) item(key = "h2") { PickerHeader(stringResource(R.string.more_to_come)) }
            items(others, key = { it.code }) { country -> PassportRow(country, false, enabled = false) {} }
        }
        Button(
            onClick = { selected?.let(onUse) },
            enabled = selected != null,
            modifier = Modifier.fillMaxWidth().padding(16.dp).height(50.dp).testTag("use-passport"),
            shape = MaterialTheme.shapes.extraLarge,
        ) { Text(stringResource(R.string.use_this_passport), fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun PickerHeader(text: String) {
    Text(
        text,
        modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 6.dp),
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun PassportRow(country: Country, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Column(Modifier.alpha(if (enabled) 1f else 0.45f)) {
        Row(
            Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 20.dp, vertical = 12.dp).testTag("passport-${country.code}"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(country.flag, style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.width(12.dp))
            Text(country.localizedName(currentLocale()), Modifier.weight(1f))
            if (selected) AppIcon(R.drawable.ic_check, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
        }
        HorizontalDivider(Modifier.padding(start = 56.dp))
    }
}

@Composable
private fun BeforeYouTravel(onAccept: () -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp).testTag("before-you-travel"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Spacer(Modifier.height(40.dp))
        AppIcon(R.drawable.ic_warning, Modifier.size(56.dp), tint = WarningOrange)
        Text(stringResource(R.string.before_you_travel), fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.travel_warning_body), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = onAccept,
            modifier = Modifier.fillMaxWidth().height(50.dp).testTag("i-understand"),
            shape = MaterialTheme.shapes.extraLarge,
        ) { Text(stringResource(R.string.i_understand), fontWeight = FontWeight.Bold) }
    }
}

@Composable
fun CountryCard(
    state: AppState,
    code: String,
    onOpen: () -> Unit,
    onAddVisa: () -> Unit,
    onAddVisit: () -> Unit,
    onAddWishlist: () -> Unit,
    onReviewWishlist: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val locale = currentLocale()
    val country = state.countriesByCode[code] ?: return
    val eligibility = state.eligibility(code)
    val source = eligibility.sourceVisa
    val entry = state.data.defaultVisas.firstOrNull { it.countryCode == code }
    var menu by remember { mutableStateOf(false) }
    val name = country.localizedName(locale)
    Surface(
        onClick = onOpen,
        modifier = modifier.widthIn(max = 480.dp).fillMaxWidth().testTag("country-card"),
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = MaterialTheme.colorScheme.onSurface,
        shadowElevation = 4.dp,
    ) {
        Row(Modifier.padding(start = 16.dp, top = 12.dp, bottom = 12.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(country.flag, fontSize = 44.sp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                val title = if (source?.coverage == VisaCoverage.SchengenArea) {
                    stringResource(R.string.schengen_issued_by, state.countriesByCode[source.countryCode]?.localizedName(locale) ?: source.countryCode)
                } else stringResource(eligibility.category.label)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Surface(shape = androidx.compose.foundation.shape.CircleShape, color = eligibility.category.color) {
                        Spacer(Modifier.size(10.dp))
                    }
                    Text(title, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium)
                }
                (source?.duration ?: entry?.duration)?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                }
                source?.let {
                    Text(stringResource(R.string.expires, formatDate(it.expiryDate)), color = it.expiryColor(), style = MaterialTheme.typography.labelSmall)
                }
            }
            Box {
                IconButton(onClick = { menu = true }, modifier = Modifier.testTag("country-actions")) {
                    androidx.compose.material3.Icon(painter = androidx.compose.ui.res.painterResource(R.drawable.ic_more),
                        contentDescription = stringResource(R.string.country_actions))
                }
                androidx.compose.material3.DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    val hasPlans = state.data.plannedTripRecords.any { it.countryCode == code }
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text(stringResource(if (hasPlans) R.string.review_wishlist else R.string.add_wishlist)) },
                        onClick = { menu = false; if (hasPlans) onReviewWishlist() else onAddWishlist() },
                        modifier = Modifier.testTag("card-wishlist"),
                    )
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text(stringResource(R.string.log_visit)) },
                        onClick = { menu = false; onAddVisit() },
                        modifier = Modifier.testTag("card-log-visit"),
                    )
                    if (eligibility.category == VisaCategory.VisaRequired) {
                        androidx.compose.material3.DropdownMenuItem(
                            text = { Text(stringResource(R.string.add_visa)) },
                            leadingIcon = { AppIcon(R.drawable.ic_add) },
                            onClick = { menu = false; onAddVisa() },
                            modifier = Modifier.testTag("card-add-visa"),
                        )
                    }
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text(stringResource(R.string.search_on, state.searchEngine.displayName)) },
                        leadingIcon = { AppIcon(R.drawable.ic_search) },
                        onClick = {
                            menu = false
                            state.searchCountry(name)
                        },
                    )
                }
            }
            IconButton(onClick = onClose, modifier = Modifier.testTag("country-close")) {
                androidx.compose.material3.Icon(painter = androidx.compose.ui.res.painterResource(R.drawable.ic_close),
                    contentDescription = stringResource(R.string.close))
            }
        }
    }
}
