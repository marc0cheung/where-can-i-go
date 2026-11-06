package com.marcocheung.wherecanigo.ui

import androidx.annotation.DrawableRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.marcocheung.wherecanigo.R
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

val ExpiredRed = Color(0xFFFF3B30)
val WarningOrange = Color(0xFFFF9500)
val LocateBlue = Color(0xFF007AFF)

@Composable
fun AppIcon(@DrawableRes icon: Int, modifier: Modifier = Modifier, tint: Color = Color.Unspecified) {
    Icon(
        painterResource(icon),
        contentDescription = null,
        modifier = modifier,
        tint = if (tint == Color.Unspecified) androidx.compose.material3.LocalContentColor.current else tint,
    )
}

@Composable
fun currentLocale(): Locale = LocalConfiguration.current.locales[0]

/** Same as iOS `.formatted(date: .abbreviated, time: .omitted)`. */
@Composable
fun formatDate(date: LocalDate): String =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(currentLocale()).format(date)

/** iOS uses en_GB for English so the bundled date reads "1 Jan 2026". */
@Composable
fun formatUpdatedDate(date: LocalDate): String {
    val locale = currentLocale().let { if (it.language == "en") Locale.UK else it }
    return DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).format(date)
}

@Composable
fun PersonalVisa.expiryColor(): Color {
    val today = LocalDate.now()
    return when {
        today.isAfter(expiryDate) -> ExpiredRed
        !today.isBefore(expiryDate.minusDays(31)) -> WarningOrange
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
}

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier = modifier.padding(start = 4.dp, bottom = 6.dp),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
fun FormCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) { content() }
    }
}

@Composable
fun FormTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = true,
    clearable: Boolean = false,
) {
    androidx.compose.material3.TextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        placeholder = { Text(placeholder) },
        singleLine = singleLine,
        minLines = if (singleLine) 1 else 3,
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.Sentences,
            imeAction = if (singleLine) ImeAction.Done else ImeAction.Default,
        ),
        trailingIcon = if (clearable && value.isNotEmpty()) {
            { IconButton(onClick = { onValueChange("") }) { AppIcon(R.drawable.ic_clear, Modifier.size(18.dp)) } }
        } else null,
        colors = androidx.compose.material3.TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent,
            unfocusedContainerColor = Color.Transparent,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
        ),
    )
}

/** Material editor with explicit cancel and commit actions. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FullScreenSheet(
    title: String,
    onCancel: () -> Unit,
    onDone: (() -> Unit)?,
    doneEnabled: Boolean = true,
    testTag: String? = null,
    content: @Composable () -> Unit,
) {
    Dialog(
        onDismissRequest = onCancel,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        Surface(
            Modifier.fillMaxSize().let { if (testTag != null) it.testTag(testTag) else it },
            color = MaterialTheme.colorScheme.surfaceContainer,
        ) {
            Column(Modifier.windowInsetsPadding(WindowInsets.safeDrawing).imePadding()) {
                TopAppBar(
                    windowInsets = WindowInsets(0),
                    title = { Text(title, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) },
                    navigationIcon = {
                        IconButton(onClick = onCancel, modifier = Modifier.testTag("sheet-cancel")) {
                            Icon(painterResource(R.drawable.ic_close), stringResource(R.string.cancel))
                        }
                    },
                    actions = {
                        if (onDone != null) {
                            TextButton(onClick = onDone, enabled = doneEnabled, modifier = Modifier.testTag("sheet-done")) {
                                Text(stringResource(R.string.done), fontWeight = FontWeight.SemiBold)
                            }
                        }
                    },
                )
                content()
            }
        }
    }
}

@Composable
fun CountryPickerSheet(
    countries: List<Country>,
    onSelect: (Country) -> Unit,
    onCancel: () -> Unit,
) {
    val locale = currentLocale()
    var search by rememberSaveable { mutableStateOf("") }
    FullScreenSheet(stringResource(R.string.select_country), onCancel, null) {
        OutlinedTextField(
            value = search,
            onValueChange = { search = it },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).testTag("picker-search"),
            placeholder = { Text(stringResource(R.string.search_countries)) },
            leadingIcon = { AppIcon(R.drawable.ic_search) },
            singleLine = true,
            shape = RoundedCornerShape(12.dp),
        )
        LazyColumn(Modifier.fillMaxSize()) {
            items(countries.filter { it.matches(search.trim(), locale) }, key = { it.code }) { country ->
                Row(
                    Modifier.fillMaxWidth().clickable { onSelect(country) }
                        .padding(horizontal = 20.dp, vertical = 12.dp)
                        .testTag("pick-${country.code}"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(country.flag, style = MaterialTheme.typography.titleLarge)
                    Spacer(Modifier.width(12.dp))
                    Text(country.localizedName(locale), style = MaterialTheme.typography.bodyLarge)
                }
                HorizontalDivider(Modifier.padding(start = 56.dp))
            }
        }
    }
}

/** Port of iOS `DateInputRow`: label, a tappable date, and an optional clear button. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateInputRow(
    label: String,
    date: LocalDate?,
    onDateChange: (LocalDate?) -> Unit,
    clearDescription: String,
    defaultDate: LocalDate = LocalDate.now(),
    minDate: LocalDate? = null,
    maxDate: LocalDate? = null,
    testTag: String,
) {
    var picking by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Surface(
            onClick = { picking = true },
            shape = RoundedCornerShape(8.dp),
            color = MaterialTheme.colorScheme.surfaceContainerHighest,
            modifier = Modifier.heightIn(min = 48.dp).testTag(testTag),
        ) {
            Text(
                date?.let { formatDate(it) } ?: stringResource(R.string.select_date),
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                color = if (date == null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
            )
        }
        if (date != null) {
            IconButton(onClick = { onDateChange(null) }) {
                Icon(
                    painterResource(R.drawable.ic_clear),
                    contentDescription = clearDescription,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
    if (picking) {
        val lower = minDate ?: LocalDate.of(minOf(1900, maxDate?.year ?: 1900), 1, 1)
        val upper = maxDate ?: LocalDate.of(maxOf(2100, minDate?.year ?: 2100), 12, 31)
        val initial = (date ?: defaultDate).coerceIn(lower, upper)
        val state = rememberDatePickerState(
            initialSelectedDateMillis = initial.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            yearRange = minOf(1900, lower.year)..maxOf(2100, upper.year),
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long): Boolean {
                    val day = Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate()
                    return (minDate == null || !day.isBefore(minDate)) && (maxDate == null || !day.isAfter(maxDate))
                }
            },
        )
        DatePickerDialog(
            onDismissRequest = { picking = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let {
                        onDateChange(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate())
                    }
                    picking = false
                }, enabled = state.selectedDateMillis?.let {
                    val day = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                    !day.isBefore(lower) && !day.isAfter(upper)
                } == true) { Text(stringResource(R.string.done)) }
            },
            dismissButton = { TextButton(onClick = { picking = false }) { Text(stringResource(R.string.cancel)) } },
        ) { DatePicker(state) }
    }
}

@Composable
fun passportLabel(state: AppState): String {
    val country = state.countriesByCode[state.data.passportCode]
    return stringResource(
        R.string.passport_label,
        country?.flag.orEmpty(),
        country?.localizedName(currentLocale()) ?: state.data.passportCode,
    )
}

@Composable
fun airlineName(airline: Airline): String = when (airline.id) {
    "CX" -> stringResource(R.string.airline_CX)
    "UO" -> stringResource(R.string.airline_UO)
    else -> airline.name
}
