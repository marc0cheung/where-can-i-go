package com.marcocheung.wherecanigo.ui

import android.content.Context
import android.content.ActivityNotFoundException
import android.util.Log
import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import android.graphics.ImageDecoder
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.webkit.MimeTypeMap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.LocalActivity
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.marcocheung.wherecanigo.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.time.LocalDate

/** Editable personal visa fields shared by the Entry Policy and Visa Details sheets. */
data class VisaDraft(
    val countryCode: String? = null,
    val visaType: String = "",
    val duration: String = "",
    val expiryDate: LocalDate? = null,
    val hasEffectiveDate: Boolean = false,
    val effectiveDate: LocalDate? = null,
    val notes: String = "",
    val coverage: VisaCoverage = VisaCoverage.IssuingCountry,
    val attachments: List<String> = emptyList(),
) {
    /** Port of iOS `DateInputPolicy.isValidVisaPeriod`. */
    val hasValidPeriod: Boolean
        get() = expiryDate != null && (!hasEffectiveDate || (effectiveDate != null && !effectiveDate.isAfter(expiryDate)))

    val isComplete: Boolean
        get() = visaType.isNotBlank() && duration.isNotBlank() && hasValidPeriod

    fun toVisa(id: String, code: String) = PersonalVisa.create(
        id = id,
        countryCode = code,
        visaType = visaType,
        duration = duration,
        expiryDate = expiryDate!!,
        effectiveDate = if (hasEffectiveDate) effectiveDate else null,
        notes = notes.ifEmpty { null },
        attachmentFileNames = attachments,
        coverage = coverage,
    )

    companion object {
        val Saver = listSaver<VisaDraft, String>(
            save = {
                listOf(it.countryCode.orEmpty(), it.visaType, it.duration, it.expiryDate?.toString().orEmpty(),
                    it.hasEffectiveDate.toString(), it.effectiveDate?.toString().orEmpty(), it.notes, it.coverage.name) +
                    it.attachments
            },
            restore = {
                VisaDraft(it[0].ifEmpty { null }, it[1], it[2], it[3].takeIf(String::isNotEmpty)?.let(LocalDate::parse),
                    it[4].toBoolean(), it[5].takeIf(String::isNotEmpty)?.let(LocalDate::parse),
                    it[6], VisaCoverage.valueOf(it[7]), it.drop(8))
            },
        )

        fun from(visa: PersonalVisa) = VisaDraft(
            countryCode = visa.countryCode,
            visaType = visa.visaType,
            duration = visa.duration,
            expiryDate = visa.expiryDate,
            hasEffectiveDate = visa.effectiveDate != null,
            effectiveDate = visa.effectiveDate,
            notes = visa.notes.orEmpty(),
            coverage = visa.coverage,
            attachments = visa.attachmentFileNames,
        )
    }
}

@Composable
fun CleanupVisaAttachments(state: AppState, visaId: String, retained: () -> List<String>) {
    val activity = LocalActivity.current
    val keep by rememberUpdatedState(retained)
    DisposableEffect(visaId) {
        onDispose {
            if (activity?.isChangingConfigurations != true) {
                val saved = state.data.personalVisas.firstOrNull { it.id == visaId }?.attachmentFileNames.orEmpty()
                state.pruneAttachments(visaId, keep() + saved)
            }
        }
    }
}

@Composable
fun PersonalVisaFields(draft: VisaDraft, visaId: String, onChange: (VisaDraft) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        if (draft.countryCode in VisaCoverage.schengenCountryCodes) {
            FormCard {
                Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.schengen_toggle), Modifier.weight(1f))
                    Switch(
                        checked = draft.coverage == VisaCoverage.SchengenArea,
                        onCheckedChange = {
                            onChange(draft.copy(coverage = if (it) VisaCoverage.SchengenArea else VisaCoverage.IssuingCountry))
                        },
                        modifier = Modifier.testTag("schengen-toggle"),
                    )
                }
            }
        }
        Column {
            SectionLabel(stringResource(R.string.visa_type_caps))
            FormCard {
                FormTextField(draft.visaType, { onChange(draft.copy(visaType = it)) },
                    stringResource(R.string.visa_type_hint), Modifier.testTag("visa-type"), clearable = true)
            }
        }
        Column {
            SectionLabel(stringResource(R.string.duration_per_visit))
            FormCard {
                FormTextField(draft.duration, { onChange(draft.copy(duration = it)) },
                    stringResource(R.string.duration_visit_hint), Modifier.testTag("visa-duration"), clearable = true)
            }
        }
        Column {
            SectionLabel(stringResource(R.string.validity_dates))
            FormCard { ValidityFields(draft, onChange) }
        }
        Column {
            SectionLabel(stringResource(R.string.notes_optional))
            FormCard {
                FormTextField(draft.notes, { onChange(draft.copy(notes = it)) },
                    stringResource(R.string.remark_hint), Modifier.testTag("visa-notes"), singleLine = false)
            }
        }
        HorizontalDivider()
        Column {
            SectionLabel(stringResource(R.string.attachments_optional))
            AttachmentsSection(visaId, draft.attachments) { onChange(draft.copy(attachments = it)) }
        }
    }
}

/** Port of iOS `VisaValidityFields`. */
@Composable
private fun ValidityFields(draft: VisaDraft, onChange: (VisaDraft) -> Unit) {
    Column {
        Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.has_effective_date), Modifier.weight(1f))
            Switch(
                checked = draft.hasEffectiveDate,
                onCheckedChange = { onChange(draft.copy(hasEffectiveDate = it, effectiveDate = if (it) draft.effectiveDate else null)) },
                modifier = Modifier.testTag("has-effective-date"),
            )
        }
        if (draft.hasEffectiveDate) {
            DateInputRow(
                label = stringResource(R.string.effective_date),
                date = draft.effectiveDate,
                onDateChange = { onChange(draft.copy(effectiveDate = it)) },
                clearDescription = stringResource(R.string.clear_effective_date),
                maxDate = draft.expiryDate,
                testTag = "effective-date",
            )
        }
        DateInputRow(
            label = stringResource(R.string.expiry_date),
            date = draft.expiryDate,
            onDateChange = { onChange(draft.copy(expiryDate = it)) },
            clearDescription = stringResource(R.string.clear_expiry_date),
            defaultDate = LocalDate.now().plusYears(1),
            minDate = if (draft.hasEffectiveDate) draft.effectiveDate else null,
            testTag = "expiry-date",
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AttachmentsSection(visaId: String, names: List<String>, onChange: (List<String>) -> Unit) {
    val context = LocalContext.current
    val state = remember { AppState.get(context) }
    val scope = rememberCoroutineScope()
    var menu by remember { mutableStateOf(false) }
    var preview by rememberSaveable { mutableStateOf<String?>(null) }
    var cameraFile by rememberSaveable { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val current by androidx.compose.runtime.rememberUpdatedState(names)
    val change by rememberUpdatedState(onChange)
    fun store(load: () -> Pair<ByteArray, String>) {
        saving = true
        scope.launch {
            // Finish the write even if the editor closes, then discard its uncommitted file.
            val result = withContext(NonCancellable + Dispatchers.IO) {
                runCatching { load().let { (bytes, ext) -> VisaAttachmentStore.save(context, bytes, ext, visaId) } }
            }
            result.onSuccess { name ->
                if (isActive) change(current + name)
                else runCatching { VisaAttachmentStore.delete(context, name, visaId) }
                    .onFailure { state.reportError(R.string.attachment_delete_error, it) }
            }.onFailure { state.reportError(R.string.attachment_save_error, it) }
            saving = false
        }
    }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { saved ->
        val path = cameraFile ?: return@rememberLauncherForActivityResult
        cameraFile = null
        val file = File(path)
        if (saved) store {
            try {
                jpeg(file.readBytes()) to "jpg"
            } finally {
                if (file.exists() && !file.delete()) Log.e("VisaAttachments", "Cannot remove camera cache file")
            }
        } else if (file.exists() && !file.delete()) {
            state.reportError(R.string.attachment_delete_error, IOException("Cannot remove cancelled camera file"))
        }
    }
    val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) store { jpeg(readBytes(context, uri)) to "jpg" }
    }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) store {
            val mime = context.contentResolver.getType(uri)
            require(mime == "application/pdf" || mime?.startsWith("image/") == true) { "Unsupported attachment type" }
            val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "dat"
            readBytes(context, uri) to ext
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box {
            Surface(
                onClick = { menu = true },
                enabled = !saving,
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                modifier = Modifier.fillMaxWidth().testTag("add-attachment"),
            ) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (saving) androidx.compose.material3.CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else AppIcon(R.drawable.ic_attach, Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.add_attachment))
                }
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.take_photo)) },
                    leadingIcon = { AppIcon(R.drawable.ic_camera) },
                    onClick = {
                        menu = false
                        try {
                            val folder = File(context.cacheDir, "camera")
                            if (!folder.isDirectory && !folder.mkdirs()) throw IOException("Cannot create camera folder")
                            val file = File(folder, "${PersonalVisa.newId()}.jpg")
                            cameraFile = file.absolutePath
                            camera.launch(FileProvider.getUriForFile(context, "${context.packageName}.files", file))
                        } catch (failure: ActivityNotFoundException) {
                            cameraFile = null
                            state.reportError(R.string.camera_unavailable, failure)
                        } catch (failure: IOException) {
                            cameraFile = null
                            state.reportError(R.string.attachment_save_error, failure)
                        }
                    },
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.choose_album)) },
                    leadingIcon = { AppIcon(R.drawable.ic_photo) },
                    onClick = {
                        menu = false
                        photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    },
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.choose_file)) },
                    leadingIcon = { AppIcon(R.drawable.ic_folder) },
                    onClick = {
                        menu = false
                        files.launch(arrayOf("image/*", "application/pdf"))
                    },
                )
            }
        }
        if (names.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                names.forEach { name ->
                    AttachmentThumbnail(visaId, name, onTap = { preview = name }, onDelete = { onChange(names - name) })
                }
            }
        }
    }
    preview?.let { AttachmentPreview(visaId, it) { preview = null } }
}

@Composable
private fun AttachmentThumbnail(visaId: String, name: String, onTap: () -> Unit, onDelete: () -> Unit) {
    val context = LocalContext.current
    val isPdf = name.lowercase().endsWith(".pdf")
    val bitmap by produceState<Bitmap?>(null, visaId, name) {
        if (!isPdf) value = withContext(Dispatchers.IO) {
            runCatching { decodeSampled(VisaAttachmentStore.file(context, name, visaId), 240) }
                .onFailure { Log.e("VisaAttachments", "Cannot decode attachment thumbnail", it) }.getOrNull()
        }
    }
    Box(Modifier.padding(top = 6.dp, end = 6.dp).testTag("attachment-$name")) {
        Box(
            Modifier.size(80.dp).clip(RoundedCornerShape(8.dp))
                .border(1.dp, Color.Gray.copy(alpha = 0.3f), RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                .clickable(onClick = onTap).semantics { contentDescription = name },
            contentAlignment = Alignment.Center,
        ) {
            val image = bitmap
            when {
                isPdf -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    AppIcon(R.drawable.ic_doc, Modifier.size(28.dp), tint = Color(0xFFFF3B30))
                    Text("PDF", style = MaterialTheme.typography.labelSmall)
                }
                image != null -> Image(image.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                else -> AppIcon(R.drawable.ic_doc, Modifier.size(28.dp))
            }
        }
        androidx.compose.material3.IconButton(
            onClick = onDelete,
            modifier = Modifier.align(Alignment.TopEnd).offset(x = 10.dp, y = (-10).dp),
        ) {
            Icon(
                painterResource(R.drawable.ic_close),
                contentDescription = stringResource(R.string.delete),
                tint = Color.White,
                modifier = Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.6f)).padding(4.dp).size(16.dp),
            )
        }
    }
}

@Composable
private fun AttachmentPreview(visaId: String, name: String, onClose: () -> Unit) {
    val context = LocalContext.current
    val file = VisaAttachmentStore.file(context, name, visaId)
    val isPdf = name.lowercase().endsWith(".pdf")
    val pageCount by produceState<Int?>(null, file) {
        value = withContext(Dispatchers.IO) {
            runCatching {
                if (isPdf) ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use {
                    PdfRenderer(it).use { renderer -> renderer.pageCount }
                } else 1
            }.onFailure { Log.e("VisaAttachments", "Cannot open attachment", it) }.getOrDefault(0)
        }
    }
    FullScreenSheet(title = name, onCancel = onClose, onDone = onClose, testTag = "attachment-preview") {
        LazyColumn(
            Modifier.fillMaxSize().background(Color.Black),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            items(pageCount ?: 0) { index ->
                AttachmentPage(file, isPdf, index)
            }
            if (pageCount == 0) item {
                ErrorText(stringResource(R.string.attachment_preview_error))
            } else if (pageCount == null) item {
                androidx.compose.material3.CircularProgressIndicator(Modifier.padding(24.dp))
            }
        }
    }
}

@Composable
private fun AttachmentPage(file: File, isPdf: Boolean, index: Int) {
    val context = LocalContext.current
    var failed by remember(file, index) { mutableStateOf(false) }
    val bitmap by produceState<Bitmap?>(null, file, index) {
        value = withContext(Dispatchers.IO) {
            runCatching {
                if (isPdf) renderPdfPage(file, index, context.resources.displayMetrics.widthPixels.coerceAtMost(1600))
                else decodeSampled(file, 2048)
            }.onFailure { Log.e("VisaAttachments", "Cannot render attachment page", it) }
                .getOrElse { null }
        }
        failed = value == null
    }
    bitmap?.let {
        Image(it.asImageBitmap(), null, Modifier.fillMaxWidth(), contentScale = ContentScale.FillWidth)
    } ?: if (failed) {
        ErrorText(stringResource(R.string.attachment_preview_error))
    } else {
        Box(Modifier.fillMaxWidth().height(240.dp), contentAlignment = Alignment.Center) {
            androidx.compose.material3.CircularProgressIndicator()
        }
    }
}

private fun readBytes(context: Context, uri: Uri): ByteArray =
    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        ?: throw IOException("Cannot read attachment")

/** Re-encodes camera and album images as 85% JPEG, like iOS. */
private fun jpeg(bytes: ByteArray): ByteArray {
    val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(java.nio.ByteBuffer.wrap(bytes))) { decoder, _, _ ->
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
    }
    try {
        return ByteArrayOutputStream().use { out ->
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)) throw IOException("Cannot encode image")
            out.toByteArray()
        }
    } finally {
        bitmap.recycle()
    }
}

private fun decodeSampled(file: File, target: Int): Bitmap =
    ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        val scale = minOf(1f, target.toFloat() / maxOf(info.size.width, info.size.height))
        decoder.setTargetSize((info.size.width * scale).toInt().coerceAtLeast(1),
            (info.size.height * scale).toInt().coerceAtLeast(1))
    }

private fun renderPdfPage(file: File, index: Int, width: Int): Bitmap =
    ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
        PdfRenderer(descriptor).use { renderer ->
            renderer.openPage(index).use { page ->
                val renderWidth = minOf(width, (2400L * page.width / page.height).toInt()).coerceAtLeast(1)
                val height = (renderWidth.toLong() * page.height / page.width).coerceAtLeast(1).toInt()
                Bitmap.createBitmap(renderWidth, height, Bitmap.Config.ARGB_8888).also {
                    it.eraseColor(AndroidColor.WHITE)
                    page.render(it, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                }
            }
        }
    }
