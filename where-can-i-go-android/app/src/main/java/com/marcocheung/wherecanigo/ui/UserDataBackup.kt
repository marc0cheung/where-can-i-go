package com.marcocheung.wherecanigo.ui

import android.content.Context
import android.util.Base64
import com.marcocheung.wherecanigo.R
import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream
import java.io.IOException
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

internal class FriendsBackupUnsupported : IOException("Friends and sharing identity are not supported yet")
internal data class BackupFile(val name: String, val bytes: ByteArray)
internal data class BackupDocument(val json: JSONObject, val attachments: Map<String, List<BackupFile>>,
    val photo: BackupFile?, val skippedMedia: Int)
internal data class RestorePlan(val data: AppData, val profile: UserProfile,
    val attachments: Map<String, List<BackupFile>>, val skippedRecords: Int, val skippedMedia: Int)

internal object UserDataBackup {
    const val maxBytes = 100 * 1024 * 1024
    private val imageExtensions = setOf("jpg", "jpeg", "png", "webp", "gif", "heic", "heif", "bmp")
    private val codePattern = Regex("[A-Z]{3}")
    private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it) }
    private fun safeName(name: String) = name.isNotEmpty() && name.length <= 255 && !name.startsWith(".") &&
        !name.contains("..") && name.none { it == '/' || it == '\\' || it.isISOControl() }
    private fun supported(file: BackupFile, profile: Boolean) = file.bytes.isNotEmpty() &&
        file.bytes.size <= (if (profile) 10 else 20) * 1024 * 1024 &&
        (file.name.substringAfterLast('.').lowercase() in imageExtensions ||
            (!profile && file.name.substringAfterLast('.').equals("pdf", true)))

    private fun media(file: BackupFile): JSONObject {
        require(safeName(file.name))
        val mime = android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.name.substringAfterLast('.').lowercase())
            ?: "application/octet-stream"
        return JSONObject().put("fileName", file.name).put("mimeType", mime)
            .put("byteCount", file.bytes.size).put("sha256", digest(file.bytes))
            .put("data", Base64.encodeToString(file.bytes, Base64.NO_WRAP))
    }

    fun export(context: Context, data: AppData, profile: UserProfile, includePhoto: Boolean,
        includeAttachments: Boolean): Pair<ByteArray, Int> {
        val defaults = BundledRepository.loadPolicy(context, data.passportCode).entries.associateBy { it.countryCode }
        val overrides = data.defaultVisas.filter { defaults[it.countryCode] != it }
        val removed = defaults.keys - data.defaultVisas.map { it.countryCode }.toSet()
        var skipped = 0
        val profileJson = JSONObject().putOpt("displayName", profile.name.trim().takeIf(String::isNotEmpty))
        if (includePhoto) profile.photoData?.let { bytes ->
            val file = BackupFile("profile.jpg", bytes)
            if (supported(file, true)) profileJson.put("photo", media(file)) else skipped++
        }
        val visas = data.personalVisas.map { visa ->
            visa.toJson().apply {
                remove("attachmentFileNames")
                put("expiryDate", visa.expiryDate.toString())
                visa.effectiveDate?.let { put("effectiveDate", it.toString()) }
                if (includeAttachments) {
                    put("attachments", JSONArray(visa.attachmentFileNames.mapNotNull { name ->
                        require(safeName(name))
                        val bytes = VisaAttachmentStore.file(context, name, visa.id).readBytes()
                        val file = BackupFile(name, bytes)
                        if (supported(file, false)) media(file) else { skipped++; null }
                    }))
                }
            }
        }
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val root = JSONObject().put("format", "wherecanigo.backup").put("schemaVersion", 1)
            .put("kind", "fullBackup").put("exportedAt", Instant.now().toString())
            .put("app", JSONObject().put("version", packageInfo.versionName).put("build", packageInfo.longVersionCode.toString()).put("platform", "Android"))
            .put("profile", profileJson).put("passport", JSONObject().put("code", data.passportCode))
            .put("entryPolicies", JSONObject().put("overrides", JSONArray(overrides.map { it.toJson() }))
                .put("removedCountryCodes", JSONArray(removed.toList())))
            .put("personalVisas", JSONArray(visas)).put("visits", JSONArray(data.visitRecords.map { it.toJson(true) }))
            .put("wishlist", JSONArray(data.plannedTripRecords.map { it.toJson(true) }))
        val bytes = root.toString(2).toByteArray(Charsets.UTF_8)
        require(bytes.size <= maxBytes) { "Backup exceeds 100 MiB" }
        return bytes to skipped
    }

    fun decode(input: InputStream): BackupDocument {
        val bytes = input.readNBytes(maxBytes + 1)
        require(bytes.size <= maxBytes) { "Backup exceeds 100 MiB" }
        val root = JSONObject(bytes.toString(Charsets.UTF_8))
        require(root.getString("format") == "wherecanigo.backup" && root.getInt("schemaVersion") == 1 &&
            root.getString("kind") == "fullBackup") { "Unsupported backup format, version or kind" }
        Instant.parse(root.getString("exportedAt"))
        if (!root.isNull("sharingIdentity") || (root.optJSONArray("friends")?.length() ?: 0) > 0)
            throw FriendsBackupUnsupported()
        root.optJSONObject("passport")?.let { require(it.getString("code") in SupportedPassports) }
        val attachments = mutableMapOf<String, List<BackupFile>>()
        var skipped = 0
        fun unpack(json: JSONObject, profile: Boolean): BackupFile? {
            val name = json.getString("fileName")
            require(safeName(name)) { "Unsafe media file name" }
            val declared = json.getInt("byteCount")
            require(declared > 0 && declared <= maxBytes)
            val data = Base64.decode(json.getString("data"), Base64.DEFAULT)
            require(data.size == declared && digest(data).equals(json.getString("sha256"), true)) { "Corrupted media" }
            val file = BackupFile(name, data)
            if (!supported(file, profile)) { skipped++; return null }
            if (profile) {
                val bitmap = decodeProfilePhoto(data)
                bitmap.recycle()
            }
            return file
        }
        fun validateRecords(key: String) {
            val records = root.getJSONArray(key).objects()
            val ids = mutableSetOf<String>()
            records.forEach { record ->
                val rawId = record.getString("id")
                require(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").matches(rawId))
                val id = UUID.fromString(rawId).toString().uppercase()
                require(ids.add(id)) { "Duplicate record ID" }
                record.put("id", id)
                require(codePattern.matches(record.getString("countryCode"))) { "Invalid country code" }
                listOf("startDate", "endDate", "expiryDate", "effectiveDate").forEach { date ->
                    record.nullableString(date)?.let { require(Regex("\\d{4}-\\d{2}-\\d{2}").matches(it)); LocalDate.parse(it) }
                }
                if (key == "personalVisas") {
                    record.getString("visaType"); record.getString("duration"); record.getString("expiryDate")
                    if (!record.isNull("attachments")) {
                        val names = mutableSetOf<String>()
                        attachments[id] = record.getJSONArray("attachments").objects().mapNotNull { item ->
                            require(names.add(item.getString("fileName").lowercase())) { "Duplicate attachment" }
                            unpack(item, false)
                        }
                    }
                }
                if (key == "wishlist") {
                    Instant.parse(record.getString("createdAt"))
                    if (!record.isNull("estimatedDays")) {
                        val number = record.get("estimatedDays")
                        require(number is Number && number.toString().toLongOrNull() != null)
                        require(number.toLong() > 0)
                    }
                }
            }
        }
        listOf("personalVisas", "visits", "wishlist").forEach(::validateRecords)
        root.optJSONObject("entryPolicies")?.let { policies ->
            val codes = mutableSetOf<String>()
            policies.getJSONArray("overrides").objects().forEach {
                require(codePattern.matches(it.getString("countryCode")) && codes.add(it.getString("countryCode")))
                it.getString("category")
            }
            val removals = policies.getJSONArray("removedCountryCodes")
            val removalCodes = mutableSetOf<String>()
            for (i in 0 until removals.length()) {
                val code = removals.getString(i)
                require(codePattern.matches(code) && removalCodes.add(code) && code !in codes)
            }
        }
        val photo = root.optJSONObject("profile")?.optJSONObject("photo")?.let { unpack(it, true) }
        return BackupDocument(root, attachments, photo, skipped)
    }

    fun plan(context: Context, backup: BackupDocument, local: AppData, localProfile: UserProfile, replace: Boolean): RestorePlan {
        val root = backup.json
        val passport = if (replace) root.optJSONObject("passport")?.getString("code") ?: local.passportCode else local.passportCode
        var skipped = 0
        val policies = root.optJSONObject("entryPolicies")
        val entries = if (replace && (policies != null || passport != local.passportCode)) {
            val result = BundledRepository.loadPolicy(context, passport).entries.associateBy { it.countryCode }.toMutableMap()
            policies?.let {
                val removed = it.getJSONArray("removedCountryCodes")
                for (i in 0 until removed.length()) result.remove(removed.getString(i))
                it.getJSONArray("overrides").objects().forEach { record ->
                    if (VisaCategory.entries.none { category -> category.jsonValue == record.getString("category") }) skipped++
                    else DefaultVisaEntry.fromJson(record).let { entry -> result[entry.countryCode] = entry }
                }
            }
            result.values.toList()
        } else local.defaultVisas
        val media = mutableMapOf<String, List<BackupFile>>()
        val visas = if (replace) mutableListOf() else local.personalVisas.toMutableList()
        root.getJSONArray("personalVisas").objects().forEach { record ->
            val id = record.getString("id")
            if (!replace && visas.any { it.id == id }) { skipped++; return@forEach }
            val existing = local.personalVisas.firstOrNull { it.id == id }
            val files = backup.attachments[id]
            if (files != null) media[id] = files
            val native = JSONObject(record.toString()).put("expiryDate", LocalDate.parse(record.getString("expiryDate")).toIsoInstant())
            record.nullableString("effectiveDate")?.let { native.put("effectiveDate", LocalDate.parse(it).toIsoInstant()) }
            native.put("attachmentFileNames", JSONArray(if (files == null && replace) existing?.attachmentFileNames.orEmpty() else emptyList<String>()))
            visas.add(PersonalVisa.fromJson(native))
        }
        val visits = if (replace) mutableListOf() else local.visitRecords.toMutableList()
        root.getJSONArray("visits").objects().forEach {
            val visit = Visit.fromJson(it, true)
            if (visits.any { row -> row.id == visit.id }) skipped++ else visits.add(visit)
        }
        val plans = if (replace) mutableListOf() else local.plannedTripRecords.toMutableList()
        root.getJSONArray("wishlist").objects().forEach {
            val plan = PlannedTrip.fromJson(it, true)
            if (plans.any { row -> row.id == plan.id } || visits.any { visit -> visit.id == plan.id }) skipped++ else plans.add(plan)
        }
        val visited = visits.map { it.id }.toSet()
        plans.removeAll { it.id in visited }
        var profile = localProfile
        root.optJSONObject("profile")?.let {
            if (replace || profile.name.isBlank()) profile = profile.copy(name = it.nullableString("displayName")?.trim().orEmpty())
            if ((replace || profile.photoData == null) && backup.photo != null)
                profile = profile.copy(photoData = prepareProfilePhoto(backup.photo.bytes, 512), photoSourceData = null, photoCrop = null)
        }
        return RestorePlan(AppData(passport, entries, visas, JSONArray(visits.map { it.toJson() }), JSONArray(plans.map { it.toJson() })),
            profile, media, skipped, backup.skippedMedia)
    }

    fun restore(context: Context, state: AppState, plan: RestorePlan): Boolean {
        val staged = mutableListOf<Pair<String, String>>()
        val originalIds = state.data.personalVisas.map { it.id }.toSet()
        try {
            val visas = plan.data.personalVisas.map { visa ->
                val files = plan.attachments[visa.id] ?: return@map visa
                val names = files.map { file ->
                    VisaAttachmentStore.save(context, file.bytes, file.name.substringAfterLast('.').lowercase(), visa.id)
                        .also { staged.add(visa.id to it) }
                }
                visa.copy(attachmentFileNames = names)
            }
            if (!state.commitRestoredData(plan.data.copy(personalVisas = visas), plan.profile)) return false
            staged.clear()
            (originalIds + visas.map { it.id }).forEach { id ->
                state.pruneAttachments(id, visas.firstOrNull { it.id == id }?.attachmentFileNames.orEmpty())
            }
            return true
        } finally {
            staged.forEach { (id, name) ->
                try { VisaAttachmentStore.delete(context, name, id) }
                catch (failure: IOException) { state.reportError(R.string.attachment_delete_error, failure) }
            }
        }
    }
}
