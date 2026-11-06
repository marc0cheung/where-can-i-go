package com.marcocheung.wherecanigo.ui

import android.content.ActivityNotFoundException
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.Canvas as AndroidCanvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.marcocheung.wherecanigo.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileEditorPage(state: AppState, onBack: () -> Unit) {
    val context = LocalContext.current
    val activity = LocalActivity.current
    val scope = rememberCoroutineScope()
    var name by rememberSaveable { mutableStateOf(state.profile.name) }
    var passport by rememberSaveable { mutableStateOf(state.data.passportCode) }
    var passportPicker by rememberSaveable { mutableStateOf(false) }
    var photoMenu by remember { mutableStateOf(false) }
    var sourcePath by rememberSaveable { mutableStateOf<String?>(null) }
    var avatarPath by rememberSaveable { mutableStateOf<String?>(null) }
    var removed by rememberSaveable { mutableStateOf(false) }
    var photoToCrop by rememberSaveable { mutableStateOf<String?>(null) }
    var newPhoto by rememberSaveable { mutableStateOf(false) }
    var zoom by rememberSaveable { mutableFloatStateOf(state.profile.photoCrop?.zoom ?: 1f) }
    var offsetX by rememberSaveable { mutableFloatStateOf(state.profile.photoCrop?.offsetX ?: 0f) }
    var offsetY by rememberSaveable { mutableFloatStateOf(state.profile.photoCrop?.offsetY ?: 0f) }
    var busy by remember { mutableStateOf(false) }
    var cameraPath by rememberSaveable { mutableStateOf<String?>(null) }
    val draftFolder = rememberSaveable { File(context.cacheDir, "profile-drafts/${PersonalVisa.newId()}").absolutePath }
    val attached = remember { java.util.concurrent.atomic.AtomicBoolean(true) }
    fun clearDrafts() {
        val folder = File(draftFolder)
        folder.listFiles()?.forEach { if (!it.delete()) android.util.Log.e("Profile", "Cannot clear draft photo") }
        if (folder.exists() && !folder.delete()) android.util.Log.e("Profile", "Cannot clear photo draft folder")
    }
    DisposableEffect(draftFolder) {
        onDispose {
            if (activity?.isChangingConfigurations != true) {
                attached.set(false)
                clearDrafts()
            }
        }
    }
    fun stage(read: () -> ByteArray) {
        busy = true
        scope.launch {
            try {
                val path = withContext(kotlinx.coroutines.NonCancellable + Dispatchers.IO) {
                    val folder = File(draftFolder)
                    if (!folder.isDirectory && !folder.mkdirs()) throw IOException("Cannot create photo draft folder")
                    val prepared = prepareProfilePhoto(read())
                    val result = File(folder, "${PersonalVisa.newId()}.jpg").apply { writeBytes(prepared) }.absolutePath
                    if (!attached.get()) clearDrafts()
                    result
                }
                photoToCrop = path
                newPhoto = true
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (failure: Exception) { state.reportError(R.string.profile_photo_error, failure) }
            finally { busy = false }
        }
    }
    val album = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) stage { context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw IOException("Cannot read profile photo") }
    }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { saved ->
        val path = cameraPath
        cameraPath = null
        if (path != null) {
            if (saved) stage {
                val file = File(path)
                try { file.readBytes() } finally { if (!file.delete()) android.util.Log.e("Profile", "Cannot delete camera photo") }
            }
            else File(path).takeIf(File::exists)?.let { if (!it.delete()) state.reportError(R.string.attachment_delete_error, IOException("Cannot delete camera photo")) }
        }
    }
    val avatar by produceState<ByteArray?>(if (removed) null else state.profile.photoData, avatarPath, removed, state.profile.photoData) {
        value = if (removed) null else if (avatarPath == null) state.profile.photoData
            else withContext(Dispatchers.IO) { File(requireNotNull(avatarPath)).readBytes() }
    }
    androidx.activity.compose.BackHandler(onBack = onBack)
    Scaffold(modifier = Modifier.testTag("page-profile"), topBar = {
        TopAppBar(title = { Text(stringResource(R.string.edit_profile)) },
            navigationIcon = { IconButton(onClick = onBack, modifier = Modifier.testTag("page-back")) {
                Icon(painterResource(R.drawable.ic_close), stringResource(R.string.cancel))
            } },
            actions = { TextButton(enabled = !busy && !state.profileLoadFailed, onClick = {
                busy = true
                scope.launch {
                    try {
                        val draft = withContext(Dispatchers.IO) {
                            UserProfile(name,
                                if (removed) null else avatarPath?.let { File(it).readBytes() } ?: state.profile.photoData,
                                if (removed) null else sourcePath?.let { File(it).readBytes() } ?: state.profile.photoSourceData,
                                if (removed) null else if (sourcePath != null) ProfilePhotoCrop(zoom, offsetX, offsetY) else state.profile.photoCrop)
                        }
                        if (state.saveProfile(draft, passport)) onBack()
                    } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
                    catch (failure: Exception) { state.reportError(R.string.profile_save_error, failure) }
                    finally { busy = false }
                }
            }, modifier = Modifier.testTag("profile-save")) { Text(stringResource(R.string.save_profile)) } })
    }) { insets ->
        Column(Modifier.padding(insets).fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
            if (state.profileLoadFailed) {
                ErrorText(stringResource(R.string.profile_load_error))
                TextButton(onClick = {
                    state.loadProfile()
                    if (!state.profileLoadFailed) {
                        name = state.profile.name
                        zoom = state.profile.photoCrop?.zoom ?: 1f
                        offsetX = state.profile.photoCrop?.offsetX ?: 0f
                        offsetY = state.profile.photoCrop?.offsetY ?: 0f
                    }
                }) { Text(stringResource(R.string.retry)) }
            }
            Box {
                IconButton(enabled = !busy, onClick = { photoMenu = true },
                    modifier = Modifier.size(96.dp).testTag("profile-photo")) { Avatar(88, avatar) }
                DropdownMenu(expanded = photoMenu, onDismissRequest = { photoMenu = false }) {
                    if (avatar != null) DropdownMenuItem(text = { Text(stringResource(R.string.edit_photo)) }, onClick = {
                        photoMenu = false
                        val source = sourcePath
                        newPhoto = false
                        if (source != null) photoToCrop = source else {
                            busy = true
                            scope.launch {
                                try {
                                    val path = withContext(Dispatchers.IO) {
                                        File(draftFolder).apply { if (!isDirectory && !mkdirs()) throw IOException("Cannot create draft folder") }
                                        File(draftFolder, "${PersonalVisa.newId()}.jpg").apply {
                                            writeBytes(state.profile.photoSourceData ?: state.profile.photoData ?: throw IOException("No photo"))
                                        }.absolutePath
                                    }
                                    photoToCrop = path
                                } catch (failure: IOException) { state.reportError(R.string.profile_photo_error, failure) }
                                finally { busy = false }
                            }
                        }
                    })
                    DropdownMenuItem(text = { Text(stringResource(R.string.take_photo)) }, onClick = {
                        photoMenu = false
                        try {
                            val folder = File(context.cacheDir, "camera").apply { if (!isDirectory && !mkdirs()) throw IOException("Cannot create camera folder") }
                            val file = File(folder, "${PersonalVisa.newId()}.jpg")
                            cameraPath = file.absolutePath
                            camera.launch(FileProvider.getUriForFile(context, "${context.packageName}.files", file))
                        } catch (failure: ActivityNotFoundException) { state.reportError(R.string.camera_unavailable, failure) }
                        catch (failure: IOException) { state.reportError(R.string.profile_photo_error, failure) }
                        catch (failure: SecurityException) { state.reportError(R.string.profile_photo_error, failure) }
                    })
                    DropdownMenuItem(text = { Text(stringResource(R.string.choose_album)) }, onClick = {
                        photoMenu = false
                        try { album.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                        catch (failure: ActivityNotFoundException) { state.reportError(R.string.profile_photo_error, failure) }
                    })
                    if (avatar != null) DropdownMenuItem(text = { Text(stringResource(R.string.remove_photo)) }, onClick = {
                        photoMenu = false; removed = true; avatarPath = null; sourcePath = null
                    })
                }
            }
            if (busy) CircularProgressIndicator()
            OutlinedTextField(name, { name = it }, label = { Text(stringResource(R.string.profile_name)) },
                singleLine = true, modifier = Modifier.fillMaxWidth().testTag("profile-name"))
            Surface(onClick = { passportPicker = true }, modifier = Modifier.fillMaxWidth().testTag("change-passport"),
                shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainer) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.passport), Modifier.weight(1f))
                    Text(state.countriesByCode[passport]?.let { "${it.flag} ${it.localizedName(currentLocale())}" } ?: passport)
                    AppIcon(R.drawable.ic_chevron_right, Modifier.padding(start = 8.dp))
                }
            }
        }
    }
    if (passportPicker) FullScreenSheet(stringResource(R.string.change_passport), { passportPicker = false }, null) {
        PassportPicker(state, passport, showWelcome = false) { passport = it; passportPicker = false }
    }
    photoToCrop?.let { path ->
        ProfileCropSheet(state, path, if (newPhoto) ProfilePhotoCrop() else ProfilePhotoCrop(zoom, offsetX, offsetY),
            onCancel = { photoToCrop = null }) { bytes, crop ->
            try {
                val file = File(draftFolder, "${PersonalVisa.newId()}.jpg")
                file.writeBytes(bytes)
                avatarPath = file.absolutePath; sourcePath = path; removed = false
                zoom = crop.zoom; offsetX = crop.offsetX; offsetY = crop.offsetY
                photoToCrop = null
            } catch (failure: IOException) { state.reportError(R.string.profile_photo_error, failure) }
        }
    }
}

@Composable
private fun ProfileCropSheet(state: AppState, sourcePath: String, initial: ProfilePhotoCrop,
    onCancel: () -> Unit, onChoose: (ByteArray, ProfilePhotoCrop) -> Unit) {
    val bitmap by produceState<Bitmap?>(null, sourcePath) {
        value = withContext(Dispatchers.IO) {
            runCatching { decodeProfilePhoto(File(sourcePath).readBytes()) }
                .onFailure { state.reportError(R.string.profile_photo_error, it) }.getOrNull()
        }
    }
    var zoom by rememberSaveable(sourcePath) { mutableFloatStateOf(initial.zoom.coerceIn(1f, 6f)) }
    var x by rememberSaveable(sourcePath) { mutableFloatStateOf(initial.offsetX) }
    var y by rememberSaveable(sourcePath) { mutableFloatStateOf(initial.offsetY) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    fun clamp(image: Bitmap) {
        val scale = maxOf(1f / image.width, 1f / image.height) * zoom
        x = x.coerceIn(-(image.width * scale - 1f) / 2f, (image.width * scale - 1f) / 2f)
        y = y.coerceIn(-(image.height * scale - 1f) / 2f, (image.height * scale - 1f) / 2f)
    }
    FullScreenSheet(stringResource(R.string.move_scale), onCancel, {
        val image = bitmap ?: return@FullScreenSheet
        clamp(image); busy = true
        scope.launch {
            try {
                val crop = ProfilePhotoCrop(zoom, x, y)
                val bytes = withContext(Dispatchers.IO) { cropProfilePhoto(image, crop) }
                onChoose(bytes, crop)
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (failure: Exception) { state.reportError(R.string.profile_photo_error, failure) }
            finally { busy = false }
        }
    }, doneEnabled = bitmap != null && !busy, testTag = "photo-crop") {
        val image = bitmap
        if (image == null) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        else Column(Modifier.fillMaxSize().background(Color.Black).padding(16.dp)) {
            val imageBitmap = remember(image) { image.asImageBitmap() }
            Canvas(Modifier.fillMaxWidth().weight(1f).pointerInput(image) {
                detectTransformGestures { _, pan, factor, _ ->
                    zoom = (zoom * factor).coerceIn(1f, 6f)
                    val diameter = (minOf(size.width, size.height) - 32).coerceAtLeast(1).toFloat()
                    x += pan.x / diameter; y += pan.y / diameter; clamp(image)
                }
            }) {
                val diameter = (minOf(size.width, size.height) - 32).coerceAtLeast(1f)
                val scale = maxOf(diameter / image.width, diameter / image.height) * zoom
                val width = image.width * scale; val height = image.height * scale
                val clampedX = x.coerceIn(-(width / diameter - 1) / 2, (width / diameter - 1) / 2)
                val clampedY = y.coerceIn(-(height / diameter - 1) / 2, (height / diameter - 1) / 2)
                drawImage(imageBitmap, dstOffset = IntOffset((center.x + clampedX * diameter - width / 2).roundToInt(),
                    (center.y + clampedY * diameter - height / 2).roundToInt()), dstSize = IntSize(width.roundToInt(), height.roundToInt()))
                val mask = Path().apply {
                    fillType = PathFillType.EvenOdd
                    addRect(Rect(Offset.Zero, size))
                    addOval(Rect(center.x - diameter / 2, center.y - diameter / 2, center.x + diameter / 2, center.y + diameter / 2))
                }
                drawPath(mask, Color.Black.copy(alpha = 0.6f))
            }
            Text(stringResource(R.string.photo_zoom), color = Color.White)
            Slider(zoom, { zoom = it; clamp(image) }, valueRange = 1f..6f, modifier = Modifier.testTag("photo-zoom"))
        }
    }
}

internal fun decodeProfilePhoto(bytes: ByteArray, maximumPixelSize: Int = 2048): Bitmap =
    ImageDecoder.decodeBitmap(ImageDecoder.createSource(java.nio.ByteBuffer.wrap(bytes))) { decoder, info, _ ->
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        val ratio = minOf(1f, maximumPixelSize.toFloat() / maxOf(info.size.width, info.size.height))
        decoder.setTargetSize((info.size.width * ratio).toInt().coerceAtLeast(1), (info.size.height * ratio).toInt().coerceAtLeast(1))
    }

internal fun prepareProfilePhoto(bytes: ByteArray, maximumPixelSize: Int = 2048): ByteArray {
    val bitmap = decodeProfilePhoto(bytes, maximumPixelSize)
    try { return jpegProfile(bitmap) } finally { bitmap.recycle() }
}

internal fun cropProfilePhoto(image: Bitmap, crop: ProfilePhotoCrop): ByteArray {
    val output = Bitmap.createBitmap(512, 512, Bitmap.Config.ARGB_8888)
    val scale = maxOf(512f / image.width, 512f / image.height) * crop.zoom.coerceIn(1f, 6f)
    val w = image.width * scale; val h = image.height * scale
    val x = (crop.offsetX * 512).coerceIn(-(w - 512) / 2, (w - 512) / 2)
    val y = (crop.offsetY * 512).coerceIn(-(h - 512) / 2, (h - 512) / 2)
    try {
        AndroidCanvas(output).drawBitmap(image, null, RectF(256 + x - w / 2, 256 + y - h / 2,
            256 + x + w / 2, 256 + y + h / 2), Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
        return jpegProfile(output)
    } finally { output.recycle() }
}

private fun jpegProfile(bitmap: Bitmap) = ByteArrayOutputStream().use {
    if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it)) throw IOException("Cannot encode photo")
    it.toByteArray()
}
