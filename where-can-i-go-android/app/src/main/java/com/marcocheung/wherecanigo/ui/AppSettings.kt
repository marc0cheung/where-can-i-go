package com.marcocheung.wherecanigo.ui

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.marcocheung.wherecanigo.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException

private const val repositoryURL = "https://github.com/marc0cheung/where-can-i-go"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppSettingsPage(state: AppState, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var section by rememberSaveable { mutableStateOf("main") }
    var includePhoto by rememberSaveable { mutableStateOf(true) }
    var includeAttachments by rememberSaveable { mutableStateOf(true) }
    var importUri by rememberSaveable { mutableStateOf<String?>(null) }
    var document by remember { mutableStateOf<BackupDocument?>(null) }
    var plan by remember { mutableStateOf<RestorePlan?>(null) }
    var replacing by rememberSaveable { mutableStateOf(false) }
    var confirm by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var result by rememberSaveable { mutableStateOf<String?>(null) }
    val back = { if (!busy) { if (section == "main") onBack() else { section = "main"; importUri = null; document = null; plan = null } } }
    BackHandler(onBack = back)
    val exportResultText = stringResource(R.string.backup_exported)
    val skipText = stringResource(R.string.backup_skipped)
    val restoreResultText = stringResource(R.string.backup_restored)
    fun openLink(url: String) {
        try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        catch (failure: ActivityNotFoundException) { state.reportError(R.string.browser_unavailable, failure) }
    }
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) {
            busy = true
            scope.launch {
                try {
                    val skipped = withContext(NonCancellable + Dispatchers.IO) {
                        val (bytes, skipped) = UserDataBackup.export(context, state.data, state.profile, includePhoto, includeAttachments)
                        context.contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
                            ?: throw IOException("Cannot write backup")
                        skipped
                    }
                    result = "$exportResultText\n$skipText: $skipped"
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
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (failure: FriendsBackupUnsupported) { state.reportError(R.string.backup_friends_unsupported, failure); importUri = null }
        catch (failure: Exception) { state.reportError(R.string.backup_import_error, failure); importUri = null }
        finally { busy = false }
    }
    LaunchedEffect(document, replacing) {
        val backup = document ?: return@LaunchedEffect
        busy = true
        try { plan = withContext(Dispatchers.IO) { UserDataBackup.plan(context, backup, state.data, state.profile, replacing) } }
        catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (failure: Exception) { state.reportError(R.string.backup_import_error, failure); document = null; importUri = null }
        finally { busy = false }
    }
    val title = when (section) {
        "backup" -> R.string.manage_data
        "faq" -> R.string.faq
        "feedback" -> R.string.send_feedback
        "about" -> R.string.about
        "privacy" -> R.string.privacy_policy
        "sources" -> R.string.acknowledgements
        else -> R.string.settings
    }
    Scaffold(Modifier.testTag("page-settings"), topBar = {
        TopAppBar(title = { Text(stringResource(title)) }, navigationIcon = {
            IconButton(onClick = back, enabled = !busy, modifier = Modifier.testTag("page-back")) {
                Icon(painterResource(R.drawable.ic_close), stringResource(R.string.back))
            }
        })
    }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            when (section) {
                "main" -> {
                    SectionLabel(stringResource(R.string.general))
                    Text(stringResource(R.string.search_engine), style = MaterialTheme.typography.titleMedium)
                    SearchEngine.entries.forEach { engine ->
                        Surface(onClick = { state.chooseSearchEngine(engine) }, color = MaterialTheme.colorScheme.surfaceContainer,
                            shape = MaterialTheme.shapes.large, modifier = Modifier.fillMaxWidth().testTag("search-engine-${engine.name}")) {
                            Row(Modifier.padding(12.dp)) {
                                RadioButton(state.searchEngine == engine, onClick = null)
                                Text(engine.displayName, Modifier.padding(start = 12.dp))
                            }
                        }
                    }
                    SettingLink(R.string.manage_data, "settings-backup") { section = "backup" }
                    SectionLabel(stringResource(R.string.support))
                    SettingLink(R.string.faq, "settings-faq") { section = "faq" }
                    SettingLink(R.string.send_feedback, "settings-feedback") { section = "feedback" }
                    SectionLabel(stringResource(R.string.about))
                    SettingLink(R.string.about, "settings-about") { section = "about" }
                    SettingLink(R.string.privacy_policy, "settings-privacy") { section = "privacy" }
                }
                "backup" -> {
                    Text(stringResource(R.string.backup_intro))
                    Row {
                        Checkbox(includePhoto, { includePhoto = it }, enabled = !busy)
                        Text(stringResource(R.string.include_profile_photo), Modifier.padding(top = 12.dp))
                    }
                    Row {
                        Checkbox(includeAttachments, { includeAttachments = it }, enabled = !busy)
                        Text(stringResource(R.string.include_attachments), Modifier.padding(top = 12.dp))
                    }
                    Button(onClick = { export.launch("wherecanigo-backup-${java.time.LocalDate.now()}.json") },
                        enabled = !busy && !state.profileLoadFailed, modifier = Modifier.fillMaxWidth().testTag("backup-export")) {
                        Text(stringResource(R.string.export_data))
                    }
                    OutlinedButton(onClick = { import.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) },
                        enabled = !busy && !state.profileLoadFailed, modifier = Modifier.fillMaxWidth().testTag("backup-import")) {
                        Text(stringResource(R.string.import_data))
                    }
                    if (busy) CircularProgressIndicator()
                    plan?.let { preview ->
                        SectionLabel(stringResource(R.string.import_preview))
                        Row {
                            FilterChip(!replacing, { replacing = false; plan = null }, label = { Text(stringResource(R.string.merge_data)) })
                            Spacer(Modifier.width(12.dp))
                            FilterChip(replacing, { replacing = true; plan = null }, label = { Text(stringResource(R.string.replace_data)) })
                        }
                        Text(stringResource(if (replacing) R.string.replace_explanation else R.string.merge_explanation))
                        Text(stringResource(R.string.restore_counts, preview.data.personalVisas.size,
                            preview.data.visitRecords.size, preview.data.plannedTripRecords.size))
                        Text("$skipText: ${preview.skippedRecords + preview.skippedMedia}")
                        Text(stringResource(R.string.passport) + ": " + preview.data.passportCode)
                        Button(onClick = { confirm = true }, enabled = !busy, modifier = Modifier.testTag("backup-restore")) {
                            Text(stringResource(R.string.restore_data))
                        }
                    }
                    result?.let { Text(it, modifier = Modifier.testTag("backup-result")) }
                }
                "faq" -> {
                    listOf(R.string.faq_colors_q to R.string.faq_colors_a, R.string.faq_accuracy_q to R.string.faq_accuracy_a,
                        R.string.faq_passport_q to R.string.faq_passport_a, R.string.faq_visa_q to R.string.faq_visa_a,
                        R.string.faq_travel_q to R.string.faq_travel_a, R.string.faq_data_q to R.string.faq_data_a,
                        R.string.faq_dice_q to R.string.faq_dice_a).forEach { (q, a) ->
                        var expanded by rememberSaveable(q) { mutableStateOf(false) }
                        SettingLink(q, "faq-$q") { expanded = !expanded }
                        if (expanded) Text(stringResource(a))
                    }
                }
                "feedback" -> {
                    Text(stringResource(R.string.feedback_intro))
                    Button(onClick = { openLink("$repositoryURL/issues/new") }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.open_github_issue))
                    }
                    OutlinedButton(onClick = {
                        val info = context.packageManager.getPackageInfo(context.packageName, 0)
                        val diagnostics = "App: ${info.versionName} (${info.longVersionCode})\nAndroid: ${android.os.Build.VERSION.RELEASE}\n" +
                            "Device: ${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}\nLanguage: ${context.resources.configuration.locales[0]}"
                        context.getSystemService(ClipboardManager::class.java)
                            .setPrimaryClip(ClipData.newPlainText("Diagnostics", diagnostics))
                    }) { Text(stringResource(R.string.copy_diagnostics)) }
                    Text(stringResource(R.string.feedback_privacy))
                }
                "about" -> {
                    Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineMedium)
                    val info = context.packageManager.getPackageInfo(context.packageName, 0)
                    Text(stringResource(R.string.version_build, info.versionName.orEmpty(), info.longVersionCode))
                    state.bundledUpdatedAt?.let { Text(stringResource(R.string.policy_updated, formatUpdatedDate(it))) }
                    Text(stringResource(R.string.about_intro))
                    SettingLink(R.string.source_code, "about-source") { openLink(repositoryURL) }
                    SettingLink(R.string.instagram, "about-instagram") { openLink("https://www.instagram.com/wherecanigo_app/") }
                    SettingLink(R.string.license, "about-license") { openLink("$repositoryURL/blob/main/LICENSE") }
                    SettingLink(R.string.acknowledgements, "about-sources") { section = "sources" }
                }
                "privacy" -> {
                    Text(stringResource(R.string.privacy_local))
                    Text(stringResource(R.string.privacy_photos))
                    Text(stringResource(R.string.privacy_network))
                    Text(stringResource(R.string.privacy_backup))
                    Text(stringResource(R.string.privacy_system))
                }
                "sources" -> {
                    Text(stringResource(R.string.sources_intro))
                    Text("Natural Earth / datasets/geo-countries · PDDL 1.0")
                    SettingLink(R.string.country_boundaries, "source-map") { openLink("https://github.com/datasets/geo-countries") }
                    Text("MapLibre Native · BSD 2-Clause\nAndroidX / Jetpack Compose · Apache 2.0")
                    SettingLink(R.string.maplibre_license, "source-maplibre") { openLink("https://github.com/maplibre/maplibre-native/blob/main/LICENSE.md") }
                    SettingLink(R.string.source_hkg, "source-hkg") { openLink("https://www.immd.gov.hk/hkt/service/travel_document/visa_free_access.html") }
                    SettingLink(R.string.source_mac, "source-mac") { openLink("https://www.dsi.gov.mo/en/visa") }
                    SettingLink(R.string.policy_sources, "source-policy") { openLink("$repositoryURL/tree/main/where-can-i-go-ios/whereCanIGo/Resources/Source") }
                    Text(stringResource(R.string.wikipedia_attribution))
                }
            }
        }
    }
    if (confirm) AlertDialog(onDismissRequest = { if (!busy) confirm = false },
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
                        document = null; plan = null; importUri = null; confirm = false
                    }
                } catch (failure: Exception) { state.reportError(R.string.backup_import_error, failure) }
                finally { busy = false }
            }
        }) { Text(stringResource(R.string.restore_data)) } },
        dismissButton = { TextButton(enabled = !busy, onClick = { confirm = false }) { Text(stringResource(R.string.cancel)) } })
}

@Composable
private fun SettingLink(label: Int, tag: String, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = Modifier.fillMaxWidth().testTag(tag)) {
        Row(Modifier.padding(16.dp)) {
            Text(stringResource(label), Modifier.weight(1f))
            AppIcon(R.drawable.ic_chevron_right)
        }
    }
}
