package com.marcocheung.wherecanigo.ui

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.marcocheung.wherecanigo.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException

private const val repositoryURL = "https://github.com/marc0cheung/where-can-i-go"
private const val instagramHandle = "wherecanigo_app"

/** Settings destinations, mirroring the iOS `SettingsView` navigation stack. */
private enum class SettingsSection(val depth: Int, val title: Int) {
    Main(0, R.string.settings),
    Sharing(1, R.string.sharing),
    Export(1, R.string.export_data),
    Import(1, R.string.import_preview),
    Faq(1, R.string.faq),
    Feedback(1, R.string.send_feedback),
    About(1, R.string.about),
    Privacy(1, R.string.privacy_policy),
    Sources(2, R.string.acknowledgements_sources),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppSettingsPage(state: AppState, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var section by rememberSaveable { mutableStateOf(SettingsSection.Main) }
    var includePhoto by rememberSaveable { mutableStateOf(true) }
    var includeAttachments by rememberSaveable { mutableStateOf(true) }
    var includeFriends by rememberSaveable { mutableStateOf(false) }
    var includeIdentity by rememberSaveable { mutableStateOf(false) }
    var importUri by rememberSaveable { mutableStateOf<String?>(null) }
    var document by remember { mutableStateOf<BackupDocument?>(null) }
    var plan by remember { mutableStateOf<RestorePlan?>(null) }
    var replacing by rememberSaveable { mutableStateOf(false) }
    var confirm by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var result by rememberSaveable { mutableStateOf<String?>(null) }
    val identityAvailable = remember {
        try { SharingIdentity.current(context) != null }
        catch (failure: Exception) {
            state.reportError(R.string.identity_access_error, failure)
            false
        }
    }
    fun clearImport() { importUri = null; document = null; plan = null }
    val back = {
        if (!busy) when (section) {
            SettingsSection.Main -> onBack()
            SettingsSection.Sources -> section = SettingsSection.About
            SettingsSection.Import -> { clearImport(); section = SettingsSection.Main }
            else -> section = SettingsSection.Main
        }
    }
    BackHandler(onBack = back)
    val exportResultText = stringResource(R.string.backup_exported)
    val skipText = stringResource(R.string.backup_skipped)
    val restoreResultText = stringResource(R.string.backup_restored)
    val openLink: (String) -> Unit = { url ->
        try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        catch (failure: ActivityNotFoundException) { state.reportError(R.string.browser_unavailable, failure) }
    }
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) {
            busy = true
            scope.launch {
                try {
                    val skipped = withContext(NonCancellable + Dispatchers.IO) {
                        val (bytes, skipped) = UserDataBackup.export(context, state.data, state.profile,
                            includePhoto, includeAttachments, includeFriends, includeIdentity)
                        context.contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
                            ?: throw IOException("Cannot write backup")
                        skipped
                    }
                    result = "$exportResultText\n$skipText: $skipped"
                    section = SettingsSection.Main
                } catch (failure: Exception) { state.reportError(R.string.backup_export_error, failure) }
                finally { busy = false }
            }
        }
    }
    val import = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            try { context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            catch (failure: SecurityException) { android.util.Log.w("Backup", "Provider did not grant persistent read permission", failure) }
            importUri = uri.toString(); result = null; plan = null; document = null; replacing = false
        }
    }
    LaunchedEffect(importUri) {
        val uri = importUri ?: return@LaunchedEffect
        busy = true
        try {
            document = withContext(Dispatchers.IO) {
                context.contentResolver.openInputStream(Uri.parse(uri))?.use(UserDataBackup::decode)
                    ?: throw IOException("Cannot read backup")
            }
            section = SettingsSection.Import
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (failure: Exception) { state.reportError(R.string.backup_import_error, failure); importUri = null }
        finally { busy = false }
    }
    LaunchedEffect(document, replacing) {
        val backup = document ?: return@LaunchedEffect
        busy = true
        try {
            plan = withContext(Dispatchers.IO) {
                UserDataBackup.plan(context, backup, state.data, state.profile,
                    replacing, state.friendStore.friends, identityAvailable)
            }
        }
        catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (failure: Exception) {
            state.reportError(R.string.backup_import_error, failure)
            clearImport(); section = SettingsSection.Main
        }
        finally { busy = false }
    }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        Modifier.nestedScroll(scrollBehavior.nestedScrollConnection).testTag("page-settings"),
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        topBar = {
            LargeTopAppBar(
                title = {
                    AnimatedContent(section.title, transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(120)) },
                        label = "settings-title") { Text(stringResource(it), maxLines = 1) }
                },
                navigationIcon = {
                    IconButton(onClick = back, enabled = !busy, modifier = Modifier.testTag("page-back")) {
                        Icon(painterResource(if (section == SettingsSection.Main) R.drawable.ic_close else R.drawable.ic_arrow_back),
                            stringResource(if (section == SettingsSection.Main) R.string.close else R.string.back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                    scrolledContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                ),
                scrollBehavior = scrollBehavior,
            )
        },
    ) { padding ->
        AnimatedContent(
            targetState = section,
            modifier = Modifier.padding(padding).fillMaxSize(),
            transitionSpec = {
                // Shared X-axis: deeper pages enter from the end, going back reverses.
                val direction = if (targetState.depth >= initialState.depth) 1 else -1
                (slideInHorizontally(tween(320, easing = FastOutSlowInEasing)) { direction * it / 5 } +
                    fadeIn(tween(210, delayMillis = 90, easing = LinearOutSlowInEasing))) togetherWith
                    (slideOutHorizontally(tween(320, easing = FastOutSlowInEasing)) { -direction * it / 5 } +
                        fadeOut(tween(90, easing = FastOutLinearInEasing)))
            },
            label = "settings-section",
        ) { current ->
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp).padding(bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                when (current) {
                    SettingsSection.Main -> MainSettings(
                        state, busy = busy, reading = importUri != null && document == null, result = result,
                        onNavigate = { section = it },
                        onImport = { import.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) },
                    )
                    SettingsSection.Sharing -> SharingSettings(state)
                    SettingsSection.Export -> ExportSettings(
                        state, busy, identityAvailable,
                        includePhoto, { includePhoto = it }, includeAttachments, { includeAttachments = it },
                        includeFriends, { includeFriends = it }, includeIdentity, { includeIdentity = it },
                        onExport = { export.launch("wherecanigo-backup-${java.time.LocalDate.now()}.json") },
                    )
                    SettingsSection.Import -> ImportSettings(
                        plan, busy, replacing, skipText,
                        onReplacing = { if (it != replacing) { replacing = it; plan = null } },
                        onRestore = { confirm = true },
                    )
                    SettingsSection.Faq -> FaqSettings(onFeedback = { section = SettingsSection.Feedback })
                    SettingsSection.Feedback -> FeedbackSettings(openLink)
                    SettingsSection.About -> AboutSettings(openLink, onSources = { section = SettingsSection.Sources })
                    SettingsSection.Privacy -> PrivacySettings()
                    SettingsSection.Sources -> SourcesSettings(openLink)
                }
            }
        }
    }
    if (confirm) AlertDialog(onDismissRequest = { if (!busy) confirm = false },
        icon = { AppIcon(R.drawable.ic_download) },
        title = { Text(stringResource(R.string.restore_data)) },
        text = { Text(stringResource(if (replacing) R.string.replace_confirm else R.string.merge_confirm)) },
        confirmButton = { TextButton(enabled = !busy, onClick = {
            val ready = plan ?: return@TextButton
            busy = true
            scope.launch {
                try {
                    val success = withContext(NonCancellable + Dispatchers.IO) { UserDataBackup.restore(context, state, ready) }
                    if (success) {
                        result = "$restoreResultText\n$skipText: ${ready.skippedMedia + ready.skippedRecords}"
                        clearImport(); confirm = false; section = SettingsSection.Main
                    }
                } catch (failure: Exception) { state.reportError(R.string.backup_import_error, failure) }
                finally { busy = false }
            }
        }) { Text(stringResource(R.string.restore_data)) } },
        dismissButton = { TextButton(enabled = !busy, onClick = { confirm = false }) { Text(stringResource(R.string.cancel)) } })
}

@Composable
private fun MainSettings(
    state: AppState,
    busy: Boolean,
    reading: Boolean,
    result: String?,
    onNavigate: (SettingsSection) -> Unit,
    onImport: () -> Unit,
) {
    val context = LocalContext.current
    SettingsGroup(stringResource(R.string.general)) {
        var menu by remember { mutableStateOf(false) }
        Box {
            SettingsRow(
                R.drawable.ic_search, stringResource(R.string.search_engine), groupedShape(0, 1),
                tag = "settings-search-engine", enabled = !busy, onClick = { menu = true },
                trailing = {
                    Text(state.searchEngine.displayName, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Medium)
                    AppIcon(R.drawable.ic_dropdown, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
                },
            )
            AppDropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.align(Alignment.TopEnd)) {
                SearchEngine.entries.forEach { engine ->
                    val selected = state.searchEngine == engine
                    DropdownMenuItem(
                        text = { Text(engine.displayName, fontWeight = if (selected) FontWeight.SemiBold else null) },
                        leadingIcon = { RadioButton(selected = selected, onClick = null) },
                        onClick = { state.chooseSearchEngine(engine); menu = false },
                        modifier = Modifier.testTag("search-engine-${engine.name}"),
                    )
                }
            }
        }
    }
    SettingsGroup(stringResource(R.string.friends), footer = stringResource(R.string.sharing_footer)) {
        SettingsRow(R.drawable.ic_group, stringResource(R.string.sharing), groupedShape(0, 1),
            tag = "settings-sharing", enabled = !busy, chevron = true) { onNavigate(SettingsSection.Sharing) }
    }
    SettingsGroup(stringResource(R.string.manage_data), footer = result, footerTag = "backup-result") {
        SettingsRow(R.drawable.ic_upload, stringResource(R.string.export_data), groupedShape(0, 2),
            tag = "settings-backup", enabled = !busy && !state.profileLoadFailed, chevron = true) { onNavigate(SettingsSection.Export) }
        SettingsRow(R.drawable.ic_download, stringResource(R.string.import_data), groupedShape(1, 2),
            tag = "backup-import", enabled = !busy && !state.profileLoadFailed, onClick = onImport,
            trailing = if (reading) ({ CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }) else null)
    }
    SettingsGroup(stringResource(R.string.support)) {
        SettingsRow(R.drawable.ic_help, stringResource(R.string.faq), groupedShape(0, 2),
            tag = "settings-faq", enabled = !busy, chevron = true) { onNavigate(SettingsSection.Faq) }
        SettingsRow(R.drawable.ic_send, stringResource(R.string.send_feedback), groupedShape(1, 2),
            tag = "settings-feedback", enabled = !busy, chevron = true) { onNavigate(SettingsSection.Feedback) }
    }
    val info = remember { context.packageManager.getPackageInfo(context.packageName, 0) }
    Column {
        SettingsGroup(stringResource(R.string.about)) {
            SettingsRow(R.drawable.ic_info, stringResource(R.string.about), groupedShape(0, 2),
                tag = "settings-about", enabled = !busy, chevron = true) { onNavigate(SettingsSection.About) }
            SettingsRow(R.drawable.ic_shield, stringResource(R.string.privacy_policy), groupedShape(1, 2),
                tag = "settings-privacy", enabled = !busy, chevron = true) { onNavigate(SettingsSection.Privacy) }
        }
        Column(Modifier.fillMaxWidth().padding(top = 16.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp)) {
            FooterText(stringResource(R.string.version_build, info.versionName.orEmpty(), info.longVersionCode), center = true)
            state.bundledUpdatedAt?.let { FooterText(stringResource(R.string.policy_updated, formatUpdatedDate(it)), center = true) }
        }
    }
}

@Composable
private fun SharingSettings(state: AppState) {
    val context = LocalContext.current
    var options by remember { mutableStateOf(SharingOptions.load(context)) }
    var identity by remember { mutableStateOf<SigningIdentity?>(null) }
    var identityError by remember { mutableStateOf<String?>(null) }
    var confirmReset by remember { mutableStateOf(false) }
    val identityAccessError = stringResource(R.string.identity_access_error)
    LaunchedEffect(Unit) {
        try { identity = SharingIdentity.current(context) }
        catch (failure: Exception) { identityError = failure.localizedMessage ?: identityAccessError }
    }
    fun update(next: SharingOptions) {
        options = next
        try { SharingOptions.save(context, next) } catch (failure: Exception) { state.reportError(R.string.save_data_error, failure) }
    }
    FooterText(stringResource(R.string.sharing_defaults_intro), Modifier.padding(top = 4.dp))
    SettingsGroup(stringResource(R.string.travel_card)) {
        Surface(shape = groupedShape(0, 2), color = listItemColor(), modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
                options.displayName, { update(options.copy(displayName = it.take(60))) },
                label = { Text(stringResource(R.string.display_name)) },
                placeholder = { Text(state.profile.name) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(16.dp).testTag("sharing-name"),
            )
        }
        SwitchRow(R.drawable.ic_photo, stringResource(R.string.include_photo), options.includePhoto, groupedShape(1, 2),
            enabled = state.profile.photoData != null) { update(options.copy(includePhoto = it)) }
    }
    ShareCategoryGroup(R.drawable.ic_pin, stringResource(R.string.share_been), options.includeBeen, options.beenFields,
        { update(options.copy(includeBeen = it)) }, { update(options.copy(beenFields = it)) })
    ShareCategoryGroup(R.drawable.ic_favorite, stringResource(R.string.share_wishlist), options.includeWishlist, options.wishlistFields,
        { update(options.copy(includeWishlist = it)) }, { update(options.copy(wishlistFields = it)) })
    SettingsGroup(stringResource(R.string.kept_on_device), footer = stringResource(R.string.travel_card_kept_private)) {
        SettingsRow(R.drawable.ic_notes, stringResource(R.string.notes_title), groupedShape(0, 3))
        SettingsRow(R.drawable.ic_passport, stringResource(R.string.passport), groupedShape(1, 3))
        SettingsRow(R.drawable.ic_doc, stringResource(R.string.visas_and_attachments), groupedShape(2, 3))
    }
    SettingsGroup(stringResource(R.string.sharing_identity), footer = stringResource(R.string.identity_explanation)) {
        val current = identity
        when {
            current != null -> {
                SettingsRow(R.drawable.ic_key, stringResource(R.string.safety_code_title), groupedShape(0, 2), trailing = {
                    Text(TravelCardCrypto.safetyCode(current.publicKey), fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodyLarge, modifier = Modifier.testTag("safety-code"))
                })
                SettingsRow(R.drawable.ic_refresh, stringResource(R.string.reset_safety_code), groupedShape(1, 2),
                    tag = "reset-safety-code", destructive = true) { confirmReset = true }
            }
            else -> Surface(shape = groupedShape(0, 1), color = listItemColor(), modifier = Modifier.fillMaxWidth()) {
                Text(identityError ?: stringResource(R.string.identity_not_created), Modifier.padding(16.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
    if (confirmReset) AlertDialog(
        onDismissRequest = { confirmReset = false },
        icon = { AppIcon(R.drawable.ic_warning) },
        title = { Text(stringResource(R.string.reset_safety_code)) },
        text = { Text(stringResource(R.string.reset_identity_warning)) },
        confirmButton = {
            TextButton(onClick = {
                try { SharingIdentity.reset(context); identity = null; identityError = null }
                catch (failure: Exception) { identityError = failure.localizedMessage ?: identityAccessError }
                confirmReset = false
            }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text(stringResource(R.string.reset)) }
        },
        dismissButton = { TextButton(onClick = { confirmReset = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ShareCategoryGroup(
    @DrawableRes icon: Int,
    title: String,
    checked: Boolean,
    fields: TravelCardFields,
    onChecked: (Boolean) -> Unit,
    onFields: (TravelCardFields) -> Unit,
) {
    SettingsGroup(null) {
        SwitchRow(icon, title, checked, if (checked) groupedShape(0, 2) else groupedShape(0, 1), onChecked = onChecked)
        AnimatedVisibility(checked, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
            Surface(shape = groupedShape(1, 2), color = listItemColor(), modifier = Modifier.fillMaxWidth().padding(top = GroupedListGap)) {
                FlowRow(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(
                        R.string.share_dates to fields.dates,
                        R.string.share_length to fields.length,
                        R.string.share_location to fields.location,
                        R.string.share_purpose to fields.purpose,
                    ).forEach { (label, value) ->
                        FilterChip(value, onClick = {
                            onFields(when (label) {
                                R.string.share_dates -> fields.copy(dates = !value)
                                R.string.share_length -> fields.copy(length = !value)
                                R.string.share_location -> fields.copy(location = !value)
                                else -> fields.copy(purpose = !value)
                            })
                        }, label = { Text(stringResource(label)) },
                            leadingIcon = if (value) ({ AppIcon(R.drawable.ic_check, Modifier.size(FilterChipDefaults.IconSize)) }) else null)
                    }
                }
            }
        }
    }
}

@Composable
private fun ExportSettings(
    state: AppState,
    busy: Boolean,
    identityAvailable: Boolean,
    includePhoto: Boolean, onPhoto: (Boolean) -> Unit,
    includeAttachments: Boolean, onAttachments: (Boolean) -> Unit,
    includeFriends: Boolean, onFriends: (Boolean) -> Unit,
    includeIdentity: Boolean, onIdentity: (Boolean) -> Unit,
    onExport: () -> Unit,
) {
    FooterText(stringResource(R.string.backup_intro), Modifier.padding(top = 4.dp))
    SettingsGroup(null) {
        SwitchRow(R.drawable.ic_person, stringResource(R.string.include_profile_photo), includePhoto, groupedShape(0, 2),
            enabled = !busy, onChecked = onPhoto)
        SwitchRow(R.drawable.ic_attach, stringResource(R.string.include_attachments), includeAttachments, groupedShape(1, 2),
            enabled = !busy, onChecked = onAttachments)
    }
    SettingsGroup(stringResource(R.string.friends)) {
        SwitchRow(R.drawable.ic_group, stringResource(R.string.include_friends, state.friendStore.friends.size), includeFriends,
            groupedShape(0, 2), enabled = !busy && state.friendStore.friends.isNotEmpty() && !state.friendStore.loadFailed,
            onChecked = onFriends)
        SwitchRow(R.drawable.ic_key, stringResource(R.string.include_sharing_identity), includeIdentity, groupedShape(1, 2),
            enabled = !busy && identityAvailable, onChecked = onIdentity)
        if (includeFriends) WarningText(stringResource(R.string.backup_friends_warning), error = false)
        if (includeIdentity) WarningText(stringResource(R.string.backup_identity_warning), error = true)
    }
    Button(onClick = onExport, enabled = !busy && !state.profileLoadFailed,
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).testTag("backup-export")) {
        if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = LocalContentColor.current)
        else {
            AppIcon(R.drawable.ic_upload, Modifier.size(ButtonDefaults.IconSize))
            Spacer(Modifier.width(ButtonDefaults.IconSpacing))
            Text(stringResource(R.string.export_data))
        }
    }
}

@Composable
private fun ImportSettings(
    plan: RestorePlan?,
    busy: Boolean,
    replacing: Boolean,
    skipText: String,
    onReplacing: (Boolean) -> Unit,
    onRestore: () -> Unit,
) {
    SettingsGroup(null, footer = stringResource(if (replacing) R.string.replace_explanation else R.string.merge_explanation)) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            listOf(false to R.string.merge_data, true to R.string.replace_data).forEachIndexed { index, (value, label) ->
                SegmentedButton(
                    selected = replacing == value,
                    onClick = { onReplacing(value) },
                    enabled = !busy,
                    shape = SegmentedButtonDefaults.itemShape(index, 2),
                    modifier = Modifier.testTag(if (value) "backup-replace" else "backup-merge"),
                ) { Text(stringResource(label)) }
            }
        }
    }
    if (plan == null) {
        Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    val lines = buildList {
        add(R.drawable.ic_visa to stringResource(R.string.restore_counts, plan.data.personalVisas.size,
            plan.data.visitRecords.size, plan.data.plannedTripRecords.size))
        plan.friends?.let { add(R.drawable.ic_group to stringResource(R.string.restore_friend_count, it.size)) }
        if (plan.sharingIdentity != null) add(R.drawable.ic_key to stringResource(R.string.restore_identity_included))
        add(R.drawable.ic_passport to stringResource(R.string.passport) + ": " + plan.data.passportCode)
        add(R.drawable.ic_warning to "$skipText: ${plan.skippedRecords + plan.skippedMedia}")
    }
    SettingsGroup(stringResource(R.string.import_preview)) {
        lines.forEachIndexed { index, (icon, text) -> SettingsRow(icon, text, groupedShape(index, lines.size)) }
    }
    Button(onClick = onRestore, enabled = !busy,
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).testTag("backup-restore")) {
        AppIcon(R.drawable.ic_download, Modifier.size(ButtonDefaults.IconSize))
        Spacer(Modifier.width(ButtonDefaults.IconSpacing))
        Text(stringResource(R.string.restore_data))
    }
}

@Composable
private fun FaqSettings(onFeedback: () -> Unit) {
    val items = listOf(R.string.faq_colors_q to R.string.faq_colors_a, R.string.faq_accuracy_q to R.string.faq_accuracy_a,
        R.string.faq_passport_q to R.string.faq_passport_a, R.string.faq_visa_q to R.string.faq_visa_a,
        R.string.faq_travel_q to R.string.faq_travel_a, R.string.faq_data_q to R.string.faq_data_a,
        R.string.faq_dice_q to R.string.faq_dice_a)
    SettingsGroup(null) {
        items.forEachIndexed { index, (q, a) ->
            var expanded by rememberSaveable(q) { mutableStateOf(false) }
            val rotation by animateFloatAsState(if (expanded) 180f else 0f, label = "faq-chevron")
            Surface(onClick = { expanded = !expanded }, shape = groupedShape(index, items.size), color = listItemColor(),
                modifier = Modifier.fillMaxWidth().testTag("faq-$q")) {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(q), Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
                        AppIcon(R.drawable.ic_dropdown, Modifier.padding(start = 8.dp).rotate(rotation),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    AnimatedVisibility(expanded, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
                        Text(stringResource(a), Modifier.padding(top = 8.dp), style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
    SettingsGroup(null, footer = stringResource(R.string.faq_footer)) {
        SettingsRow(R.drawable.ic_send, stringResource(R.string.send_feedback), groupedShape(0, 1),
            tag = "faq-feedback", chevron = true, onClick = onFeedback)
    }
}

@Composable
private fun FeedbackSettings(openLink: (String) -> Unit) {
    val context = LocalContext.current
    val copied = stringResource(R.string.diagnostics_copied)
    val language = androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    SettingsGroup(null, footer = stringResource(R.string.feedback_intro)) {
        SettingsRow(R.drawable.ic_code, stringResource(R.string.open_github_issue), groupedShape(0, 1),
            tag = "feedback-github", external = true) { openLink("$repositoryURL/issues/new") }
    }
    SettingsGroup(null, footer = stringResource(R.string.feedback_privacy)) {
        SettingsRow(R.drawable.ic_copy, stringResource(R.string.copy_diagnostics), groupedShape(0, 1), tag = "feedback-diagnostics") {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            val diagnostics = "App: ${info.versionName} (${info.longVersionCode})\nAndroid: ${android.os.Build.VERSION.RELEASE}\n" +
                "Device: ${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}\nLanguage: $language"
            context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Diagnostics", diagnostics))
            if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU)
                Toast.makeText(context, copied, Toast.LENGTH_SHORT).show()
        }
    }
}

@Composable
private fun AboutSettings(openLink: (String) -> Unit, onSources: () -> Unit) {
    val context = LocalContext.current
    val info = remember { context.packageManager.getPackageInfo(context.packageName, 0) }
    Column(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(88.dp).clip(RoundedCornerShape(28.dp)).background(MaterialTheme.colorScheme.primaryContainer),
            contentAlignment = Alignment.Center) {
            AppIcon(R.drawable.ic_globe, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
        }
        Spacer(Modifier.height(4.dp))
        Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.version_build, info.versionName.orEmpty(), info.longVersionCode),
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Surface(shape = groupedShape(0, 1), color = listItemColor(), modifier = Modifier.fillMaxWidth()) {
        Text(stringResource(R.string.about_intro), Modifier.padding(16.dp), style = MaterialTheme.typography.bodyLarge)
    }
    SettingsGroup(stringResource(R.string.follow_us)) {
        SettingsRow(R.drawable.ic_camera, stringResource(R.string.instagram), groupedShape(0, 2), supporting = "@$instagramHandle",
            tag = "about-instagram", external = true) { openLink("https://www.instagram.com/$instagramHandle/") }
        SettingsRow(R.drawable.ic_code, stringResource(R.string.source_code_github), groupedShape(1, 2),
            tag = "about-source", external = true) { openLink(repositoryURL) }
    }
    SettingsGroup(null) {
        SettingsRow(R.drawable.ic_favorite, stringResource(R.string.acknowledgements_sources), groupedShape(0, 2),
            tag = "about-sources", chevron = true, onClick = onSources)
        SettingsRow(R.drawable.ic_doc, stringResource(R.string.license), groupedShape(1, 2), tag = "about-license",
            onClick = { openLink("$repositoryURL/blob/main/LICENSE") }, trailing = {
                Text("MIT", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                AppIcon(R.drawable.ic_open_in_new, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            })
    }
}

@Composable
private fun PrivacySettings() {
    val paragraphs = listOf(
        R.drawable.ic_lock to R.string.privacy_local,
        R.drawable.ic_photo to R.string.privacy_photos,
        R.drawable.ic_globe to R.string.privacy_network,
        R.drawable.ic_upload to R.string.privacy_backup,
        R.drawable.ic_settings to R.string.privacy_system,
    )
    SettingsGroup(null) {
        paragraphs.forEachIndexed { index, (icon, text) ->
            Surface(shape = groupedShape(index, paragraphs.size), color = listItemColor(), modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    IconBadge(icon)
                    Text(stringResource(text), style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

@Composable
private fun SourcesSettings(openLink: (String) -> Unit) {
    FooterText(stringResource(R.string.sources_intro), Modifier.padding(top = 4.dp))
    val policy = listOf(
        Triple(R.string.source_hkg, "source-hkg", "https://www.immd.gov.hk/hkt/service/travel_document/visa_free_access.html"),
        Triple(R.string.source_mac, "source-mac", "https://www.dsi.gov.mo/en/visa"),
        Triple(R.string.policy_sources, "source-policy", "$repositoryURL/tree/main/where-can-i-go-ios/whereCanIGo/Resources/Source"),
    )
    SettingsGroup(stringResource(R.string.policy_sources), footer = stringResource(R.string.wikipedia_attribution)) {
        policy.forEachIndexed { index, (label, tag, url) ->
            SettingsRow(R.drawable.ic_doc, stringResource(label), groupedShape(index, policy.size), tag = tag, external = true) { openLink(url) }
        }
    }
    SettingsGroup(stringResource(R.string.third_party_licenses)) {
        SettingsRow(R.drawable.ic_globe, stringResource(R.string.country_boundaries), groupedShape(0, 2),
            supporting = "Natural Earth / datasets/geo-countries · PDDL 1.0", tag = "source-map", external = true) {
            openLink("https://github.com/datasets/geo-countries")
        }
        SettingsRow(R.drawable.ic_code, stringResource(R.string.maplibre_license), groupedShape(1, 2),
            supporting = "MapLibre Native · BSD 2-Clause\nAndroidX / Jetpack Compose · Apache 2.0", tag = "source-maplibre", external = true) {
            openLink("https://github.com/maplibre/maplibre-native/blob/main/LICENSE.md")
        }
    }
}

/** An M3 Expressive grouped list section: header label, tightly-gapped rows and an optional footer. */
@Composable
private fun SettingsGroup(
    title: String?,
    footer: String? = null,
    footerTag: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column {
        title?.let {
            Text(it, Modifier.padding(start = 16.dp, bottom = 8.dp), style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
        }
        Column(verticalArrangement = Arrangement.spacedBy(GroupedListGap), content = content)
        footer?.let {
            FooterText(it, Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp)
                .then(if (footerTag != null) Modifier.testTag(footerTag) else Modifier))
        }
    }
}

@Composable
private fun SettingsRow(
    @DrawableRes icon: Int,
    title: String,
    shape: Shape,
    supporting: String? = null,
    tag: String? = null,
    enabled: Boolean = true,
    chevron: Boolean = false,
    external: Boolean = false,
    destructive: Boolean = false,
    trailing: (@Composable RowScope.() -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    val modifier = Modifier.fillMaxWidth().then(if (tag != null) Modifier.testTag(tag) else Modifier)
    val body: @Composable () -> Unit = {
        Row(
            Modifier.heightIn(min = 64.dp).padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            IconBadge(icon, destructive)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = MaterialTheme.typography.bodyLarge,
                    color = if (destructive) MaterialTheme.colorScheme.error else Color.Unspecified)
                supporting?.let {
                    Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (trailing != null) Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp), content = trailing)
            if (chevron) AppIcon(R.drawable.ic_chevron_right, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            if (external) AppIcon(R.drawable.ic_open_in_new, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (onClick != null) Surface(onClick = onClick, enabled = enabled, shape = shape, color = listItemColor(),
        modifier = modifier) { Box(Modifier.disabledAlpha(enabled)) { body() } }
    else Surface(shape = shape, color = listItemColor(), modifier = modifier) { body() }
}

@Composable
private fun SwitchRow(
    @DrawableRes icon: Int,
    title: String,
    checked: Boolean,
    shape: Shape,
    enabled: Boolean = true,
    onChecked: (Boolean) -> Unit,
) {
    Surface(
        checked = checked, onCheckedChange = onChecked, enabled = enabled, shape = shape, color = listItemColor(),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            Modifier.heightIn(min = 64.dp).padding(horizontal = 16.dp, vertical = 12.dp).disabledAlpha(enabled),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            IconBadge(icon)
            Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
            Switch(
                checked = checked, onCheckedChange = null, enabled = enabled,
                thumbContent = if (checked) ({ AppIcon(R.drawable.ic_check, Modifier.size(SwitchDefaults.IconSize)) }) else null,
            )
        }
    }
}

@Composable
private fun IconBadge(@DrawableRes icon: Int, destructive: Boolean = false) {
    val container = if (destructive) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.secondaryContainer
    val content = if (destructive) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onSecondaryContainer
    Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(container), contentAlignment = Alignment.Center) {
        AppIcon(icon, Modifier.size(22.dp), tint = content)
    }
}

@Composable
private fun FooterText(text: String, modifier: Modifier = Modifier, center: Boolean = false) {
    Text(text, modifier, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = if (center) TextAlign.Center else null)
}

@Composable
private fun WarningText(text: String, error: Boolean) {
    Row(Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        AppIcon(R.drawable.ic_warning, Modifier.size(16.dp),
            tint = if (error) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text, style = MaterialTheme.typography.bodySmall,
            color = if (error) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun Modifier.disabledAlpha(enabled: Boolean) = if (enabled) this else alpha(0.38f)
