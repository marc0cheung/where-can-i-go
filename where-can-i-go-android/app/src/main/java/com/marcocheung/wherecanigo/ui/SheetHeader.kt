package com.marcocheung.wherecanigo.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.marcocheung.wherecanigo.R

/** Dice options, kept for the process like the iOS `@State` in ContentView. */
class DiceOptions {
    var continents by mutableStateOf(emptySet<Continent>())
    var airlines by mutableStateOf(emptySet<String>())
    var includeAll by mutableStateOf(false)

    companion object {
        val Saver = listSaver<DiceOptions, String>(
            save = { listOf(it.continents.joinToString(",") { continent -> continent.name },
                it.airlines.joinToString(","), it.includeAll.toString()) },
            restore = {
                DiceOptions().apply {
                    continents = it[0].split(",").filter(String::isNotEmpty).map(Continent::valueOf).toSet()
                    airlines = it[1].split(",").filter(String::isNotEmpty).toSet()
                    includeAll = it[2].toBoolean()
                }
            },
        )
    }
}

@Composable
fun SheetHeader(
    state: AppState,
    dice: DiceOptions,
    onDicePicked: (String) -> Unit,
    onOpenProfile: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var diceMenu by rememberSaveable { mutableStateOf(false) }
    Column(modifier) {
        Row(
            Modifier.fillMaxWidth().padding(start = 20.dp, end = 12.dp, top = 4.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.app_title), fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text(
                    passportLabel(state),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.testTag("passport-label"),
                )
            }
            DiceButton(state, dice, diceMenu, { diceMenu = it }, onDicePicked)
            Spacer(Modifier.width(8.dp))
            ProfileButton(onOpenProfile, onOpenSettings)
        }
        HorizontalDivider()
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DiceButton(state: AppState, dice: DiceOptions, menu: Boolean, onMenuChange: (Boolean) -> Unit, onPicked: (String) -> Unit) {
    var noMatch by remember { mutableStateOf(false) }
    var airlineError by remember { mutableStateOf(false) }
    val badge = dice.continents.size + dice.airlines.size
    val description = stringResource(R.string.random_country)
    val optionsDescription = stringResource(R.string.dice_options)
    val selectedOptions = buildList {
        add(if (dice.continents.isEmpty()) stringResource(R.string.all_continents)
            else dice.continents.joinToString { state.appContext.getString(it.label) })
        add(if (dice.airlines.isEmpty()) stringResource(R.string.no_airline_restriction) else
            state.airlines.orEmpty().filter { it.id in dice.airlines }.joinToString { it.name })
        add(stringResource(if (dice.includeAll) R.string.include_all_requirements else R.string.accessible_only))
    }.joinToString(", ")
    fun roll() {
        val airlines = state.airlines ?: run { airlineError = true; return }
        val destinations = airlines.filter { it.id in dice.airlines }.flatMap { it.destinationCountryCodes }.toSet()
        val eligible = state.countries.filter { country ->
            country.code != state.data.passportCode &&
                (dice.continents.isEmpty() || Continent.of(country.code) in dice.continents) &&
                (dice.airlines.isEmpty() || country.code in destinations) &&
                (dice.includeAll || state.eligibility(country.code).isAccessible)
        }
        val picked = eligible.randomOrNull() ?: run { noMatch = true; return }
        onPicked(picked.code)
    }
    Box {
        Surface(
            shape = CircleShape,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            modifier = Modifier.size(48.dp).clip(CircleShape)
                .combinedClickable(onClick = ::roll, onLongClickLabel = optionsDescription, onLongClick = { onMenuChange(true) })
                .semantics { contentDescription = description; stateDescription = selectedOptions }
                .testTag("dice-button"),
        ) {
            Box(contentAlignment = Alignment.Center) {
                AppIcon(
                    R.drawable.ic_dice,
                    Modifier.size(22.dp),
                    tint = if (dice.includeAll) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                )
            }
        }
        if (badge > 0) {
            Box(
                Modifier.align(Alignment.TopEnd).offset(x = 4.dp, y = (-4).dp).size(18.dp)
                    .clip(CircleShape).background(MaterialTheme.colorScheme.primary),
                contentAlignment = Alignment.Center,
            ) {
                Text("$badge", color = MaterialTheme.colorScheme.onPrimary, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { onMenuChange(false) }, modifier = Modifier.testTag("dice-menu")) {
            Header(stringResource(R.string.continent))
            Check(stringResource(R.string.all_continents), dice.continents.isEmpty()) { dice.continents = emptySet() }
            Continent.entries.forEach { continent ->
                Check(stringResource(continent.label), continent in dice.continents) {
                    dice.continents = if (continent in dice.continents) dice.continents - continent else dice.continents + continent
                }
            }
            val airlines = state.airlines.orEmpty()
            if (airlines.isNotEmpty()) {
                HorizontalDivider()
                Header(stringResource(R.string.airlines))
                Check(stringResource(R.string.no_airline_restriction), dice.airlines.isEmpty()) { dice.airlines = emptySet() }
                val allIds = airlines.map { it.id }.toSet()
                Check(stringResource(R.string.all_airlines), dice.airlines.containsAll(allIds)) {
                    dice.airlines = if (dice.airlines.containsAll(allIds)) emptySet() else allIds
                }
                airlines.forEach { airline ->
                    Check(airlineName(airline), airline.id in dice.airlines) {
                        dice.airlines = if (airline.id in dice.airlines) dice.airlines - airline.id else dice.airlines + airline.id
                    }
                }
            }
            HorizontalDivider()
            Check(stringResource(R.string.accessible_only), !dice.includeAll) { dice.includeAll = false }
            Check(stringResource(R.string.include_all_requirements), dice.includeAll) { dice.includeAll = !dice.includeAll }
        }
    }
    if (noMatch) {
        val close = { noMatch = false }
        AlertDialog(
            onDismissRequest = close,
            title = { Text(stringResource(R.string.no_matching_countries)) },
            text = { Text(stringResource(R.string.dice_no_match)) },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    if (dice.continents.isNotEmpty()) {
                        TextButton(onClick = { dice.continents = emptySet(); close() }) { Text(stringResource(R.string.all_continents)) }
                    }
                    if (dice.airlines.isNotEmpty()) {
                        TextButton(onClick = { dice.airlines = emptySet(); close() }) {
                            Text(stringResource(R.string.remove_airline_restriction))
                        }
                    }
                    TextButton(onClick = close) { Text(stringResource(R.string.ok)) }
                }
            },
        )
    }
    if (airlineError) {
        AlertDialog(
            onDismissRequest = { airlineError = false },
            title = { Text(stringResource(R.string.airline_unavailable)) },
            text = { Text(stringResource(R.string.airline_unavailable_body)) },
            confirmButton = { TextButton(onClick = { airlineError = false }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

@Composable
private fun Header(text: String) {
    Text(
        text,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun Check(text: String, checked: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(text) },
        onClick = onClick,
        leadingIcon = { Checkbox(checked = checked, onCheckedChange = null) },
    )
}

@Composable
private fun ProfileButton(onOpenProfile: () -> Unit, onOpenSettings: () -> Unit) {
    var menu by rememberSaveable { mutableStateOf(false) }
    val description = stringResource(R.string.profile)
    val profile = AppState.get(androidx.compose.ui.platform.LocalContext.current).profile
    Box {
        Surface(
            onClick = { menu = true },
            shape = CircleShape,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            modifier = Modifier.size(48.dp).testTag("profile-button")
                .semantics { contentDescription = description },
        ) {
            Box(contentAlignment = Alignment.Center) { Avatar(32, profile.photoData) }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.testTag("profile-menu")) {
            DropdownMenuItem(
                text = {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Avatar(48, profile.photoData)
                        Column {
                            Text(profile.name.ifBlank { stringResource(R.string.your_profile) }, fontWeight = FontWeight.SemiBold)
                            Text(stringResource(R.string.edit_profile), color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodySmall)
                        }
                    }
                },
                onClick = { menu = false; onOpenProfile() },
                modifier = Modifier.testTag("menu-profile"),
            )
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text(stringResource(R.string.settings)) },
                leadingIcon = { AppIcon(R.drawable.ic_settings) },
                onClick = { menu = false; onOpenSettings() },
                modifier = Modifier.testTag("menu-settings"),
            )
        }
    }
}

@Composable
fun Avatar(size: Int, photo: ByteArray? = null) {
    val bitmap = remember(photo) { photo?.let { decodeProfilePhoto(it, 512) } }
    Box(
        Modifier.size(size.dp).clip(CircleShape).background(MaterialTheme.colorScheme.secondaryContainer),
        contentAlignment = Alignment.Center,
    ) {
        if (bitmap != null) androidx.compose.foundation.Image(bitmap.asImageBitmap(), null,
            Modifier.size(size.dp), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
        else AppIcon(R.drawable.ic_person, Modifier.size((size * 0.6f).dp), tint = MaterialTheme.colorScheme.onSecondaryContainer)
    }
}
